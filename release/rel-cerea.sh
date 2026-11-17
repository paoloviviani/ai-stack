#!/usr/bin/env bash
# Cerea release: rel-cerea.sh <cerea version> <pystino version to pin>
# Run from anywhere. Needs a Cerea-wt-merge worktree (created if missing), gh, npm, python3.
# Gate first (AGENTS.md / ci-first-checks): `gh workflow run ci.yml --ref main -f full=true` green on main.
# The changelog: kit/CHANGELOG.md's "## Unreleased" becomes "## vX — date" with Pins/To update lines;
# edit release/changelog-extra.txt (optional) for extra "To update" sentences before running.
set -euo pipefail
export PATH="$HOME/.local/opt/node/bin:$PATH"
# The live stack holds 80/443 on this box: the fresh-kit test runs beside it on free ports.
export HTTP_PORT=${HTTP_PORT:-8180} HTTPS_PORT=${HTTPS_PORT:-8543} GATEWAY_PORT=${GATEWAY_PORT:-8100}
V=${1:?cerea version}; P=${2:?pystino version}
WS=${WORKSPACE:-$HOME/workspace}
W=$WS/Cerea-wt-merge
export TMPDIR=${TMPDIR:-/var/tmp/cerel-tmp}; mkdir -p "$TMPDIR"
cd "$WS/Cerea"
git fetch -q origin
[ -d "$W" ] || git worktree add -q --detach "$W" origin/main
cd "$W"
git checkout -q --detach origin/main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
npm version "$V" --no-git-tag-version >/dev/null
kit/tools/pin --cerea "$V" --pystino "$P"
kit/tools/pin --check
sed -i "s/^PYSTINO_CONTRACT_VERSION=.*/PYSTINO_CONTRACT_VERSION=$P/" deploy/ci/pystino-contract.env
grep -q "^PYSTINO_CONTRACT_VERSION=$P$" deploy/ci/pystino-contract.env
python3 "$(dirname "$0")/changelog.py" "$V" "$P" "$(dirname "$0")/changelog-extra.txt"
(cd kit && python3 -m unittest discover -s tests -q)
git diff --stat
git commit -qam "Release v$V"
git push -q origin HEAD:main
gh workflow run contract.yml --ref main; sleep 15
cid=$(gh run list --workflow contract.yml --branch main -L1 --json databaseId -q ".[0].databaseId")
until [ "$(gh run view "$cid" --json status -q .status)" = completed ]; do sleep 30; done
[ "$(gh run view "$cid" --json conclusion -q .conclusion)" = success ] || { echo "contract $P FAILED"; exit 1; }
echo "contract $P OK"
scripts/release/release.sh "$V"
# If release.sh STOPs at "image build" after the tag: see memory note cerea-release-resume
# (publish only the missing image, then run release.sh's steps 4-6 with resume-steps.sh).
