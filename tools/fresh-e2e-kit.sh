#!/usr/bin/env bash
set -euo pipefail
# Each release pulls ~3 GB; drop older release images first so the disk does not fill.
docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "paoloviviani/(cerea|pystino)" | xargs -r docker rmi >/dev/null 2>&1 || true
KIT=/home/ubuntu/scratch-pub/kit
IP=$(hostname -I | awk '{print $1}')
df -h / | tail -1
rm -rf /home/ubuntu/scratch-pub
mkdir -p /home/ubuntu/scratch-pub
curl -fsSL "https://raw.githubusercontent.com/paoloviviani/Cerea/${KIT_REF:?}/kit/get-kit.sh" | sh -s -- --version "${KIT_REF}" --dir /home/ubuntu/scratch-pub/checkout >/tmp/get-kit.log 2>&1 || { cat /tmp/get-kit.log; exit 1; }
KIT=/home/ubuntu/scratch-pub/checkout/kit
ls -A /home/ubuntu/scratch-pub/checkout | tr "\n" " "; echo "(checkout root)"
test ! -e "$KIT/.env"
cd "$KIT"
./configure --non-interactive --origin "https://$IP" --admin-email admin@example.org --preset homelab --tls internal --idp authelia --agents --terminal --project cerapub > /tmp/fresh-configure.log 2>&1
mkdir -p /tmp/anon-docker
echo '{}' > /tmp/anon-docker/config.json
export DOCKER_CONFIG=/tmp/anon-docker
grep -q "^CODE_TERMINAL_ENABLED='true'" .env
docker compose pull -q
docker compose up -d --wait
docker compose ps --format '{{.Service}} {{.Image}} {{.Status}}'
docker compose ps --format '{{.Image}}' | grep -q "cerea:${CEREA_TAG:?}"
docker compose ps --format '{{.Image}}' | grep -q 'pystino-gateway:0.3.2'
docker compose ps --format '{{.Service}}' | grep -qx extractor
docker compose exec -T chat printenv CODE_TERMINAL_ENABLED | grep -qx true
sed "s#/opt/cerea#$KIT#; s#/home/ubuntu/scratch/tempuser#/home/ubuntu/scratch-pub/tempuser#g" /home/ubuntu/scratch/tempuser.sh > /home/ubuntu/scratch-pub/tempuser.sh
chmod +x /home/ubuntu/scratch-pub/tempuser.sh
TEMP_USER=pubcheck /home/ubuntu/scratch-pub/tempuser.sh create
PW=$(cat /home/ubuntu/scratch-pub/tempuser.pw)
cd /home/ubuntu/scratch
LOGIN_USER=pubcheck LOGIN_EMAIL=pubcheck@cerea.example.org EXPECT_ADMIN=false uv run --quiet --with httpx python signin_check.py "$KIT" "$PW" --chat 2>&1 | tail -3
cd "$KIT"
docker compose down -v
cd /
rm -rf /home/ubuntu/scratch-pub /tmp/fresh-configure.log
