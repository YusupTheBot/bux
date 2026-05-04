#!/usr/bin/env python3
"""browser-keeper — maintains a long-lived local Chrome session with CDP.

Writes /home/bux/.claude/browser.env (mode 640, owner bux:bux):
    BU_CDP_URL=http://127.0.0.1:9222
    BU_CDP_WS=ws://127.0.0.1:9222/devtools/browser/<id>
    BU_BROWSER_ID=<id>
    BU_BROWSER_LIVE_URL=

Behavior:
- If a Chrome/Chromium instance is already listening on BU_CDP_URL, attach to it.
- Otherwise launch a dedicated browser with remote debugging on that URL.
- Prefer a real window when DISPLAY/WAYLAND is present; fall back to headless.
- Keep a persistent user-data-dir so cookies/logins survive restarts.
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

STATE_DIR = pathlib.Path('/home/bux/.claude')
ENV_FILE = STATE_DIR / 'browser.env'
STATE_DIR.mkdir(parents=True, exist_ok=True)

CDP_URL = os.environ.get('BUX_CDP_URL', 'http://127.0.0.1:9222')
CHROME_BIN = os.environ.get('BUX_CHROME_BIN') or shutil.which('google-chrome') or shutil.which('chromium') or shutil.which('chromium-browser')
CHROME_PROFILE_DIR = pathlib.Path(os.environ.get('BUX_CHROME_PROFILE_DIR', '/home/bux/browser-profile'))
WINDOW_SIZE = os.environ.get('BUX_CHROME_WINDOW_SIZE', '1280,720')
STARTUP_TIMEOUT_SEC = int(os.environ.get('BUX_CHROME_STARTUP_TIMEOUT_SEC', '30'))
POLL_INTERVAL_SEC = int(os.environ.get('BUX_KEEPER_POLL_INTERVAL_SEC', '30'))

if not CHROME_BIN:
    sys.exit('no Chrome/Chromium binary found (set BUX_CHROME_BIN)')

parsed = urlparse(CDP_URL)
if parsed.scheme not in {'http', 'https'} or not parsed.hostname or not parsed.port:
    sys.exit(f'invalid BUX_CDP_URL: {CDP_URL}')

CDP_HOST = parsed.hostname
CDP_PORT = parsed.port

_current_proc: subprocess.Popen | None = None
_owned_browser = False


def log(msg: str) -> None:
    print(f'[keeper] {msg}', flush=True)


def _http_json(url: str, timeout: int = 10) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def browser_version() -> dict | None:
    try:
        return _http_json(f'{CDP_URL}/json/version', timeout=5)
    except Exception:
        return None


def browser_ws() -> str:
    info = browser_version() or {}
    return str(info.get('webSocketDebuggerUrl') or '')


def browser_id_from_ws(ws: str) -> str:
    marker = '/devtools/browser/'
    if marker in ws:
        return ws.split(marker, 1)[1].strip()
    return ''


def health_check() -> tuple[bool, str, str]:
    info = browser_version()
    if not info:
        return False, '', ''
    ws = str(info.get('webSocketDebuggerUrl') or '')
    bid = browser_id_from_ws(ws)
    return bool(ws), ws, bid


def write_env(ws: str, bid: str) -> None:
    tmp = ENV_FILE.with_suffix('.tmp')
    payload = (
        f'BU_CDP_URL={CDP_URL}\n'
        f'BU_CDP_WS={ws}\n'
        f'BU_BROWSER_ID={bid}\n'
        'BU_BROWSER_LIVE_URL=\n'
    )
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    fd = os.open(str(tmp), os.O_CREAT | os.O_WRONLY | os.O_EXCL | os.O_CLOEXEC, 0o640)
    try:
        os.write(fd, payload.encode())
    finally:
        os.close(fd)
    tmp.replace(ENV_FILE)
    try:
        import pwd
        u = pwd.getpwnam('bux')
        os.chown(str(ENV_FILE), u.pw_uid, u.pw_gid)
    except Exception:
        pass


def launch_browser() -> subprocess.Popen:
    CHROME_PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    has_gui = bool(os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'))
    cmd = [
        CHROME_BIN,
        f'--remote-debugging-port={CDP_PORT}',
        f'--remote-debugging-address={CDP_HOST}',
        f'--user-data-dir={CHROME_PROFILE_DIR}',
        f'--window-size={WINDOW_SIZE}',
        '--no-first-run',
        '--no-default-browser-check',
        'about:blank',
    ]
    if not has_gui:
        cmd.insert(1, '--headless=new')
    log(f'launching local Chrome: {cmd[0]} on {CDP_URL} (gui={has_gui})')
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ensure_browser() -> tuple[str, str]:
    global _current_proc, _owned_browser
    ok, ws, bid = health_check()
    if ok:
        _owned_browser = False
        return ws, bid

    if _current_proc is None or _current_proc.poll() is not None:
        _current_proc = launch_browser()
        _owned_browser = True

    deadline = time.time() + STARTUP_TIMEOUT_SEC
    while time.time() < deadline:
        ok, ws, bid = health_check()
        if ok:
            return ws, bid
        if _current_proc is not None and _current_proc.poll() is not None:
            raise RuntimeError(f'chrome exited early rc={_current_proc.returncode}')
        time.sleep(1)
    raise RuntimeError(f'chrome did not expose CDP at {CDP_URL} within {STARTUP_TIMEOUT_SEC}s')


def shutdown(*_args) -> None:
    global _current_proc
    if _owned_browser and _current_proc is not None and _current_proc.poll() is None:
        log('shutting down owned Chrome process')
        try:
            _current_proc.terminate()
            _current_proc.wait(timeout=10)
        except Exception:
            try:
                _current_proc.kill()
            except Exception:
                pass
    sys.exit(0)


def main() -> None:
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log(f'keeping local browser ready on {CDP_URL}')
    last_ws = ''
    while True:
        try:
            ws, bid = ensure_browser()
            if ws != last_ws:
                write_env(ws, bid)
                last_ws = ws
                log(f'wrote {ENV_FILE} ws={ws}')
            time.sleep(POLL_INTERVAL_SEC)
        except Exception as e:
            log(f'loop error: {e!r}, sleeping 5s')
            time.sleep(5)


if __name__ == '__main__':
    main()
