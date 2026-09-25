#!/usr/bin/env bash
#===============================================================================
# tests/run_all_tests.sh
#
# OFFLINE (simulated) test-suite for the LiteLLM <-> OpenCode setup script.
#
# How it works:
#   - every external command the script touches (docker, apt-get, service,
#     systemctl, curl, powershell.exe, sudo) is replaced by a deterministic
#     stub from tests/helpers/stubbin
#   - /etc/docker writes are virtualized into a temporary FAKE_ROOT
#   - the Windows user profile is emulated under /mnt/c/Users/<Test User>
#     (a dedicated fake folder, never a real profile; removed on exit)
#   - every scenario runs the REAL script end-to-end and asserts on:
#       exit codes, generated config.yaml, generated opencode.json,
#       master-key consistency, daemon.json mirrors, docker run arguments,
#       container lifecycle and uninstall behavior
#
# Results:  tests/results/<test-name>.log  +  tests/results/summary.txt
#
# Usage:  bash tests/run_all_tests.sh
#===============================================================================
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_FILE="${ROOT_DIR}/LiteLLM.sh"
TESTS_DIR="${ROOT_DIR}/tests"
STUBBIN="${TESTS_DIR}/helpers/stubbin"
RESULTS_DIR="${TESTS_DIR}/results"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"

mkdir -p "$RESULTS_DIR"

#-------------------------------------------------------------------------------
# Globals
#-------------------------------------------------------------------------------
PASS=0; FAIL=0; SKIP=0
T_NAME=""
T_WORK=""
T_WORKSTATE=""
FAKE_ROOT=""
HOME_DIR=""
REAL_DAEMON_STATE=""   # "", "was-present", "seeded-absent"
REAL_DAEMON_BACKUP=""
CREATED_PROFILE_DIRS=()
CURRENT_LOG=""

ALL7_MODELS=$'qwen-2.5-coder-32b\nllama-3.3-70b-versatile\ndeepseek/deepseek-chat-v3:free\ndeepseek/deepseek-r1:free\ngemini-2.0-flash\nllama3.1-70b\ncodestral-latest'
GROQ2_MODELS=$'qwen-2.5-coder-32b\nllama-3.3-70b-versatile'
OR2_MODELS=$'deepseek/deepseek-chat-v3:free\ndeepseek/deepseek-r1:free'
GEMINI1_MODELS='gemini-2.0-flash'

cleanup() {
  # remove fake Windows profile dirs created for the tests (never real ones)
  local d
  for d in "${CREATED_PROFILE_DIRS[@]:-}"; do
    [ -n "$d" ] && rm_rf_sudo "$d"
  done
  # restore host daemon.json if the backup test seeded it
  if [ "$REAL_DAEMON_STATE" = "was-present" ] && [ -f "$REAL_DAEMON_BACKUP" ]; then
    cp_sudo "$REAL_DAEMON_BACKUP" /etc/docker/daemon.json
  elif [ "$REAL_DAEMON_STATE" = "seeded-absent" ]; then
    rm_f_sudo /etc/docker/daemon.json
  fi
  [ -n "$T_WORK" ] && [ -d "$T_WORK" ] && rm -rf "$T_WORK"
  return 0
}
trap cleanup EXIT INT TERM

#-------------------------------------------------------------------------------
# Small helpers
#-------------------------------------------------------------------------------
msg()  { echo "[SUITE] $*"; }
pass_test() { PASS=$((PASS+1)); msg "PASS  ${T_NAME}"; echo "PASS  ${T_NAME}" >> "$SUMMARY_FILE"; }
skip_test() { SKIP=$((SKIP+1)); msg "SKIP  ${T_NAME} - $*"; echo "SKIP  ${T_NAME} - $*" >> "$SUMMARY_FILE"; }
fail_test() { FAIL=$((FAIL+1)); msg "FAIL  ${T_NAME} - $*"; echo "FAIL  ${T_NAME} - $*" >> "$SUMMARY_FILE"; }

# root/sudo helpers (work as root or via sudo, otherwise fail softly)
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi
}
rm_rf_sudo() { as_root rm -rf "$1" 2>/dev/null || true; }
rm_f_sudo()  { as_root rm -f "$1" 2>/dev/null || true; }
cp_sudo()    { as_root cp "$1" "$2" 2>/dev/null || true; }

start_test() {
  T_NAME="$1"
  CURRENT_LOG="${RESULTS_DIR}/${T_NAME}.log"
  : > "$CURRENT_LOG"
}

#-------------------------------------------------------------------------------
# Fresh isolated environment per test
#-------------------------------------------------------------------------------
fresh_env() {
  # deterministic start: make sure no docker stub is left in STUBBIN
  # (tests that need it install it explicitly, e.g. T16)
  rm -f "${STUBBIN}/docker"
  T_WORK="$(mktemp -d /tmp/litellm-test.XXXXXX)"
  T_WORKSTATE="${T_WORK}/state"
  FAKE_ROOT="${T_WORK}/fakeroot"
  HOME_DIR="${T_WORK}/home"
  mkdir -p "$T_WORKSTATE" "$FAKE_ROOT" "$HOME_DIR"
  : > "${T_WORKSTATE}/docker-calls.log"
  : > "${T_WORKSTATE}/apt-calls.log"
  : > "${T_WORKSTATE}/containers.txt"
  : > "${T_WORKSTATE}/container-running.txt"
  : > "${T_WORKSTATE}/images.txt"
  # reset shared fake Windows profiles so every test starts clean
  for u in "Test User" "Ali Rezaei"; do
    d="/mnt/c/Users/${u}/.config"
    [ -w "$d" ] && rm -rf "$d"
  done
  return 0 2>/dev/null || true
  # mirror the host /etc/docker/daemon.json into the virtual root (if any),
  # so the script's backup branch behaves consistently
  if [ -f /etc/docker/daemon.json ]; then
    mkdir -p "${FAKE_ROOT}/etc/docker"
    cp /etc/docker/daemon.json "${FAKE_ROOT}/etc/docker/daemon.json"
  fi
}

# Runs the real script inside the isolated environment.
# Expected input (menu choices / keys) is piped in by the caller.
run_script() { # optional $1 = path of the script copy to run (default: the real one)
  local script_file="${1:-$SCRIPT_FILE}"
  env -u DOCKER_PULL_FAIL -u DOCKER_APT_FAIL \
    HOME="$HOME_DIR" \
    PATH="${STUBBIN}:${PATH}" \
    STUBBIN="$STUBBIN" \
    T_WORKSTATE="$T_WORKSTATE" \
    FAKE_ROOT="$FAKE_ROOT" \
    HEALTH_CODE="${T_HEALTH_CODE:-200}" \
    LITELLM_BOOT_MODE="${T_BOOT_MODE:-auto}" \
    LITELLM_PULL_RETRIES="${T_PULL_RETRIES:-3}" \
    LITELLM_UI_DB="${T_UI_DB:-1}" \
    LITELLM_HEALTH_WAIT_SEC="${T_HEALTH_WAIT_SEC:-}" \
    bash "$script_file" >> "$CURRENT_LOG" 2>&1
}

#-------------------------------------------------------------------------------
# Assertion helpers (each failure is logged and counted)
#-------------------------------------------------------------------------------
A_FAILURES=0
a_ok()   { echo "    ok: $*" >> "$CURRENT_LOG"; }
a_bad()  { echo "    ASSERTION FAILED: $*" >> "$CURRENT_LOG"; A_FAILURES=$((A_FAILURES+1)); }

assert_rc() { # $1 expected rc
  if [ "${T_RC:-999}" = "$1" ]; then a_ok "exit code = $1"; else a_bad "exit code expected $1, got ${T_RC:-unset}"; fi
}
assert_contains() { # $1 file, $2 needle (fixed string)
  if grep -qF -- "$2" "$1" 2>/dev/null; then a_ok "contains: $2"; else a_bad "expected to contain: $2"; fi
}
assert_not_contains() { # $1 file, $2 needle
  if grep -qF -- "$2" "$1" 2>/dev/null; then a_bad "expected NOT to contain: $2"; else a_ok "not contains: $2"; fi
}
assert_file_exists() {
  if [ -e "$1" ]; then a_ok "file exists: $1"; else a_bad "file missing: $1"; fi
}
assert_file_missing() {
  if [ ! -e "$1" ]; then a_ok "file missing: $1"; else a_bad "file should not exist: $1"; fi
}
assert_models() { # $1 config.yaml path, $2 expected (newline separated)
  local got expected="$2"
  got="$(model_names "$1")"
  if [ -z "$got" ]; then a_bad "could not extract models from: $1"; return; fi
  if [ "$got" = "$expected" ]; then
    a_ok "models match (${expected//$'\n'/, })"
  else
    a_bad "models mismatch: got [${got//$'\n'/, }] expected [${expected//$'\n'/, }]"
  fi
}

# Extract model_name list from generated config.yaml
# Uses PyYAML when available; falls back to a structural sed extraction.
model_names() {
  local out rc
  out="$(python3 - "$1" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except Exception:
    sys.exit(3)
try:
    cfg = yaml.safe_load(open(sys.argv[1]))
except Exception:
    sys.exit(4)
for m in (cfg.get("model_list") or []):
    print(m.get("model_name", ""))
PY
)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s' "$out"
    return 0
  fi
  # structural fallback (no PyYAML installed)
  sed -n 's/^  - model_name: //p' "$1" 2>/dev/null
}

# Full validation of a generated opencode.json
# $1 = file, $2 = master key, $3 = expected default model, $4 = expected models (newline list)
assert_opencode_json() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, json
path, mkey, default, models = sys.argv[1], sys.argv[2], sys.argv[3], [m for m in sys.argv[4].split("\n") if m]
fails = 0
def bad(msg):
    global fails
    fails += 1
    print(f"    ASSERTION FAILED (opencode.json): {msg}")
try:
    cfg = json.load(open(path))
except Exception as e:
    bad(f"invalid JSON: {e}")
    sys.exit(1)
prov = (cfg.get("provider") or {}).get("litellm") or {}
opts = prov.get("options") or {}
if cfg.get("$schema") != "https://opencode.ai/config.json": bad("$schema mismatch")
if cfg.get("model") != f"litellm/{default}": bad(f"default model mismatch: {cfg.get('model')}")
if opts.get("baseURL") != "http://127.0.0.1:4000/v1": bad(f"baseURL mismatch: {opts.get('baseURL')}")
if opts.get("apiKey") != mkey: bad("apiKey does not match master key")
if prov.get("name") != "LiteLLM Proxy (Local)": bad("provider name mismatch")
if prov.get("npm") != "@ai-sdk/openai-compatible": bad("npm package mismatch")
got = list((prov.get("models") or {}).keys())
if got != models: bad(f"models mismatch: {got}")
if fails == 0:
    print("    ok: opencode.json fully valid")
sys.exit(1 if fails else 0)
PY
  local rc=$?
  if [ $rc -ne 0 ]; then A_FAILURES=$((A_FAILURES+1)); else a_ok "opencode.json valid ($1)"; fi
  return $rc
}

assert_daemon_json_mirrors() { # $1 = daemon.json path
  python3 - "$1" <<'PY'
import sys, json
expected = ["https://docker.arvancloud.ir",
            "https://docker.hub.iran.liara.run",
            "https://docker.iranserver.com"]
try:
    mirrors = json.load(open(sys.argv[1])).get("registry-mirrors")
except Exception as e:
    print(f"    ASSERTION FAILED: daemon.json invalid: {e}"); sys.exit(1)
if mirrors != expected:
    print(f"    ASSERTION FAILED: mirrors mismatch: {mirrors}"); sys.exit(1)
print("    ok: daemon.json mirrors exact")
PY
  if [ $? -ne 0 ]; then A_FAILURES=$((A_FAILURES+1)); else a_ok "daemon.json mirrors exact ($1)"; fi
}

finish_test() {
  if [ "$A_FAILURES" -eq 0 ]; then pass_test; else fail_test "${A_FAILURES} assertion(s) failed - see ${CURRENT_LOG}"; fi
  A_FAILURES=0
  [ -n "$T_WORK" ] && [ -d "$T_WORK" ] && rm -rf "$T_WORK"
}

# dump auxiliary state into the test log (for committed evidence)
dump_state() {
  {
    echo; echo "--- docker-calls.log ---";     cat "${T_WORKSTATE}/docker-calls.log" 2>/dev/null
    echo; echo "--- apt-calls.log ---";        cat "${T_WORKSTATE}/apt-calls.log" 2>/dev/null
    echo; echo "--- containers.txt ---";       cat "${T_WORKSTATE}/containers.txt" 2>/dev/null
    echo; echo "--- generated config.yaml ---";  cat "${HOME_DIR}/.litellm/config.yaml" 2>/dev/null
    echo; echo "--- generated daemon.json (virtual) ---"; cat "${FAKE_ROOT}/etc/docker/daemon.json" 2>/dev/null
    echo; echo "--- generated opencode.json ---"; cat "/mnt/c/Users/Test User/.config/opencode/opencode.json" 2>/dev/null
  } >> "$CURRENT_LOG"
}

master_key_from() { cat "${HOME_DIR}/.litellm/master_key.txt" 2>/dev/null | tr -d '\n'; }
master_key_in_docker_run() {
  grep -o 'LITELLM_MASTER_KEY=[^ ]*' "${T_WORKSTATE}/docker-calls.log" 2>/dev/null | head -1 | cut -d= -f2
}

#-------------------------------------------------------------------------------
# Preflight
#-------------------------------------------------------------------------------
msg "LiteLLM <-> OpenCode offline test-suite"
msg "script under test: ${SCRIPT_FILE}"

echo "SUITE RUN - $(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$SUMMARY_FILE"
echo "host: $(uname -sr) | user: $(id -un) | bash: ${BASH_VERSION}" >> "$SUMMARY_FILE"

start_test "T00_static_checks"
A_FAILURES=0
if [ -f "$SCRIPT_FILE" ]; then a_ok "script file exists"; else a_bad "script file missing"; fi
if bash -n "$SCRIPT_FILE" 2>>"$CURRENT_LOG"; then a_ok "bash -n (syntax) OK"; else a_bad "bash -n failed"; fi
if head -1 "$SCRIPT_FILE" | grep -q '^#!/usr/bin/env bash'; then a_ok "shebang OK"; else a_bad "shebang missing"; fi
if [ -x "$SCRIPT_FILE" ]; then a_ok "executable bit set"; else a_bad "not executable"; fi
# CRITICAL RULE: script source + terminal output must be 100% ASCII (RTL-safe)
if LC_ALL=C grep -qP '[^\x09\x0A\x0D\x20-\x7E]' "$SCRIPT_FILE"; then
  a_bad "non-ASCII characters found in script (breaks RTL terminals)"
  LC_ALL=C grep -nP '[^\x09\x0A\x0D\x20-\x7E]' "$SCRIPT_FILE" | head -5 >> "$CURRENT_LOG"
else
  a_ok "script is 100% printable ASCII (RTL-safe)"
fi
finish_test

# prepare the fake Windows profiles under /mnt/c (targeted names only)
MNT_OK=1
for u in "Test User" "Ali Rezaei"; do
  d="/mnt/c/Users/${u}"
  if [ ! -d "$d" ]; then
    if as_root mkdir -p "$d" 2>/dev/null && as_root chown "$(id -u):$(id -g)" "$d" 2>/dev/null; then
      CREATED_PROFILE_DIRS+=("$d")
    else
      MNT_OK=0
    fi
  else
    # directory already exists (e.g. re-run); make sure we can write into it
    [ -w "$d" ] || MNT_OK=0
  fi
done
if [ "$MNT_OK" -eq 1 ]; then
  msg "fake Windows profiles ready under /mnt/c/Users (isolated names, removed on exit)"
else
  msg "WARNING: cannot create /mnt/c fake profiles - profile-dependent tests will SKIP"
fi

# permissions to manage /etc/docker/daemon.json (needed only by T12/T13)
CAN_MANAGE_DAEMON=1
if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  CAN_MANAGE_DAEMON=0
fi

#===============================================================================
# T01 - full install with all 5 API keys (apt install path)
#===============================================================================
start_test "T01_full_install_all_keys"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\n\n\n\n\n\ngsk_test_groq_0123456789abcd\nsk-or-test_0123456789abcd\nAIzaTest0123456789abcd\ncsk-test_0123456789abcd\nsk_mistral_test012345678\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "INSTALLATION COMPLETED SUCCESSFULLY"
  assert_contains "${T_WORKSTATE}/apt-calls.log" "install -y docker.io"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "pull ghcr.io/berriai/litellm:main-latest"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "run -d --name litellm --restart unless-stopped -p 4000:4000"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-v ${HOME_DIR}/.litellm/config.yaml:/app/config.yaml:ro"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "--config /app/config.yaml --port 4000"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e GROQ_API_KEY=gsk_test_groq_0123456789abcd"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e OPENROUTER_API_KEY=sk-or-test_0123456789abcd"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e GEMINI_API_KEY=AIzaTest0123456789abcd"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e CEREBRAS_API_KEY=csk-test_0123456789abcd"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e MISTRAL_API_KEY=sk_mistral_test012345678"
  if grep -qxF "litellm" "${T_WORKSTATE}/containers.txt"; then a_ok "container registered"; else a_bad "container not registered"; fi
  assert_file_exists "${HOME_DIR}/.litellm/config.yaml"
  assert_file_exists "${HOME_DIR}/.litellm/master_key.txt"
  assert_models "${HOME_DIR}/.litellm/config.yaml" "$ALL7_MODELS"
  MK="$(master_key_from)"
  if [ -n "$MK" ] && [ "$MK" = "$(master_key_in_docker_run)" ]; then a_ok "master key consistent (file == docker env)"; else a_bad "master key mismatch"; fi
  assert_file_exists "${HOME_DIR}/.litellm/dashboard_credentials.txt"
  assert_contains "${HOME_DIR}/.litellm/dashboard_credentials.txt" "Username : admin"
  assert_contains "${HOME_DIR}/.litellm/dashboard_credentials.txt" "Password : ${MK}"
  assert_contains "$CURRENT_LOG" "Password  : ${MK}"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e UI_PASSWORD=${MK}"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e UI_USERNAME=admin"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e UI_PASSWORD=${MK}"
  assert_file_exists "${HOME_DIR}/.litellm/db_password.txt"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "run -d --name litellm-db --restart unless-stopped --network litellm-net"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e POSTGRES_USER=litellm"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-v ${HOME_DIR}/.litellm/pgdata:/var/lib/postgresql/data"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "exec litellm-db pg_isready"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e DATABASE_URL=postgresql://litellm:"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "@litellm-db:5432/litellm"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "--network litellm-net"
  assert_contains "${HOME_DIR}/.litellm/config.yaml" "database_url: os.environ/DATABASE_URL"
  assert_file_exists "${FAKE_ROOT}/usr/local/bin/litellm"
  assert_file_exists "${FAKE_ROOT}/usr/local/bin/litellm-boot.sh"
  if grep -qF "command = /usr/local/bin/litellm-boot.sh" "${FAKE_ROOT}/etc/wsl.conf" 2>/dev/null \
     || [ -f "${FAKE_ROOT}/etc/systemd/system/litellm.service" ]; then
    a_ok "boot persistence configured (wsl.conf entry or systemd unit)"
  else
    a_bad "no boot persistence found (neither wsl.conf entry nor systemd unit)"
  fi
  assert_daemon_json_mirrors "${FAKE_ROOT}/etc/docker/daemon.json"
  if [ -f /etc/docker/daemon.json ]; then
    assert_contains "$CURRENT_LOG" "Existing daemon.json backed up"
  else
    assert_not_contains "$CURRENT_LOG" "backed up"
  fi
  assert_file_exists "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$ALL7_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T02 - install with ONLY the Groq key
#===============================================================================
start_test "T02_install_groq_only"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_only_groq_0123456789ab\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Collected 1 API key(s)"
  assert_models "${HOME_DIR}/.litellm/config.yaml" "$GROQ2_MODELS"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e GROQ_API_KEY=gsk_only_groq_0123456789ab"
  assert_not_contains "${T_WORKSTATE}/docker-calls.log" "OPENROUTER_API_KEY"
  assert_not_contains "${T_WORKSTATE}/docker-calls.log" "GEMINI_API_KEY"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T03 - install with ONLY the Google AI key (default model selection)
#===============================================================================
start_test "T03_install_gemini_only"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\n\n\nAIzaOnlyTest0123456789ab\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_models "${HOME_DIR}/.litellm/config.yaml" "$GEMINI1_MODELS"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "gemini-2.0-flash" "$GEMINI1_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T04 - zero keys on first round -> forced retry -> success on second round
#===============================================================================
start_test "T04_no_keys_retry_then_success"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\n\n\n\n\n\n\nsk_or_second_0123456789ab\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "At least ONE API key is required. Let's try again."
  assert_contains "$CURRENT_LOG" "Collected 1 API key(s)"
  assert_models "${HOME_DIR}/.litellm/config.yaml" "$OR2_MODELS"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "deepseek/deepseek-chat-v3:free" "$OR2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T05 - zero keys on all 3 attempts -> script must exit non-zero
#===============================================================================
start_test "T05_no_keys_three_attempts_fails"
fresh_env
printf '1\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n' | run_script
T_RC=$?
assert_rc 1
assert_contains "$CURRENT_LOG" "Exiting after 3 attempts"
dump_state
finish_test

#===============================================================================
# T06 - reinstall over an existing container replaces it
#===============================================================================
start_test "T06_reinstall_replaces_container"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_first_0123456789abcdef\n\n\n\n\n' | run_script
  # second run: answer 'n' -> replace all keys
  printf '1\nn\ngsk_second_0123456789abcdef\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Existing API keys found (from the previous install)"
  assert_contains "$CURRENT_LOG" "OK - enter the replacement keys below."
  assert_contains "$CURRENT_LOG" "Found existing container 'litellm'. Removing it..."
  assert_contains "${T_WORKSTATE}/docker-calls.log" "rm -f litellm"
  if [ "$(grep -cx 'litellm' "${T_WORKSTATE}/containers.txt")" = "1" ]; then a_ok "exactly one container registered"; else a_bad "container registry not deduplicated"; fi
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e GROQ_API_KEY=gsk_second_0123456789abcdef"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T07 - full uninstall removes container + linux folder + windows config
#===============================================================================
start_test "T07_full_uninstall"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_uninstall_0123456789ab\n\n\n\n\n' | run_script
  printf '2\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "UNINSTALL COMPLETED SUCCESSFULLY"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "stop litellm"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "rm litellm"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "rm litellm-db"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "network rm litellm-net"
  if [ ! -s "${T_WORKSTATE}/containers.txt" ]; then a_ok "container registry empty"; else a_bad "container still registered"; fi
  assert_file_missing "${HOME_DIR}/.litellm/config.yaml"
  assert_file_missing "${HOME_DIR}/.litellm/master_key.txt"
  assert_file_missing "${HOME_DIR}/.litellm/dashboard_credentials.txt"
  assert_file_missing "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  assert_file_missing "${FAKE_ROOT}/usr/local/bin/litellm"
  assert_file_missing "${FAKE_ROOT}/usr/local/bin/litellm-boot.sh"
  assert_not_contains "${FAKE_ROOT}/etc/wsl.conf" "litellm-boot.sh"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T08 - uninstall when nothing is installed (idempotent, must not fail)
#===============================================================================
start_test "T08_uninstall_idempotent"
fresh_env
printf '2\n' | run_script
T_RC=$?
assert_rc 0
assert_contains "$CURRENT_LOG" "No container named 'litellm' found"
assert_contains "$CURRENT_LOG" "UNINSTALL COMPLETED SUCCESSFULLY"
dump_state
finish_test

#===============================================================================
# T09 - invalid menu choice exits with code 1
#===============================================================================
start_test "T09_invalid_menu_choice"
fresh_env
printf '9\n' | run_script
T_RC=$?
assert_rc 1
assert_contains "$CURRENT_LOG" "Invalid choice"
dump_state
finish_test

#===============================================================================
# T10 - quit option exits cleanly
#===============================================================================
start_test "T10_menu_quit"
fresh_env
printf 'q\n' | run_script
T_RC=$?
assert_rc 0
assert_contains "$CURRENT_LOG" "Bye!"
dump_state
finish_test

#===============================================================================
# T11 - Windows username containing a space
#===============================================================================
start_test "T11_username_with_space"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_spaceuser_0123456789ab\n\n\n\n\n' | \
    env -u DOCKER_PULL_FAIL -u DOCKER_APT_FAIL -u HEALTH_CODE \
      HOME="$HOME_DIR" PATH="${STUBBIN}:${PATH}" \
      STUBBIN="$STUBBIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
      HEALTH_CODE="200" PS_USERNAME="Ali Rezaei" \
      bash "$SCRIPT_FILE" >> "$CURRENT_LOG" 2>&1
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "/mnt/c/Users/Ali Rezaei"
  assert_file_exists "/mnt/c/Users/Ali Rezaei/.config/opencode/opencode.json"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Ali Rezaei/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T12 - existing daemon.json is backed up before being replaced
#===============================================================================
start_test "T12_daemon_json_backup"
if [ "$CAN_MANAGE_DAEMON" -eq 1 ]; then
  fresh_env
  REAL_DAEMON_BACKUP="${T_WORK}/host-daemon.json.orig"
  if [ -f /etc/docker/daemon.json ]; then
    REAL_DAEMON_STATE="was-present"
    cp /etc/docker/daemon.json "$REAL_DAEMON_BACKUP"
  else
    REAL_DAEMON_STATE="seeded-absent"
  fi
  as_root mkdir -p /etc/docker 2>/dev/null || true
  printf '{\n  "user-custom-key": "keep-me"\n}\n' | as_root tee /etc/docker/daemon.json >/dev/null
  # re-mirror the seeded host file into the virtual root (fresh_env ran before seeding)
  mkdir -p "${FAKE_ROOT}/etc/docker"
  cp /etc/docker/daemon.json "${FAKE_ROOT}/etc/docker/daemon.json"
  printf '1\ngsk_backup_0123456789abcdef\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Existing daemon.json backed up"
  bak_count="$(find "${FAKE_ROOT}/etc/docker" -name 'daemon.json.bak.*' 2>/dev/null | wc -l)"
  if [ "${bak_count:-0}" -ge 1 ]; then a_ok "backup file created in virtual /etc/docker"; else a_bad "no daemon.json.bak.* created"; fi
  assert_daemon_json_mirrors "${FAKE_ROOT}/etc/docker/daemon.json"
  dump_state
  # restore host state BEFORE finish_test (which deletes $T_WORK)
  if [ "$REAL_DAEMON_STATE" = "was-present" ]; then
    cp_sudo "$REAL_DAEMON_BACKUP" /etc/docker/daemon.json
  else
    rm_f_sudo /etc/docker/daemon.json
  fi
  REAL_DAEMON_STATE=""
  finish_test
else
  skip_test "requires root/sudo to manage /etc/docker/daemon.json"
fi

#===============================================================================
# T13 - powershell.exe found via /mnt/c fallback (no PATH interop)
#===============================================================================
start_test "T13_powershell_fallback_path"
if [ "$MNT_OK" -eq 1 ] && [ "$CAN_MANAGE_DAEMON" -eq 1 ]; then
  fresh_env
  FALLBACK_BIN="${T_WORK}/bin-without-ps"
  mkdir -p "$FALLBACK_BIN"
  for f in sudo apt-get service systemctl curl docker.installer; do
    cp "$STUBBIN/$f" "$FALLBACK_BIN/${f%.installer}"
  done
  chmod +x "$FALLBACK_BIN"/*
  PS_MNT="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  as_root mkdir -p "/mnt/c/Windows/System32/WindowsPowerShell/v1.0" 2>/dev/null || true
  CREATED_PS=0
  if [ ! -f "$PS_MNT" ]; then
    as_root cp "$STUBBIN/powershell.exe" "$PS_MNT" && as_root chmod 755 "$PS_MNT" && CREATED_PS=1
  fi
  if [ -x "$PS_MNT" ]; then
    printf '1\ngsk_fallback_0123456789abc\n\n\n\n\n' | \
      env -u DOCKER_PULL_FAIL -u DOCKER_APT_FAIL -u HEALTH_CODE -u PS_USERNAME \
        HOME="$HOME_DIR" PATH="${FALLBACK_BIN}:${PATH}" \
        STUBBIN="$FALLBACK_BIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
        HEALTH_CODE="200" \
        bash "$SCRIPT_FILE" >> "$CURRENT_LOG" 2>&1
    T_RC=$?
    assert_rc 0
    assert_contains "$CURRENT_LOG" "/mnt/c/Users/Test User"
    assert_file_exists "/mnt/c/Users/Test User/.config/opencode/opencode.json"
    if [ "$CREATED_PS" -eq 1 ]; then rm_f_sudo "$PS_MNT"; fi
  else
    a_bad "could not stage powershell.exe under /mnt/c"
  fi
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c + sudo"
fi

#===============================================================================
# T14 - health check timeout path (server never becomes healthy)
#===============================================================================
start_test "T14_health_check_timeout"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  T_HEALTH_CODE="000"
  T_HEALTH_WAIT_SEC="4"
  printf '1\ngsk_timeout_0123456789abcd\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Health check timed out"
  assert_contains "$CURRENT_LOG" "INSTALLATION COMPLETED SUCCESSFULLY"
  T_HEALTH_CODE=""
  T_HEALTH_WAIT_SEC=""
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T15 - docker pull failure -> script must die with a clear error
#===============================================================================
start_test "T15_pull_failure"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_pullfail_0123456789abc\n\n\n\n\n' | \
    env -u DOCKER_APT_FAIL -u HEALTH_CODE -u PS_USERNAME \
      DOCKER_PULL_FAIL="1" LITELLM_PULL_RETRIES="1" \
      HOME="$HOME_DIR" PATH="${STUBBIN}:${PATH}" \
      STUBBIN="$STUBBIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
      HEALTH_CODE="200" \
      bash "$SCRIPT_FILE" >> "$CURRENT_LOG" 2>&1
  T_RC=$?
  assert_rc 1
  assert_contains "$CURRENT_LOG" "Image pull failed"
  assert_file_missing "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T16 - docker already installed -> apt-get must be skipped
#===============================================================================
start_test "T16_docker_already_installed"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  cp "$STUBBIN/docker.installer" "${STUBBIN}/docker"
  chmod +x "${STUBBIN}/docker"
  printf '1\ngsk_predocker_0123456789ab\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Docker binary already present, skipping apt installation"
  if [ ! -s "${T_WORKSTATE}/apt-calls.log" ]; then a_ok "apt-get never called"; else a_bad "apt-get was called unexpectedly"; fi
  rm -f "${STUBBIN}/docker"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T17 - CRLF self-heal: a Windows-line-endings copy must still work end-to-end
#===============================================================================
start_test "T17_crlf_self_heal"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  CRLF_COPY="${T_WORK}/LiteLLM.crlf.sh"
  sed 's/$/\r/' "$SCRIPT_FILE" > "$CRLF_COPY"
  printf '1\ngsk_crlf_0123456789abcdef\n\n\n\n\n' | run_script "$CRLF_COPY"
  T_RC=$?
  assert_rc 0
  assert_not_contains "$CURRENT_LOG" "invalid option name"
  assert_contains "$CURRENT_LOG" "INSTALLATION COMPLETED SUCCESSFULLY"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T18 - systemd branch: litellm.service unit created and enabled
#===============================================================================
start_test "T18_autostart_systemd_unit"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  T_BOOT_MODE="systemd"
  printf '1\ngsk_systemd_0123456789abc\n\n\n\n\n' | run_script
  T_RC=$?
  T_BOOT_MODE=""
  assert_rc 0
  UNIT="${FAKE_ROOT}/etc/systemd/system/litellm.service"
  assert_file_exists "$UNIT"
  assert_contains "$UNIT" "ExecStart=/usr/local/bin/litellm-boot.sh"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "systemctl enable litellm.service"
  assert_contains "$CURRENT_LOG" "systemd service: litellm.service (enabled)"
  if [ -f "${FAKE_ROOT}/etc/wsl.conf" ]; then
    assert_not_contains "${FAKE_ROOT}/etc/wsl.conf" "litellm-boot.sh"
  fi
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T19 - management CLI: up / down / restart / status / uninstall
#===============================================================================
start_test "T19_management_cli"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_cli_0123456789abcdef\n\n\n\n\n' | run_script
  T_RC=$?
  assert_rc 0
  CLI="${FAKE_ROOT}/usr/local/bin/litellm"
  if [ -x "$CLI" ]; then a_ok "CLI installed and executable"; else a_bad "CLI missing or not executable"; fi
  run_cli() {
    env -u DOCKER_PULL_FAIL -u DOCKER_APT_FAIL -u HEALTH_CODE -u PS_USERNAME \
      HOME="$HOME_DIR" PATH="${STUBBIN}:${PATH}" \
      STUBBIN="$STUBBIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
      HEALTH_CODE="200" PS_USERNAME="Test User" \
      bash "$CLI" "$@" >> "$CURRENT_LOG" 2>&1
  }
  run_cli status
  assert_contains "$CURRENT_LOG" "Container state : running"
  assert_contains "$CURRENT_LOG" "Restart policy  : unless-stopped"
  assert_contains "$CURRENT_LOG" "Admin panel     : http://127.0.0.1:4000/ui"
  run_cli down
  assert_contains "${T_WORKSTATE}/docker-calls.log" "stop litellm"
  if grep -qxF "litellm" "${T_WORKSTATE}/container-running.txt"; then a_bad "container still marked running after down"; else a_ok "running state cleared after down"; fi
  run_cli up
  assert_contains "${T_WORKSTATE}/docker-calls.log" "start litellm"
  run_cli restart
  assert_contains "${T_WORKSTATE}/docker-calls.log" "restart litellm"
  MK="$(master_key_from)"
  run_cli credentials
  assert_contains "$CURRENT_LOG" "Username : admin"
  assert_contains "$CURRENT_LOG" "Password : ${MK}"
  run_cli uninstall --yes
  assert_contains "$CURRENT_LOG" "UNINSTALL COMPLETED."
  if [ ! -s "${T_WORKSTATE}/containers.txt" ]; then a_ok "container registry empty after CLI uninstall"; else a_bad "container still registered after CLI uninstall"; fi
  assert_file_missing "${HOME_DIR}/.litellm/config.yaml"
  assert_file_missing "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  assert_file_missing "$CLI"
  assert_file_missing "${FAKE_ROOT}/usr/local/bin/litellm-boot.sh"
  assert_not_contains "${FAKE_ROOT}/etc/wsl.conf" "litellm-boot.sh"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T20 - wsl.conf boot-command branch (forced via LITELLM_BOOT_MODE=wslconf)
#===============================================================================
start_test "T20_autostart_wslconf_boot"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  T_BOOT_MODE="wslconf"
  printf '1\ngsk_wslconf_0123456789abc\n\n\n\n\n' | run_script
  T_RC=$?
  T_BOOT_MODE=""
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Boot command added to /etc/wsl.conf"
  assert_contains "${FAKE_ROOT}/etc/wsl.conf" "command = /usr/local/bin/litellm-boot.sh"
  assert_file_missing "${FAKE_ROOT}/etc/systemd/system/litellm.service"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T21 - pull fails but a local image exists -> continue with the local copy
#===============================================================================
start_test "T21_pull_failure_with_local_image"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  echo "ghcr.io/berriai/litellm:main-latest" > "${T_WORKSTATE}/images.txt"
  printf '1\ngsk_localimg_0123456789abc\n\n\n\n\n' | \
    env -u DOCKER_APT_FAIL -u HEALTH_CODE -u PS_USERNAME \
      DOCKER_PULL_FAIL="1" LITELLM_PULL_RETRIES="1" \
      HOME="$HOME_DIR" PATH="${STUBBIN}:${PATH}" \
      STUBBIN="$STUBBIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
      HEALTH_CODE="200" \
      bash "$SCRIPT_FILE" >> "$CURRENT_LOG" 2>&1
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Image already exists locally"
  assert_contains "$CURRENT_LOG" "continuing with the local copy"
  assert_contains "$CURRENT_LOG" "INSTALLATION COMPLETED SUCCESSFULLY"
  assert_file_exists "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T22 - ghcr fallback mirror is used when the direct pull fails
#===============================================================================
start_test "T22_ghcr_mirror_fallback"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_mirror_0123456789abcd\n\n\n\n\n' | \
    env -u DOCKER_APT_FAIL -u HEALTH_CODE -u PS_USERNAME \
      DOCKER_PULL_FAIL_MATCH="ghcr.io" LITELLM_PULL_RETRIES="1" \
      LITELLM_GHCR_MIRROR="ghcr.nju.edu.cn/" \
      HOME="$HOME_DIR" PATH="${STUBBIN}:${PATH}" \
      STUBBIN="$STUBBIN" T_WORKSTATE="$T_WORKSTATE" FAKE_ROOT="$FAKE_ROOT" \
      HEALTH_CODE="200" \
      bash "$SCRIPT_FILE" >> "$CURRENT_LOG" 2>&1
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Trying the ghcr fallback mirror"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "pull ghcr.nju.edu.cn/berriai/litellm:main-latest"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "tag ghcr.nju.edu.cn/berriai/litellm:main-latest ghcr.io/berriai/litellm:main-latest"
  assert_contains "$CURRENT_LOG" "INSTALLATION COMPLETED SUCCESSFULLY"
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T23 - reinstall keeps existing keys by default (Enter = keep)
#===============================================================================
start_test "T23_reinstall_keeps_existing_keys"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  printf '1\ngsk_keepme_0123456789abc\n\n\n\n\n' | run_script
  # second run: only the menu answer -> default keeps existing keys
  printf '1\n\n' | run_script
  T_RC=$?
  assert_rc 0
  assert_contains "$CURRENT_LOG" "Database container 'litellm-db' already present."
  assert_contains "$CURRENT_LOG" "Existing API keys found (from the previous install)"
  assert_contains "$CURRENT_LOG" "Groq       : gsk_****9abc"
  assert_contains "$CURRENT_LOG" "Keeping the existing 1 API key(s)."
  assert_not_contains "$CURRENT_LOG" "Groq API key"
  assert_contains "${T_WORKSTATE}/docker-calls.log" "-e GROQ_API_KEY=gsk_keepme_0123456789abc"
  MK1="$(grep -o 'LITELLM_MASTER_KEY=[^ ]*' "${T_WORKSTATE}/docker-calls.log" | head -1 | cut -d= -f2)"
  MK2="$(grep -o 'LITELLM_MASTER_KEY=[^ ]*' "${T_WORKSTATE}/docker-calls.log" | tail -1 | cut -d= -f2)"
  if [ -n "$MK1" ] && [ "$MK1" = "$MK2" ]; then a_ok "master key stable across reinstall"; else a_bad "master key changed on reinstall"; fi
  MK="$(master_key_from)"
  assert_opencode_json "/mnt/c/Users/Test User/.config/opencode/opencode.json" "$MK" "qwen-2.5-coder-32b" "$GROQ2_MODELS"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# T24 - LITELLM_UI_DB=0: no database stack, config without database_url
#===============================================================================
start_test "T24_ui_db_disabled"
if [ "$MNT_OK" -eq 1 ]; then
  fresh_env
  T_UI_DB="0"
  printf '1\ngsk_nodb_0123456789abcd\n\n\n\n\n' | run_script
  T_RC=$?
  T_UI_DB=""
  assert_rc 0
  assert_not_contains "${T_WORKSTATE}/docker-calls.log" "litellm-db"
  assert_not_contains "${T_WORKSTATE}/docker-calls.log" "DATABASE_URL"
  assert_not_contains "${HOME_DIR}/.litellm/config.yaml" "database_url"
  assert_not_contains "${T_WORKSTATE}/docker-calls.log" "--network litellm-net"
  assert_contains "$CURRENT_LOG" "Admin UI database               : disabled"
  assert_file_exists "/mnt/c/Users/Test User/.config/opencode/opencode.json"
  dump_state
  finish_test
else
  skip_test "requires writable /mnt/c"
fi

#===============================================================================
# Summary
#===============================================================================
echo >> "$SUMMARY_FILE"
echo "TOTAL: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped" >> "$SUMMARY_FILE"

echo
msg "==============================================================="
msg "RESULTS: ${PASS} passed / ${FAIL} failed / ${SKIP} skipped"
msg "logs:    ${RESULTS_DIR}/"
msg "summary: ${SUMMARY_FILE}"
msg "==============================================================="

[ "$FAIL" -eq 0 ]
