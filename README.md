# LiteLLM-OpenCode
LiteLLM Installation and Configuration for OpenCode

## Quick Start (WSL2 Ubuntu)

```bash
bash litellm_opencode_setup.sh
```

Interactive menu:

- `1) Full Install` — installs Docker from the Ubuntu apt repository (`docker.io`,
  no `get.docker.com`), configures Iranian Docker Hub mirrors in
  `/etc/docker/daemon.json`, pulls the prebuilt image
  `ghcr.io/berriai/litellm:main-latest` (never builds), asks for up to 5 API keys
  (Groq / OpenRouter / Google AI / Cerebras / Mistral — at least one required),
  generates `~/.litellm/config.yaml`, starts the proxy on port `4000` with
  `--restart unless-stopped`, and writes the OpenCode provider config to
  `%USERPROFILE%\.config\opencode\opencode.json` pointing at
  `http://127.0.0.1:4000/v1`.
- `2) Full Uninstall` — stops and removes the container, deletes the Linux
  config folder and the Windows `opencode.json`.

The Windows user profile is detected through PowerShell only
(`[Environment]::GetFolderPath('UserProfile')`), so usernames containing
spaces are handled safely.

All script output is plain English ASCII (RTL-safe in Windows terminals).
Run the script WITHOUT `sudo`; it escalates only where needed.
