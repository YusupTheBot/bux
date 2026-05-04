#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="$HOME"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
BIN_DIR="$HOME_DIR/.local/bin"
CONFIG_DIR="$CONFIG_HOME/bux"
DATA_DIR="$DATA_HOME/bux"
STATE_DIR="$STATE_HOME/bux"
REPO_DIR="${BUX_REPO_DIR:-$DATA_DIR/repo}"
VENV_DIR="${BUX_VENV_DIR:-$DATA_DIR/venv}"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"

[ "${EUID:-$(id -u)}" -ne 0 ] || { echo "bootstrap.sh must run as the target user, not root" >&2; exit 1; }

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$STATE_DIR" "$STATE_DIR/logs" "$SYSTEMD_USER_DIR" "$BIN_DIR"

ln -sfn "$REPO_DIR/agent/tg-send" "$BIN_DIR/tg-send"
ln -sfn "$REPO_DIR/agent/tg-schedule" "$BIN_DIR/tg-schedule"
ln -sfn "$REPO_DIR/agent/tg-schedule-fire" "$BIN_DIR/tg-schedule-fire"
ln -sfn "$REPO_DIR/agent/tg-approve.py" "$BIN_DIR/tg-approve"
chmod +x "$REPO_DIR/agent/tg-send" "$REPO_DIR/agent/tg-schedule" "$REPO_DIR/agent/tg-schedule-fire" "$REPO_DIR/agent/tg-approve.py"

if [ -f "$REPO_DIR/agent/CLAUDE.md" ]; then
  install -m 0644 "$REPO_DIR/agent/CLAUDE.md" "$HOME_DIR/CLAUDE.md"
  ln -sfn "$HOME_DIR/CLAUDE.md" "$HOME_DIR/AGENTS.md"
fi

if [ -f "$HOME_DIR/.profile" ] && ! grep -q 'browser.env' "$HOME_DIR/.profile" 2>/dev/null; then
  cat >> "$HOME_DIR/.profile" <<'PROFILE'

if [ -r "$HOME/.claude/browser.env" ]; then
  . "$HOME/.claude/browser.env" 2>/dev/null || true
  if [ -n "${BU_CDP_URL:-}" ]; then
    printf '\n  \033[1mBrowser CDP:\033[0m %s\n\n' "$BU_CDP_URL"
  fi
fi
PROFILE
fi

for unit in box-agent.service bux-browser-keeper.service bux-tg.service bux-ttyd.service; do
  install -m 0644 "$REPO_DIR/agent/$unit" "$SYSTEMD_USER_DIR/$unit"
done

systemctl --user daemon-reload
systemctl --user enable box-agent.service bux-browser-keeper.service bux-ttyd.service >/dev/null
systemctl --user restart box-agent.service bux-browser-keeper.service bux-ttyd.service
if [ -f "$CONFIG_DIR/tg.env" ]; then
  systemctl --user enable bux-tg.service >/dev/null
  systemctl --user restart bux-tg.service
else
  systemctl --user stop bux-tg.service >/dev/null 2>&1 || true
fi

echo "bootstrap: done"
