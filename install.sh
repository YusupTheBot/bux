#!/usr/bin/env bash
set -euo pipefail

BUX_REF="${BUX_REF:-main}"
BUX_CDP_URL="${BUX_CDP_URL:-http://127.0.0.1:9222}"
BUX_CHROME_BIN="${BUX_CHROME_BIN:-}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_SETUP_TOKEN="${TG_SETUP_TOKEN:-}"
TG_BOT_USERNAME="${TG_BOT_USERNAME:-}"
TG_OWNER_ID="${TG_OWNER_ID:-}"
TG_OWNER_USERNAME="${TG_OWNER_USERNAME:-}"
TG_OWNER_NAME="${TG_OWNER_NAME:-}"

HOME_DIR="$HOME"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
BIN_DIR="$HOME_DIR/.local/bin"
NPM_BIN_DIR="$HOME_DIR/.npm-global/bin"
CONFIG_DIR="$CONFIG_HOME/bux"
DATA_DIR="$DATA_HOME/bux"
STATE_DIR="$STATE_HOME/bux"
REPO_LINK="$DATA_DIR/repo"
VENV_DIR="$DATA_DIR/venv"
BROWSER_HARNESS_DIR="$DATA_DIR/browser-harness"
BROWSER_HARNESS_VENV="$DATA_DIR/browser-harness-venv"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"

say() { printf '➜ %s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }

[ "${EUID:-$(id -u)}" -ne 0 ] || die 'run install.sh as your normal user, not root'
command -v python3 >/dev/null 2>&1 || die 'python3 is required'
command -v git >/dev/null 2>&1 || die 'git is required'
command -v curl >/dev/null 2>&1 || die 'curl is required'
command -v systemctl >/dev/null 2>&1 || die 'systemctl is required'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$REPO_DIR" = '/dev' ] || [ ! -f "$REPO_DIR/agent/browser_keeper.py" ]; then
  say "fetching bux@${BUX_REF} from github"
  tmpdir="$(mktemp -d)"
  curl -fsSL "https://github.com/YusupTheBot/bux/archive/${BUX_REF}.tar.gz" | tar -xz -C "$tmpdir" --strip-components=1 || die "failed to download bux@${BUX_REF}"
  REPO_DIR="$tmpdir"
fi

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$STATE_DIR/logs" "$BIN_DIR" "$NPM_BIN_DIR" "$SYSTEMD_USER_DIR" "$HOME_DIR/.claude"
ln -sfn "$REPO_DIR" "$REPO_LINK"

append_path_line() {
  local file="$1"
  local line='export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"'
  touch "$file"
  grep -Fq "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
}
append_path_line "$HOME_DIR/.profile"
[ -f "$HOME_DIR/.zshrc" ] && append_path_line "$HOME_DIR/.zshrc"

if command -v npm >/dev/null 2>&1; then
  npm config set prefix "$HOME_DIR/.npm-global" >/dev/null 2>&1 || true
  if ! command -v claude >/dev/null 2>&1; then
    say 'installing Claude Code'
    npm install -g @anthropic-ai/claude-code
  fi
  if ! command -v codex >/dev/null 2>&1; then
    say 'installing Codex CLI'
    npm install -g @openai/codex || warn 'codex install failed; continuing'
  fi
else
  warn 'npm not found; assuming claude/codex are already installed elsewhere on PATH'
fi

if ! command -v viberelay >/dev/null 2>&1; then
  say 'installing viberelay'
  env VIBERELAY_AUTO_SERVICE=1 bash -lc 'curl -fsSL https://github.com/vibeproxy/viberelay/releases/latest/download/install.sh | bash'
fi

mkdir -p "$HOME_DIR/.viberelay/profiles"
if [ ! -f "$HOME_DIR/.viberelay/profiles/vibe.json" ]; then
  cat > "$HOME_DIR/.viberelay/profiles/vibe.json" <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8327",
    "ANTHROPIC_AUTH_TOKEN": "viberelay-local",
    "ANTHROPIC_MODEL": "high[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "high[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "mid[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "low[1m]",
    "CLAUDE_CODE_SUBAGENT_MODEL": "low[1m]"
  }
}
JSON
fi
viberelay start >/dev/null 2>&1 || true

if ! command -v browser-harness >/dev/null 2>&1; then
  say 'installing browser-harness'
  if [ ! -d "$BROWSER_HARNESS_DIR/.git" ]; then
    git clone --depth=1 https://github.com/browser-use/browser-harness "$BROWSER_HARNESS_DIR"
  fi
  python3 -m venv "$BROWSER_HARNESS_VENV"
  "$BROWSER_HARNESS_VENV/bin/pip" install --upgrade pip >/dev/null
  "$BROWSER_HARNESS_VENV/bin/pip" install -e "$BROWSER_HARNESS_DIR"
  ln -sfn "$BROWSER_HARNESS_VENV/bin/browser-harness" "$BIN_DIR/browser-harness"
fi

if ! command -v ttyd >/dev/null 2>&1; then
  say 'installing ttyd'
  arch="$(uname -m)"
  case "$arch" in
    x86_64) ttyd_arch=x86_64 ;;
    aarch64|arm64) ttyd_arch=aarch64 ;;
    *) die "unsupported arch for ttyd: $arch" ;;
  esac
  curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ttyd_arch}" -o "$BIN_DIR/ttyd"
  chmod +x "$BIN_DIR/ttyd"
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install -r "$REPO_LINK/agent/requirements.txt"

cat > "$CONFIG_DIR/env" <<EOF
BUX_CDP_URL=$BUX_CDP_URL
BUX_CHROME_BIN=$BUX_CHROME_BIN
BUX_REPO_DIR=$REPO_LINK
BUX_VENV_DIR=$VENV_DIR
EOF
chmod 600 "$CONFIG_DIR/env"

if [ -n "$TG_BOT_TOKEN" ]; then
  {
    printf 'TG_BOT_TOKEN=%s\n' "$TG_BOT_TOKEN"
    [ -n "$TG_SETUP_TOKEN" ] && printf 'TG_SETUP_TOKEN=%s\n' "$TG_SETUP_TOKEN"
    [ -n "$TG_BOT_USERNAME" ] && printf 'TG_BOT_USERNAME=%s\n' "$TG_BOT_USERNAME"
    [ -n "$TG_OWNER_ID" ] && printf 'TG_OWNER_ID=%s\n' "$TG_OWNER_ID"
    [ -n "$TG_OWNER_USERNAME" ] && printf 'TG_OWNER_USERNAME=%s\n' "$TG_OWNER_USERNAME"
    [ -n "$TG_OWNER_NAME" ] && printf 'TG_OWNER_NAME=%s\n' "$TG_OWNER_NAME"
  } > "$CONFIG_DIR/tg.env"
  chmod 600 "$CONFIG_DIR/tg.env"
fi

"$REPO_LINK/agent/bootstrap.sh"

say 'done'
printf '\nNext steps:\n'
printf '  1. Run: viberelay sync %s@<host>\n' "$USER"
printf '  2. Check: systemctl --user status box-agent bux-browser-keeper bux-ttyd\n'
printf '  3. If using Telegram, send a message to the bot after TG_BOT_TOKEN is set\n'
