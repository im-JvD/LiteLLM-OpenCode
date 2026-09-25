#!/usr/bin/env bash
#===============================================================================
#
#   LiteLLM <-> OpenCode Bridge  |  WSL2 Ubuntu Setup Script
#
#   Installs and configures a local LiteLLM proxy inside WSL2 Ubuntu
#   and wires OpenCode (on the Windows side) to it through
#   http://127.0.0.1:4000/v1
#
#   Features:
#     - Interactive menu: Full Install / Full Uninstall
#     - Docker installed from Ubuntu apt repo (docker.io), Iran-friendly
#     - Iranian Docker Hub mirrors for sanctioned networks (403 fix)
#     - Prebuilt image only: ghcr.io/berriai/litellm:main-latest (NO docker build)
#     - Auto-generated config.yaml from the API keys you provide
#     - Auto-generated opencode.json on the Windows user profile
#
#   Usage (run WITHOUT sudo - the script escalates where needed):
#     bash LiteLLM.sh
#
#===============================================================================
#-----------------------------------------------------------------------------
# CRLF self-heal: if this file was saved with Windows line endings (CRLF),
# bash fails with "set: pipefail: invalid option name".
# The guard below is a deliberate SINGLE-line simple command (CRLF-safe):
# it detects CR bytes in this file and re-executes a stripped copy through
# process substitution. See docs/troubleshooting.md for the manual fix.
#-----------------------------------------------------------------------------
[ -f "$0" ] && grep -q $'\r' "$0" && exec bash <(tr -d '\r' < "$0") "$@"

set -euo pipefail

#-------------------------------------------------------------------------------
# Constants
#-------------------------------------------------------------------------------
CONTAINER_NAME="litellm"
LITELLM_IMAGE="ghcr.io/berriai/litellm:main-latest"
LITELLM_PORT="4000"
LITELLM_DIR="${HOME}/.litellm"
LITELLM_CONFIG="${LITELLM_DIR}/config.yaml"
LITELLM_KEYFILE="${LITELLM_DIR}/master_key.txt"
DAEMON_JSON="/etc/docker/daemon.json"
CLI_BIN="/usr/local/bin/litellm"
BOOT_HELPER="/usr/local/bin/litellm-boot.sh"
SYSTEMD_UNIT="/etc/systemd/system/litellm.service"
WSL_CONF="/etc/wsl.conf"
BOOT_LINE="command = /usr/local/bin/litellm-boot.sh"
AUTOSTART_MODE=""
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Iranian Docker Hub mirrors (403 / rate-limit workaround)
REGISTRY_MIRRORS=(
  "https://docker.arvancloud.ir"
  "https://docker.hub.iran.liara.run"
  "https://docker.iranserver.com"
)

#-------------------------------------------------------------------------------
# UI helpers (plain ASCII so Windows terminals render them correctly)
#-------------------------------------------------------------------------------
if [ -t 1 ]; then
  C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'
  C_CYAN='\033[0;36m'; C_BOLD='\033[1m'; C_NC='\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_NC=''
fi

log_info()  { echo -e "${C_CYAN}[INFO]${C_NC} $*"; }
log_ok()    { echo -e "${C_GREEN}[ OK ]${C_NC} $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_NC} $*"; }
log_error() { echo -e "${C_RED}[FAIL]${C_NC} $*" >&2; }
die()       { log_error "$*"; exit 1; }

trap 'echo; log_warn "Interrupted by user. Exiting."; exit 130' INT TERM

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
SUDO=""
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
  log_warn "Running as root. Config will be created under /root/.litellm"
else
  if ! command -v sudo >/dev/null 2>&1; then
    die "'sudo' is not installed and you are not root. Install sudo first:  apt-get install -y sudo"
  fi
  SUDO="sudo"
  # Silent if passwordless; otherwise prompts once for the password.
  $SUDO -n true 2>/dev/null || $SUDO true 2>/dev/null || \
    die "Sudo authentication failed. Please configure sudo for this user."
fi

check_wsl_environment() {
  log_info "[1/9] Checking WSL2 environment..."
  if ! grep -qi "microsoft" /proc/version 2>/dev/null; then
    log_warn "This does not look like a WSL kernel (/proc/version)."
    log_warn "Continuing anyway - Windows/PowerShell integration may fail."
  fi
  find_powershell >/dev/null || \
    die "powershell.exe was not found. Enable WSL interop (append Windows PATH) and try again."
  log_ok "WSL2 environment looks good."
}

# Locate powershell.exe (works even if Windows PATH interop is disabled)
find_powershell() {
  if command -v powershell.exe >/dev/null 2>&1; then
    command -v powershell.exe
    return 0
  fi
  for p in /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
           /mnt/*/Windows/System32/WindowsPowerShell/v1.0/powershell.exe; do
    if [ -x "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# Get the real Windows user profile path (safe with spaces in the username)
# and convert it to its WSL mount point, e.g.:
#   C:\Users\John Doe  ->  /mnt/c/Users/John Doe
get_windows_home() {
  local ps raw drive letter rest
  ps="$(find_powershell)" || return 1
  raw="$($ps -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')" 2>/dev/null | tr -d '\r')"
  [ -n "$raw" ] || return 1

  drive="${raw%%:*}"
  letter="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
  rest="${raw#*:}"
  rest="${rest//\\//}"          # backslashes -> forward slashes

  printf '/mnt/%s%s' "$letter" "$rest"
}

#-------------------------------------------------------------------------------
# Docker installation (apt repo, NOT get.docker.com) + Iranian mirrors
#-------------------------------------------------------------------------------
install_docker() {
  log_info "[2/9] Installing Docker Engine (docker.io from Ubuntu apt repository)..."
  if ! command -v docker >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker.io
  else
    log_ok "Docker binary already present, skipping apt installation."
  fi
}

configure_docker_mirrors() {
  log_info "[3/9] Configuring Iranian Docker Hub mirrors (${DAEMON_JSON})..."
  $SUDO mkdir -p /etc/docker

  if [ -f "$DAEMON_JSON" ]; then
    local backup="${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
    $SUDO cp "$DAEMON_JSON" "$backup"
    log_warn "Existing daemon.json backed up to: ${backup}"
  fi

  local mirrors_json=""
  for m in "${REGISTRY_MIRRORS[@]}"; do
    [ -n "$mirrors_json" ] && mirrors_json+=",\n    "
    mirrors_json+="\"${m}\""
  done

  printf '{\n  "registry-mirrors": [\n    %b\n  ]\n}\n' "$mirrors_json" \
    | $SUDO tee "$DAEMON_JSON" >/dev/null

  log_ok "Registry mirrors written:"
  for m in "${REGISTRY_MIRRORS[@]}"; do echo "       - ${m}"; done
}

start_docker_daemon() {
  log_info "       Starting/restarting the Docker daemon..."
  $SUDO service docker restart >/dev/null 2>&1 || $SUDO service docker start >/dev/null 2>&1 || true

  # Enable auto-start on boot when systemd is available (WSL2 with systemd=true)
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl enable docker.service >/dev/null 2>&1 || true
  fi

  local i
  for i in $(seq 1 20); do
    if $SUDO docker info >/dev/null 2>&1; then
      log_ok "Docker daemon is up and running."
      return 0
    fi
    sleep 1
  done
  die "Docker daemon did not start. Try manually:  sudo service docker start"
}

#-------------------------------------------------------------------------------
# API keys
#-------------------------------------------------------------------------------
mask_key() {
  local k="$1"
  if [ -z "$k" ]; then echo "<skipped>"; return; fi
  if [ "${#k}" -ge 12 ]; then
    echo "${k:0:4}****${k: -4}"
  else
    echo "****"
  fi
}

collect_api_keys() {
  echo
  log_info "[4/9] API keys setup (5 providers)"
  echo "       Press ENTER to skip a provider you do not use."
  echo "       At least ONE key is required."
  echo

  local attempts=0
  while true; do
    attempts=$((attempts + 1))
    read -r -p "       [1/5] Groq API key        (gsk_...): " GROQ_KEY || true
    read -r -p "       [2/5] OpenRouter API key (sk-or-...): " OPENROUTER_KEY || true
    read -r -p "       [3/5] Google AI key      (AIza...): " GEMINI_KEY || true
    read -r -p "       [4/5] Cerebras API key   (csk-...): " CEREBRAS_KEY || true
    read -r -p "       [5/5] Mistral API key    (sk-...) : " MISTRAL_KEY || true

    # Strip any accidental whitespace
    GROQ_KEY="${GROQ_KEY//[[:space:]]/}"
    OPENROUTER_KEY="${OPENROUTER_KEY//[[:space:]]/}"
    GEMINI_KEY="${GEMINI_KEY//[[:space:]]/}"
    CEREBRAS_KEY="${CEREBRAS_KEY//[[:space:]]/}"
    MISTRAL_KEY="${MISTRAL_KEY//[[:space:]]/}"

    KEY_COUNT=0
    [ -n "$GROQ_KEY" ]       && KEY_COUNT=$((KEY_COUNT + 1)) || true
    [ -n "$OPENROUTER_KEY" ] && KEY_COUNT=$((KEY_COUNT + 1)) || true
    [ -n "$GEMINI_KEY" ]     && KEY_COUNT=$((KEY_COUNT + 1)) || true
    [ -n "$CEREBRAS_KEY" ]   && KEY_COUNT=$((KEY_COUNT + 1)) || true
    [ -n "$MISTRAL_KEY" ]    && KEY_COUNT=$((KEY_COUNT + 1)) || true

    if [ "$KEY_COUNT" -ge 1 ]; then
      echo
      log_ok "Collected ${KEY_COUNT} API key(s):"
      echo "         Groq       : $(mask_key "$GROQ_KEY")"
      echo "         OpenRouter : $(mask_key "$OPENROUTER_KEY")"
      echo "         Google AI  : $(mask_key "$GEMINI_KEY")"
      echo "         Cerebras   : $(mask_key "$CEREBRAS_KEY")"
      echo "         Mistral    : $(mask_key "$MISTRAL_KEY")"
      break
    fi
    if [ "$attempts" -ge 3 ]; then
      die "At least ONE API key is required. Exiting after ${attempts} attempts."
    fi
    log_error "At least ONE API key is required. Let's try again."
    echo
  done
  return 0
}

generate_master_key() {
  if command -v openssl >/dev/null 2>&1; then
    MASTER_KEY="sk-$(openssl rand -hex 32)"
  else
    MASTER_KEY="sk-$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  fi
  mkdir -p "$LITELLM_DIR"
  printf '%s\n' "$MASTER_KEY" > "$LITELLM_KEYFILE"
  chmod 600 "$LITELLM_KEYFILE"
  log_ok "LiteLLM master key generated and saved to: ${LITELLM_KEYFILE}"
}

#-------------------------------------------------------------------------------
# config.yaml (only providers whose keys were provided)
#-------------------------------------------------------------------------------
generate_litellm_config() {
  log_info "[5/9] Generating LiteLLM configuration: ${LITELLM_CONFIG}"
  mkdir -p "$LITELLM_DIR"

  {
    echo "model_list:"

    if [ -n "$GROQ_KEY" ]; then
      cat <<'EOF'
  # ---------------- Groq (fast inference) ----------------
  - model_name: qwen-2.5-coder-32b
    litellm_params:
      model: groq/qwen-2.5-coder-32b
      api_key: os.environ/GROQ_API_KEY
      api_base: https://api.groq.com/openai/v1
  - model_name: llama-3.3-70b-versatile
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: os.environ/GROQ_API_KEY
      api_base: https://api.groq.com/openai/v1
EOF
    fi

    if [ -n "$OPENROUTER_KEY" ]; then
      cat <<'EOF'
  # ---------------- OpenRouter (free coding models) ----------------
  - model_name: deepseek/deepseek-chat-v3:free
    litellm_params:
      model: openrouter/deepseek/deepseek-chat-v3:free
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
  - model_name: deepseek/deepseek-r1:free
    litellm_params:
      model: openrouter/deepseek/deepseek-r1:free
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
EOF
    fi

    if [ -n "$GEMINI_KEY" ]; then
      cat <<'EOF'
  # ---------------- Google AI Studio (Gemini) ----------------
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: os.environ/GEMINI_API_KEY
EOF
    fi

    if [ -n "$CEREBRAS_KEY" ]; then
      cat <<'EOF'
  # ---------------- Cerebras ----------------
  - model_name: llama3.1-70b
    litellm_params:
      model: cerebras/llama3.1-70b
      api_key: os.environ/CEREBRAS_API_KEY
      api_base: https://api.cerebras.ai/v1
EOF
    fi

    if [ -n "$MISTRAL_KEY" ]; then
      cat <<'EOF'
  # ---------------- Mistral ----------------
  - model_name: codestral-latest
    litellm_params:
      model: mistral/codestral-latest
      api_key: os.environ/MISTRAL_API_KEY
      api_base: https://api.mistral.ai/v1
EOF
    fi

    cat <<'EOF'

litellm_settings:
  drop_params: true        # silently drop unsupported provider params

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
EOF
  } > "$LITELLM_CONFIG"

  log_ok "config.yaml generated (only providers with keys are enabled)."
}

#-------------------------------------------------------------------------------
# Container lifecycle
#-------------------------------------------------------------------------------
build_docker_env_args() {
  DOCKER_ENV_ARGS=(-e "LITELLM_MASTER_KEY=${MASTER_KEY}")
  # Admin panel (UI) login credentials: http://127.0.0.1:4000/ui
  DOCKER_ENV_ARGS+=(-e "UI_USERNAME=admin" -e "UI_PASSWORD=${MASTER_KEY}")
  if [ -n "$GROQ_KEY" ];       then DOCKER_ENV_ARGS+=(-e "GROQ_API_KEY=${GROQ_KEY}"); fi
  if [ -n "$OPENROUTER_KEY" ]; then DOCKER_ENV_ARGS+=(-e "OPENROUTER_API_KEY=${OPENROUTER_KEY}"); fi
  if [ -n "$GEMINI_KEY" ];     then DOCKER_ENV_ARGS+=(-e "GEMINI_API_KEY=${GEMINI_KEY}"); fi
  if [ -n "$CEREBRAS_KEY" ];   then DOCKER_ENV_ARGS+=(-e "CEREBRAS_API_KEY=${CEREBRAS_KEY}"); fi
  if [ -n "$MISTRAL_KEY" ];    then DOCKER_ENV_ARGS+=(-e "MISTRAL_API_KEY=${MISTRAL_KEY}"); fi
  return 0
}

remove_existing_container() {
  if $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log_warn "       Found existing container '${CONTAINER_NAME}'. Removing it..."
    $SUDO docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  return 0
}

pull_liteLLM_image() {
  log_info "[6/9] Pulling prebuilt LiteLLM image (no build step): ${LITELLM_IMAGE}"
  log_info "       This may take several minutes on the first run..."
  if ! $SUDO docker pull "$LITELLM_IMAGE"; then
    die "Image pull failed. Check your connection. ghcr.io is usually NOT blocked;
         if it is, configure an HTTPS_PROXY for Docker and retry."
  fi
  log_ok "Image pulled successfully."
}

start_litellm_container() {
  log_info "[7/9] Starting LiteLLM container on port ${LITELLM_PORT}..."
  remove_existing_container
  build_docker_env_args

  $SUDO docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${LITELLM_PORT}:4000" \
    -v "${LITELLM_CONFIG}:/app/config.yaml:ro" \
    "${DOCKER_ENV_ARGS[@]}" \
    "$LITELLM_IMAGE" \
    --config /app/config.yaml \
    --port 4000 >/dev/null

  log_ok "Container '${CONTAINER_NAME}' started (restart policy: unless-stopped)."
}

wait_for_litellm() {
  log_info "       Waiting for LiteLLM to become healthy (up to 60s)..."
  local i http_code=""
  for i in $(seq 1 30); do
    http_code=""
    if command -v curl >/dev/null 2>&1; then
      http_code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${LITELLM_PORT}/health/liveliness" 2>/dev/null || true)"
    elif command -v wget >/dev/null 2>&1; then
      if wget -q -O /dev/null "http://127.0.0.1:${LITELLM_PORT}/health/liveliness" 2>/dev/null; then
        http_code="200"
      fi
    else
      log_warn "       Neither curl nor wget found - skipping health check."
      return 0
    fi
    if [ "$http_code" = "200" ]; then
      log_ok "LiteLLM is healthy: http://127.0.0.1:${LITELLM_PORT}"
      return 0
    fi
    sleep 2
  done
  log_warn "Health check timed out. The proxy may still be booting."
  log_warn "Inspect logs with:  ${SUDO} docker logs -f ${CONTAINER_NAME}"
}

#-------------------------------------------------------------------------------
# Auto-start on WSL boot + management CLI (litellm up/down/restart/uninstall)
#-------------------------------------------------------------------------------
write_boot_helper() {
  $SUDO mkdir -p "$(dirname "$BOOT_HELPER")"
  {
    echo '#!/usr/bin/env bash'
    echo '# Auto-generated by LiteLLM.sh - starts Docker and the litellm container at WSL boot.'
    echo 'LOG="${TMPDIR:-/tmp}/litellm-boot.log"'
    echo '{'
    echo '  if [ "$(id -u)" -eq 0 ]; then S=""; else S="sudo"; fi'
    echo '  $S service docker start >/dev/null 2>&1 || true'
    echo '  for i in $(seq 1 30); do $S docker info >/dev/null 2>&1 && break; sleep 1; done'
    echo '  if $S docker ps -a --format "{{.Names}}" 2>/dev/null | grep -qx litellm; then'
    echo '    $S docker start litellm >/dev/null 2>&1 || true'
    echo '  fi'
    echo '} >>"$LOG" 2>&1'
  } | $SUDO tee "$BOOT_HELPER" >/dev/null
  $SUDO chmod 755 "$BOOT_HELPER"
}

write_management_cli() {
  $SUDO mkdir -p "$(dirname "$CLI_BIN")"
  cat <<'LITEOF' | $SUDO tee "$CLI_BIN" >/dev/null
#!/usr/bin/env bash
#===============================================================================
# litellm - management CLI for the LiteLLM <-> OpenCode proxy (WSL2)
# Installed by the LiteLLM.sh setup script.
#
#   litellm up          Start the proxy (and Docker daemon if needed)
#   litellm down        Stop the proxy
#   litellm restart     Restart the proxy and wait until healthy
#   litellm status      Show container state, health and config paths
#   litellm logs        Follow the proxy logs (Ctrl+C to exit)
#   litellm uninstall   Remove the proxy, all configs and this CLI
#===============================================================================
set -u

CONTAINER_NAME="litellm"
PORT="4000"
LITELLM_DIR="${HOME}/.litellm"
KEYFILE="${LITELLM_DIR}/master_key.txt"
CONFIG_FILE="${LITELLM_DIR}/config.yaml"
CLI_BIN="/usr/local/bin/litellm"
BOOT_HELPER="/usr/local/bin/litellm-boot.sh"
SYSTEMD_UNIT="/etc/systemd/system/litellm.service"
WSL_CONF="/etc/wsl.conf"
BOOT_LINE="command = /usr/local/bin/litellm-boot.sh"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

log_info()  { echo "[INFO] $*"; }
log_ok()    { echo "[ OK ] $*"; }
log_warn()  { echo "[WARN] $*"; }
log_error() { echo "[FAIL] $*" >&2; }

daemon_up() { $SUDO docker info >/dev/null 2>&1; }

ensure_daemon() {
  if daemon_up; then return 0; fi
  log_info "Starting the Docker daemon..."
  $SUDO service docker start >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 20); do
    if daemon_up; then log_ok "Docker daemon is up."; return 0; fi
    sleep 1
  done
  log_error "Docker daemon did not start. Try: sudo service docker start"
  return 1
}

container_exists() { $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; }
is_running()       { [ "$($SUDO docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = "true" ]; }

health_code() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${PORT}/health/liveliness" 2>/dev/null || true
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -O /dev/null "http://127.0.0.1:${PORT}/health/liveliness" 2>/dev/null; then echo 200; else echo 000; fi
  else
    echo "n/a"
  fi
}

wait_healthy() {
  local i code
  for i in $(seq 1 15); do
    code="$(health_code)"
    if [ "$code" = "200" ]; then
      log_ok "LiteLLM is healthy: http://127.0.0.1:${PORT}"
      return 0
    fi
    sleep 2
  done
  log_warn "Proxy is up but the health check timed out. Logs: ${SUDO} docker logs -f ${CONTAINER_NAME}"
  return 0
}

win_home() {
  local ps=""
  if command -v powershell.exe >/dev/null 2>&1; then
    ps="powershell.exe"
  elif [ -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
    ps="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  fi
  [ -n "$ps" ] || return 1
  local raw drive letter rest
  raw="$($ps -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')" 2>/dev/null | tr -d '\r')" || return 1
  [ -n "$raw" ] || return 1
  drive="${raw%%:*}"
  letter="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
  rest="${raw#*:}"
  rest="${rest//\\//}"
  printf '/mnt/%s%s' "$letter" "$rest"
}

cmd_up() {
  ensure_daemon || return 1
  if ! container_exists; then
    log_error "Container '${CONTAINER_NAME}' does not exist. Run the installer first."
    return 1
  fi
  if is_running; then
    log_ok "Proxy is already running."
  else
    log_info "Starting '${CONTAINER_NAME}'..."
    $SUDO docker start "$CONTAINER_NAME" >/dev/null
    log_ok "Container started."
  fi
  wait_healthy
}

cmd_down() {
  if ! container_exists; then
    log_warn "No container named '${CONTAINER_NAME}' found."
    return 0
  fi
  if is_running; then
    $SUDO docker stop "$CONTAINER_NAME" >/dev/null
    log_ok "Proxy stopped."
  else
    log_ok "Proxy is already stopped."
  fi
}

cmd_restart() {
  ensure_daemon || return 1
  $SUDO docker restart "$CONTAINER_NAME" >/dev/null
  log_ok "Proxy restarted."
  wait_healthy
}

cmd_status() {
  ensure_daemon || return 1
  if ! container_exists; then
    log_warn "Container '${CONTAINER_NAME}' is not installed."
    return 1
  fi
  local state policy
  state="$($SUDO docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
  policy="$($SUDO docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
  echo "  Container state : ${state}"
  echo "  Restart policy  : ${policy}"
  echo "  Health endpoint : $(health_code)  (http://127.0.0.1:${PORT}/health/liveliness)"
  echo "  OpenAI endpoint : http://127.0.0.1:${PORT}/v1"
  echo "  Admin panel     : http://127.0.0.1:${PORT}/ui  (user: admin, password: master key)"
  echo "  Config file     : ${CONFIG_FILE}$([ -f "$CONFIG_FILE" ] && echo ' (present)' || echo ' (missing)')"
  echo "  Master key file : ${KEYFILE}$([ -f "$KEYFILE" ] && echo ' (present)' || echo ' (missing)')"
}

cmd_logs() {
  ensure_daemon || return 1
  $SUDO docker logs -f --tail 100 "$CONTAINER_NAME"
}

cmd_uninstall() {
  local assume_yes="${1:-}"
  if [ "$assume_yes" != "--yes" ] && [ "$assume_yes" != "-y" ]; then
    printf "This removes the proxy container, all configs and this CLI. Continue? [y/N]: "
    local answer=""
    read -r answer || answer=""
    case "$answer" in
      y|Y|yes|YES) ;;
      *) log_info "Aborted."; return 1 ;;
    esac
  fi

  if container_exists; then
    $SUDO docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    $SUDO docker rm "$CONTAINER_NAME"   >/dev/null 2>&1 || true
    log_ok "Container removed."
  else
    log_warn "No container named '${CONTAINER_NAME}' found."
  fi

  if [ -d "$LITELLM_DIR" ]; then
    rm -rf "$LITELLM_DIR"
    log_ok "Removed ${LITELLM_DIR}"
  fi

  local wh oc
  wh="$(win_home || true)"
  if [ -n "$wh" ] && [ -d "$wh" ]; then
    oc="${wh}/.config/opencode/opencode.json"
    if [ -f "$oc" ]; then
      rm -f "$oc"
      log_ok "Removed ${oc}"
    fi
  fi

  if $SUDO test -f "$SYSTEMD_UNIT"; then
    $SUDO rm -f "$SYSTEMD_UNIT"
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    log_ok "Removed systemd service."
  fi
  if $SUDO test -f "$BOOT_HELPER"; then
    $SUDO rm -f "$BOOT_HELPER"
    log_ok "Removed boot helper."
  fi
  if $SUDO test -f "$WSL_CONF" && $SUDO grep -qF "$BOOT_LINE" "$WSL_CONF" 2>/dev/null; then
    $SUDO sed -i "\|^${BOOT_LINE}\$|d" "$WSL_CONF"
    log_ok "Removed boot entry from ${WSL_CONF}."
  fi
  if $SUDO test -f "$CLI_BIN"; then
    $SUDO rm -f "$CLI_BIN"
    log_ok "Management CLI removed."
  fi

  echo
  log_ok "UNINSTALL COMPLETED."
  echo "  Kept: Docker Engine, /etc/docker/daemon.json and the pulled image."
  return 0
}

case "${1:-}" in
  up)        shift; cmd_up "$@" ;;
  down)      shift; cmd_down "$@" ;;
  restart)   shift; cmd_restart "$@" ;;
  status)    shift; cmd_status "$@" ;;
  logs)      shift; cmd_logs "$@" ;;
  uninstall) shift; cmd_uninstall "${1:-}"; exit $? ;;
  ""|help|-h|--help)
    echo "Usage: litellm {up|down|restart|status|logs|uninstall}"
    echo "  up          start the proxy (and Docker if needed)"
    echo "  down        stop the proxy"
    echo "  restart     restart the proxy and wait until healthy"
    echo "  status      show container state, health and config paths"
    echo "  logs        follow proxy logs (Ctrl+C to exit)"
    echo "  uninstall   remove proxy, configs and this CLI"
    ;;
  *) log_error "Unknown command: '${1}'. Try 'litellm help'."; exit 1 ;;
esac
LITEOF
  $SUDO chmod 755 "$CLI_BIN"
}

# Auto-start mode: auto (default) | systemd | wslconf  (env: LITELLM_BOOT_MODE)
use_systemd() {
  case "${LITELLM_BOOT_MODE:-auto}" in
    systemd) return 0 ;;
    wslconf) return 1 ;;
    *) [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && return 0 ;;
  esac
  return 1
}

configure_autostart_and_cli() {
  log_info "[8/9] Setting up auto-start on boot + management CLI..."
  write_boot_helper
  write_management_cli

  if use_systemd; then
    # real systemd available (wsl.conf [boot] systemd=true)
    $SUDO mkdir -p /etc/systemd/system
    printf '%s\n' \
      '[Unit]' \
      'Description=LiteLLM proxy container (Docker)' \
      'After=docker.service' \
      'Requires=docker.service' \
      '' \
      '[Service]' \
      'Type=oneshot' \
      'RemainAfterExit=yes' \
      'ExecStart=/usr/local/bin/litellm-boot.sh' \
      '' \
      '[Install]' \
      'WantedBy=multi-user.target' \
      | $SUDO tee "$SYSTEMD_UNIT" >/dev/null
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    $SUDO systemctl enable litellm.service >/dev/null 2>&1 || true
    AUTOSTART_MODE="systemd service: litellm.service (enabled)"
  else
    # no systemd -> WSL boot command (runs as root when the distro starts)
    if ! $SUDO test -f "$WSL_CONF"; then
      printf '' | $SUDO tee "$WSL_CONF" >/dev/null
    fi
    if $SUDO grep -qF "$BOOT_LINE" "$WSL_CONF" 2>/dev/null; then
      log_ok "       Boot entry already present in ${WSL_CONF}."
    elif $SUDO grep -qE '^[[:space:]]*command[[:space:]]*=' "$WSL_CONF" 2>/dev/null; then
      log_warn "       ${WSL_CONF} already defines a custom boot command - add this line under [boot] manually:"
      log_warn "         ${BOOT_LINE}"
    else
      if $SUDO grep -qE '^[[:space:]]*\[boot\]' "$WSL_CONF" 2>/dev/null; then
        $SUDO sed -i "/^[[:space:]]*\[boot\]/a ${BOOT_LINE}" "$WSL_CONF"
      else
        printf '\n[boot]\n%s\n' "$BOOT_LINE" | $SUDO tee -a "$WSL_CONF" >/dev/null
      fi
      log_ok "       Boot command added to ${WSL_CONF}."
    fi
    AUTOSTART_MODE="/etc/wsl.conf boot command (no systemd detected)"
  fi

  log_ok "Auto-start on WSL boot: ${AUTOSTART_MODE}"
  log_ok "Management CLI installed: ${CLI_BIN}  (try: litellm status)"
}

#-------------------------------------------------------------------------------
# OpenCode configuration on the Windows side
#-------------------------------------------------------------------------------
collect_opencode_models() {
  OC_MODELS_BLOCK=""
  DEFAULT_MODEL=""
  local sep=""

  add_oc_model() {
    OC_MODELS_BLOCK+="${sep}        \"${1}\": { \"name\": \"${2}\" }"
    sep=",$(printf '\n        ')"
  }

  if [ -n "$GROQ_KEY" ]; then
    add_oc_model "qwen-2.5-coder-32b"      "Qwen 2.5 Coder 32B (Groq, free)"
    add_oc_model "llama-3.3-70b-versatile" "Llama 3.3 70B Versatile (Groq, free)"
    if [ -z "$DEFAULT_MODEL" ]; then DEFAULT_MODEL="qwen-2.5-coder-32b"; fi
  fi
  if [ -n "$OPENROUTER_KEY" ]; then
    add_oc_model "deepseek/deepseek-chat-v3:free" "DeepSeek Chat V3 (OpenRouter, free)"
    add_oc_model "deepseek/deepseek-r1:free"      "DeepSeek R1 (OpenRouter, free)"
    if [ -z "$DEFAULT_MODEL" ]; then DEFAULT_MODEL="deepseek/deepseek-chat-v3:free"; fi
  fi
  if [ -n "$GEMINI_KEY" ]; then
    add_oc_model "gemini-2.0-flash" "Gemini 2.0 Flash (Google AI, free)"
    if [ -z "$DEFAULT_MODEL" ]; then DEFAULT_MODEL="gemini-2.0-flash"; fi
  fi
  if [ -n "$CEREBRAS_KEY" ]; then
    add_oc_model "llama3.1-70b" "Llama 3.1 70B (Cerebras, free)"
    if [ -z "$DEFAULT_MODEL" ]; then DEFAULT_MODEL="llama3.1-70b"; fi
  fi
  if [ -n "$MISTRAL_KEY" ]; then
    add_oc_model "codestral-latest" "Codestral (Mistral)"
    if [ -z "$DEFAULT_MODEL" ]; then DEFAULT_MODEL="codestral-latest"; fi
  fi
  return 0
}

configure_opencode_windows() {
  log_info "[9/9] Configuring OpenCode on the Windows side..."

  local win_home oc_dir
  win_home="$(get_windows_home)" || \
    die "Could not detect the Windows user profile via PowerShell."

  if [ ! -d "$win_home" ]; then
    die "Converted Windows profile path does not exist in WSL: ${win_home}"
  fi
  log_ok "Windows user profile detected: ${win_home}"

  oc_dir="${win_home}/.config/opencode"
  OC_FILE="${oc_dir}/opencode.json"
  mkdir -p "$oc_dir"

  collect_opencode_models

  cat > "$OC_FILE" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "litellm/${DEFAULT_MODEL}",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Proxy (Local)",
      "options": {
        "baseURL": "http://127.0.0.1:${LITELLM_PORT}/v1",
        "apiKey": "${MASTER_KEY}"
      },
      "models": {
${OC_MODELS_BLOCK}
      }
    }
  }
}
EOF

  log_ok "OpenCode config written: ${OC_FILE}"
}

#-------------------------------------------------------------------------------
# Full Install
#-------------------------------------------------------------------------------
full_install() {
  echo
  log_info "=== FULL INSTALL: starting ==="
  echo

  check_wsl_environment                       # step 1
  install_docker                              # step 2
  configure_docker_mirrors                    # step 3
  start_docker_daemon
  collect_api_keys                            # step 4
  generate_master_key
  generate_litellm_config                     # step 5
  pull_liteLLM_image                          # step 6
  start_litellm_container                     # step 7
  wait_for_litellm
  configure_autostart_and_cli                 # step 8 (autostart + litellm CLI)

  OC_FILE=""
  configure_opencode_windows                  # step 9

  print_install_success "$OC_FILE"
}

print_install_success() {
  local oc_file="$1"
  echo
  echo -e "${C_GREEN}${C_BOLD}================================================================="
  echo "  INSTALLATION COMPLETED SUCCESSFULLY!"
  echo -e "=================================================================${C_NC}"
  echo
  echo "  LiteLLM endpoint (from Windows) : http://127.0.0.1:${LITELLM_PORT}/v1"
  echo
  echo -e "${C_BOLD}  ADMIN PANEL (UI) - open in the WINDOWS browser:${C_NC}"
  echo "    URL       : http://127.0.0.1:${LITELLM_PORT}/ui"
  echo "    Username  : admin"
  echo "    Password  : (the Master key below)"
  echo
  echo "  Master key (also saved to)      : ${LITELLM_KEYFILE}"
  echo "  Master key                      : ${MASTER_KEY}"
  echo "  LiteLLM config file             : ${LITELLM_CONFIG}"
  echo "  OpenCode config file (Windows)  : ${oc_file}"
  echo "  Container name                  : ${CONTAINER_NAME}"
  echo "  Auto-start on WSL boot          : ${AUTOSTART_MODE}"
  echo
  echo -e "${C_BOLD}  MANAGEMENT COMMANDS (any terminal):${C_NC}"
  echo "    litellm up | down | restart | status | logs | uninstall"
  echo
  echo -e "${C_BOLD}  USEFUL COMMANDS (run inside WSL):${C_NC}"
  echo "    Live logs        : ${SUDO} docker logs -f ${CONTAINER_NAME}"
  echo "    Restart proxy    : ${SUDO} docker restart ${CONTAINER_NAME}"
  echo "    Stop proxy       : ${SUDO} docker stop ${CONTAINER_NAME}"
  echo "    Start proxy      : ${SUDO} docker start ${CONTAINER_NAME}"
  echo "    Test endpoint    : curl -s http://127.0.0.1:${LITELLM_PORT}/v1/models \\"
  echo "                         -H \"Authorization: Bearer ${MASTER_KEY}\""
  local rerun="bash \"${SCRIPT_PATH}\""
  case "$SCRIPT_PATH" in
    /dev/fd/*|/dev/stdin|/dev/fd*)
      rerun='bash <(curl -fsSL https://raw.githubusercontent.com/im-JvD/LiteLLM-OpenCode/main/LiteLLM.sh)' ;;
  esac
  echo "    Re-run this tool : ${rerun}"
  echo
  echo -e "${C_BOLD}  NEXT STEPS (on WINDOWS):${C_NC}"
  echo "    1. Open a NEW terminal (PowerShell or CMD)."
  echo "    2. cd into any project folder."
  echo "    3. Run: opencode"
  echo "    4. Pick the provider 'LiteLLM Proxy (Local)' and a model."
  echo
  echo "  NOTE: If you ever run 'wsl --shutdown', start Docker again with:"
  echo "        sudo service docker start   (auto if systemd is enabled)"
  echo
  log_ok "Done. Happy coding!"
}

#-------------------------------------------------------------------------------
# Full Uninstall
#-------------------------------------------------------------------------------
full_uninstall() {
  echo
  log_info "=== FULL UNINSTALL: starting ==="
  echo

  # 1) Remove the LiteLLM container
  if command -v docker >/dev/null 2>&1 && \
     $SUDO docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log_info "Stopping and removing container '${CONTAINER_NAME}'..."
    $SUDO docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    $SUDO docker rm "$CONTAINER_NAME"   >/dev/null 2>&1 || true
    log_ok "Container removed."
  else
    log_warn "No container named '${CONTAINER_NAME}' found - nothing to remove."
  fi

  # 2) Remove the LiteLLM config folder in Linux
  if [ -d "$LITELLM_DIR" ]; then
    rm -rf "$LITELLM_DIR"
    log_ok "Removed LiteLLM config folder: ${LITELLM_DIR}"
  else
    log_warn "LiteLLM config folder not found: ${LITELLM_DIR}"
  fi

  # 3) Remove opencode.json on the Windows side
  if find_powershell >/dev/null 2>&1; then
    local win_home oc_file
    win_home="$(get_windows_home)" || win_home=""
    if [ -n "$win_home" ] && [ -d "$win_home" ]; then
      oc_file="${win_home}/.config/opencode/opencode.json"
      if [ -f "$oc_file" ]; then
        rm -f "$oc_file"
        log_ok "Removed OpenCode config: ${oc_file}"
      else
        log_warn "OpenCode config not found: ${oc_file}"
      fi
    else
      log_warn "Could not resolve the Windows profile. Delete this file manually:"
      log_warn "  %USERPROFILE%\\.config\\opencode\\opencode.json"
    fi
  else
    log_warn "powershell.exe not found. Delete this file manually:"
    log_warn "  %USERPROFILE%\\.config\\opencode\\opencode.json"
  fi

  # 4) Remove boot persistence (systemd service / wsl.conf boot entry / helper)
  if $SUDO test -f "$SYSTEMD_UNIT"; then
    $SUDO rm -f "$SYSTEMD_UNIT"
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    log_ok "Removed systemd service: ${SYSTEMD_UNIT}"
  fi
  if $SUDO test -f "$BOOT_HELPER"; then
    $SUDO rm -f "$BOOT_HELPER"
    log_ok "Removed boot helper: ${BOOT_HELPER}"
  fi
  if $SUDO test -f "$WSL_CONF" && $SUDO grep -qF "$BOOT_LINE" "$WSL_CONF" 2>/dev/null; then
    $SUDO sed -i "\|^${BOOT_LINE}\$|d" "$WSL_CONF"
    log_ok "Removed boot entry from ${WSL_CONF}"
  fi

  # 5) Remove the management CLI
  if $SUDO test -f "$CLI_BIN"; then
    $SUDO rm -f "$CLI_BIN"
    log_ok "Removed management CLI: ${CLI_BIN}"
  fi

  echo
  echo -e "${C_GREEN}${C_BOLD}================================================================="
  echo "  UNINSTALL COMPLETED SUCCESSFULLY!"
  echo -e "=================================================================${C_NC}"
  echo
  echo "  Removed:"
  echo "    - Docker container : ${CONTAINER_NAME}"
  echo "    - Linux folder     : ${LITELLM_DIR}  (config.yaml + master key)"
  echo "    - Windows file     : ~/.config/opencode/opencode.json"
  echo "    - Boot persistence : systemd service / wsl.conf boot entry / helper"
  echo "    - Management CLI   : ${CLI_BIN}"
  echo
  echo "  Kept (on purpose):"
  echo "    - Docker Engine itself and /etc/docker/daemon.json (mirrors)"
  echo
  log_ok "Done."
}

#-------------------------------------------------------------------------------
# Interactive menu
#-------------------------------------------------------------------------------
show_menu() {
  echo
  echo -e "${C_BOLD}================================================================="
  echo "     LiteLLM  <->  OpenCode  Bridge  |  WSL2 Ubuntu Setup"
  echo -e "=================================================================${C_NC}"
  echo
  echo "   Proxy target : ${LITELLM_IMAGE}"
  echo "   Proxy port   : ${LITELLM_PORT}   (restart policy: unless-stopped)"
  echo "   Linux config : ${LITELLM_DIR}"
  echo
  echo "   Please choose an option:"
  echo
  echo -e "     ${C_BOLD}1)${C_NC} Full Install    (Docker + LiteLLM proxy + OpenCode config)"
  echo -e "     ${C_BOLD}2)${C_NC} Full Uninstall  (remove container + all generated configs)"
  echo -e "     ${C_BOLD}q)${C_NC} Quit"
  echo
  read -r -p "   Enter your choice [1/2/q]: " CHOICE || CHOICE=""
  echo
}

main() {
  show_menu
  case "$CHOICE" in
    1) full_install ;;
    2) full_uninstall ;;
    q|Q) log_info "Bye!" ;;
    *) die "Invalid choice: '${CHOICE}'. Run the script again and pick 1, 2 or q." ;;
  esac
}

main "$@"
