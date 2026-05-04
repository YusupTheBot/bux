# Installing bux

bux runs on any box that runs Ubuntu / Debian 22.04+. 2GB RAM is enough. For this fork, the browser runs locally on your box through Chrome CDP, so the host needs a working Chrome/Chromium path.

## The 30-second version

```bash
ssh root@your-box
curl -fsSL https://raw.githubusercontent.com/browser-use/bux/main/install.sh \
  | sudo bash
```

That's it. Skip to [first run](#first-run).

---

## Step by step

### 1. Get a box

Any of these work. Pick one you already use.

**VPS providers** (5 min, most portable)
- **Hetzner** — cheapest; CX11 (€4/mo, 2 vCPU / 2GB) is plenty. Falkenstein or Nuremberg for EU latency, Ashburn for US.
- **DigitalOcean** — $6/mo droplet, ubuntu 24.04 image.
- **Fly.io / Railway** — sized too small by default; bump to 2GB.
- **AWS EC2** — `t3.small` minimum. If you want auto-provisioning with one command, the [Browser Use Cloud managed version](https://cloud.browser-use.com) handles AMI baking + launch for you.

**Home lab** (0 min, no recurring cost)
- **Mac mini** with Ubuntu Asahi, or a Raspberry Pi 4/5. Expose via Tailscale (recommended) or Cloudflare Tunnel. No open ports to the internet needed.

**Existing server**
- If you already have a dev box, bux can share it — it adds a `bux` user and runs everything under `/opt/bux`. Installer is idempotent.

### 2. Make sure Chrome is available

This fork expects a local Chrome/Chromium browser path on the box, or a reachable CDP endpoint at `http://127.0.0.1:9222`.

Useful checks:

```bash
command -v google-chrome || command -v chromium || command -v chromium-browser
curl -s http://127.0.0.1:9222/json/version || true
```

**Telegram bot (optional)** — message [@BotFather](https://t.me/BotFather) on Telegram:

```
/newbot
<pick any name, e.g. "my-agent">
<pick any username ending in _bot, e.g. my_agent_bot>
```

BotFather replies with a token like `1234567890:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`. Save it.

### 3. Run the installer

```bash
ssh root@your-box

# Interactive (it'll ask for anything missing):
curl -fsSL https://raw.githubusercontent.com/browser-use/bux/main/install.sh | sudo bash

# Or one-shot with everything up front:
curl -fsSL https://raw.githubusercontent.com/browser-use/bux/main/install.sh \
  | sudo TG_BOT_TOKEN=123:abc BUX_CDP_URL=http://127.0.0.1:9222 bash
```

The script:
1. Installs Node.js 24 + Claude Code + ttyd + Python `browser-harness`
2. Creates a `bux` system user with its own venv
3. Drops the local Chrome browser-keeper + telegram-bot + systemd units
4. Installs [ztk](https://github.com/codejunkie99/ztk) (pinned) — compresses long Bash tool outputs before they hit Claude's context. Opt out with `WITH_ZTK=0`.
5. Starts everything

Takes ~2-3 minutes on a fresh box. Idempotent — safe to rerun after edits.

### 4. Sync your viberelay profile onto the box

This fork runs Claude through `viberelay run -d vibe -- ...`, so the box needs your working viberelay account state.

From a machine where `viberelay` already works for you, sync it onto the box:

```bash
viberelay sync bux@your-box
```

Then verify on the box:

```bash
ssh bux@your-box
viberelay accounts
viberelay run -d vibe -- --version
```

If you do not already use viberelay locally, set that up first on your laptop, then rerun the sync command.

### 5. First run

```bash
sudo -iu bux        # become the bux user
cd ~ && viberelay run -d vibe --
```

On first launch the wrapped Claude session should start under the `vibe` profile. If you synced successfully, it should already have working account access.

### 6. Bind the Telegram bot

If you passed `TG_BOT_TOKEN`, the installer printed a `t.me/<bot>` URL. Open it on your phone, send any message ("hi" works). **The first chat wins** — after you bind, the bot ignores everyone else forever.

Try it:

```
you: hi
bot: 🔒 This bot is now locked to this chat only.

you: /live
bot: ℹ️ local browser mode has no shareable live view; use the host machine's Chrome window

you: check my email, find unread from today, one-line summary each
bot: 🧠 on it…
bot: 3 unread from today:
     • Stripe: invoice for April usage ready
     • …
```

### 6. You're done

Every message is its own claude turn but **shares memory** with the previous ones. Follow-ups work:

```
you: check my email
bot: [summary]
you: reply to the stripe one saying pay it next week
bot: done, want to see the draft first?
```

## Troubleshooting

**`browser.env` isn't created / browser-keeper crashes**
```bash
sudo journalctl -u bux-browser-keeper -n 50
```
Most common causes: Chrome isn't installed, `BUX_CHROME_BIN` points to the wrong binary, or nothing is listening on `BUX_CDP_URL`. Edit `/etc/bux/env`, restart.

**TG bot silent after sending a message**
```bash
sudo journalctl -u bux-tg -n 50
```
- `dropping msg from chat_id=... (already bound)` → someone else's chat_id is bound. Wipe `/etc/bux/tg.env`, rerun install, bind again.
- `invalid bot token` → regenerate via @BotFather.

**claude errors on `--session-id` or `--resume`**
You have an older Claude Code version. Update:
```bash
sudo npm install -g @anthropic-ai/claude-code@latest
sudo systemctl restart bux-tg
```

**browser-harness says no CDP endpoint is set**
The browser-keeper hasn't written `~/.claude/browser.env` yet. Wait 10s on first boot, or:
```bash
sudo systemctl restart bux-browser-keeper
cat /home/bux/.claude/browser.env   # should have BU_CDP_URL=http://127.0.0.1:9222
```

**Need a clean slate**
```bash
sudo systemctl stop bux-tg bux-browser-keeper bux-ttyd
sudo rm -rf /etc/bux /opt/bux /home/bux/.claude /home/bux/.bux
sudo userdel -r bux
# rerun install.sh
```

## What's next

- [SKILL.md](SKILL.md) — how claude uses the browser (auto-loaded as `CLAUDE.md` context)
- [browser-harness](https://github.com/browser-use/browser-harness) — the CDP skill powering the browser
- [docs/recipes/](docs/recipes/) — provider-specific deploy notes
