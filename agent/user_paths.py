from __future__ import annotations

import os
import pwd
from pathlib import Path

HOME = Path.home()
USER = pwd.getpwuid(os.getuid()).pw_name
XDG_CONFIG_HOME = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config'))
XDG_DATA_HOME = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share'))
XDG_STATE_HOME = Path(os.environ.get('XDG_STATE_HOME', HOME / '.local/state'))
LOCAL_BIN = HOME / '.local/bin'
NPM_GLOBAL_BIN = HOME / '.npm-global/bin'

BUX_CONFIG_DIR = XDG_CONFIG_HOME / 'bux'
BUX_DATA_DIR = XDG_DATA_HOME / 'bux'
BUX_STATE_DIR = XDG_STATE_HOME / 'bux'
BUX_LOG_DIR = BUX_STATE_DIR / 'logs'
REPO_DIR = Path(os.environ.get('BUX_REPO_DIR', BUX_DATA_DIR / 'repo'))
VENV_DIR = Path(os.environ.get('BUX_VENV_DIR', BUX_DATA_DIR / 'venv'))

TG_ENV = BUX_CONFIG_DIR / 'tg.env'
BOX_ENV = BUX_CONFIG_DIR / 'env'
OPENAI_ENV = BUX_CONFIG_DIR / 'openai.env'
ALLOWED_FILE = BUX_STATE_DIR / 'tg-allowed.txt'
STATE_FILE = BUX_STATE_DIR / 'tg-state.json'
QUEUE_FILE = BUX_STATE_DIR / 'tg-queue.json'
LAST_ANNOUNCED_SHA = BUX_STATE_DIR / 'last-announced.sha'
UPDATE_REQUEST_LANES = BUX_STATE_DIR / 'update-request.lanes'
SESSIONS_DIR = BUX_STATE_DIR / 'sessions'
LEGACY_SESSION_FILE = BUX_STATE_DIR / 'session'
APPROVALS_DIR = Path('/tmp/tg-approvals')
WORKSPACE = HOME
BROWSER_ENV = HOME / '.claude' / 'browser.env'
CLAUDE_PROJECTS_DIR = HOME / '.claude' / 'projects'
INBOX_DIR = BUX_STATE_DIR / 'inbox'


def workspace_slug(path: Path) -> str:
    resolved = path.resolve()
    return str(resolved).replace('/', '-')


def claude_project_dir(path: Path = WORKSPACE) -> Path:
    return CLAUDE_PROJECTS_DIR / workspace_slug(path)
