#!/usr/bin/env bash
# Start the paseo daemon (loopback-only inside this container), wait for
# health, then publish the pairing offer to the shared volume. The offer is
# the trust anchor: in production the user would scan the QR into the chat.
set -euo pipefail

# The LLM leg uses the box's existing opencode provider credential (a
# stand-in for the /v1 serve shim, which belongs to the enrollment axis).
# Mounted read-only at /mnt and copied into place so the daemon's opencode
# can read it without a root-owned directory appearing inside $HOME.
if [ -f /mnt/opencode-auth.json ]; then
  mkdir -p "$HOME/.local/share/opencode"
  cp /mnt/opencode-auth.json "$HOME/.local/share/opencode/auth.json"
fi

# Permission policy lives in the user machine's opencode config: opencode's
# prompt API carries no per-request permission field, so `edit`/`bash` asks
# are configured globally here — in production this is the installer's job
# (mount scoping and posture, see ADR 0085's open-question answers).
mkdir -p "$HOME/.config/opencode"
cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "edit": "ask",
    "bash": "ask"
  }
}
JSON

entry="$(cat /etc/paseo-server-entry)"
node "$entry" &
DAEMON_PID=$!
trap 'kill "$DAEMON_PID" 2>/dev/null || true' TERM INT

echo "[userbox] waiting for daemon health on 127.0.0.1:6767"
for _ in $(seq 1 90); do
  if node -e "require('http').get({hostname:'127.0.0.1',port:6767,path:'/api/health'},r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))" 2>/dev/null; then
    break
  fi
  sleep 1
done

echo "[userbox] daemon healthy; generating pairing offer"
# The pair RPC is a short-timeout call against a busy daemon; retry until it
# lands rather than racing the daemon's first-minute work.
ok=""
for _ in $(seq 1 15); do
  if paseo daemon pair --json | tee /offer/offer.json; then
    ok=1
    break
  fi
  echo "[userbox] pair attempt failed; retrying"
  sleep 3
done
[ -n "$ok" ] || { echo "[userbox] pairing never succeeded"; exit 1; }

echo "[userbox] warming the opencode provider so the first agent create is not a cold boot"
for _ in $(seq 1 10); do
  if paseo provider models opencode >/dev/null 2>&1; then
    echo "[userbox] opencode provider warm"
    break
  fi
  sleep 5
done

echo "[userbox] daemon pid $DAEMON_PID; keeping container alive"
wait "$DAEMON_PID"
