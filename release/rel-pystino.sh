#!/usr/bin/env bash
# Pystino release: rel-pystino.sh <new version> <previous version> <paired released cerea version>
# Follows Pystino AGENTS.md "Releasing Pystino". Run the live checks first for request-path/money/SQL changes.
set -euo pipefail
V=${1:?new}; PREV=${2:?previous}; C=${3:?cerea}
WS=${WORKSPACE:-$HOME/workspace}; W=$WS/Pystino-wt-rel
export TMPDIR=${TMPDIR:-/var/tmp/pyrel-tmp}; mkdir -p "$TMPDIR"
export UV_PYTHON=${UV_PYTHON:-3.13}  # google-re2 has no wheel for newer Pythons; a source build needs c++
cd "$WS/Pystino"; git fetch -q origin
git worktree add -q --detach "$W" origin/main; cd "$W"
wait_run(){ local id=$1; until [ "$(gh run view "$id" --json status -q .status)" = completed ]; do sleep 30; done; local c; c=$(gh run view "$id" --json conclusion -q .conclusion); echo "run $id $c"; [ "$c" = success ]; }
latest(){ sleep 12; gh run list --workflow "$1" ${2:+--branch "$2"} -L1 --json databaseId -q '.[0].databaseId'; }
echo "== main CI green"; id=$(gh run list --workflow ci.yml --branch main -L1 --json databaseId -q ".[0].databaseId"); wait_run "$id"
echo "== release commit"
sed -i "s/^version = \"$PREV\"/version = \"$V\"/" apps/gateway/pyproject.toml
grep -q "^version = \"$V\"" apps/gateway/pyproject.toml
uv lock -q
sed -i "s/PYSTINO_VERSION:-$PREV}/PYSTINO_VERSION:-$V}/g" deploy/compose.yaml
[ "$(grep -c "PYSTINO_VERSION:-$V}" deploy/compose.yaml)" = 2 ]
sed -i "s/^PYSTINO_VERSION=.*/PYSTINO_VERSION=$V/; s/^CEREA_VERSION=.*/CEREA_VERSION=$C/; /^CEREA_IMAGE=/d" deploy/release.env
uv run -q --package gateway pystino release-pin
uv run -q --package gateway pystino release-pin --check
grep "^CEREA_IMAGE=.*cerea:$C@sha256:" deploy/release.env
uv run -q pytest apps/gateway/tests/test_deploy_pystino_only.py apps/gateway/tests/test_deploy_release.py -q
# CHANGELOG.md: "## Unreleased" becomes this release's section; refuse an empty one.
python3 - "$V" "$C" <<'PY'
import datetime, pathlib, re, sys
v, c = sys.argv[1], sys.argv[2]
p = pathlib.Path("CHANGELOG.md"); s = p.read_text()
m = re.search(r"^## Unreleased\n(.*?)(?=^## v)", s, re.M | re.S)
assert m, "CHANGELOG.md has no '## Unreleased' section above the last release"
assert m.group(1).strip(), "CHANGELOG.md '## Unreleased' is empty: write the release notes first"
head = f"## Unreleased\n\n## v{v} — {datetime.date.today().isoformat()}\n\nPaired with Cerea {c}.\n\n"
p.write_text(s[: m.start()] + head + m.group(1).lstrip("\n") + s[m.end():])
PY
changed=$(git diff --name-only | sort | tr '\n' ' '); echo "changed: $changed"
[ "$changed" = "CHANGELOG.md apps/gateway/pyproject.toml deploy/compose.yaml deploy/release.env uv.lock " ]
git commit -qam "release: Pystino $V, paired with Cerea $C"
git push -q origin HEAD:main
id=$(latest ci.yml main); wait_run "$id"
echo "== tag"; git tag -a "v$V" -m "v$V"; git push -q origin "v$V"
echo "== images"; gh workflow run images.yml --ref "v$V"; id=$(latest images.yml); wait_run "$id"
echo "== anonymous pull"; anon=$(mktemp -d); echo '{}' > "$anon/config.json"
DOCKER_CONFIG=$anon docker manifest inspect "ghcr.io/paoloviviani/pystino-gateway:$V" >/dev/null && echo gateway OK
DOCKER_CONFIG=$anon docker manifest inspect "ghcr.io/paoloviviani/pystino-redaction:$V-pattern" >/dev/null && echo redaction OK
rm -rf "$anon"
echo "== stack on tag"; id=$(gh run list --workflow stack.yml --branch "v$V" -L1 --json databaseId -q '.[0].databaseId'); wait_run "$id"
echo "== GitHub release"
notes="$TMPDIR/pystino-v$V-notes.md"
awk -v h="## v$V " 'index($0,h)==1{on=1;next} on&&/^## v/{exit} on' CHANGELOG.md > "$notes"
[ -s "$notes" ] || { echo "no CHANGELOG.md section for v$V"; exit 1; }
gh release create "v$V" --verify-tag --title "v$V" --notes-file "$notes" --latest
[ "$(gh release view "v$V" --json tagName -q .tagName)" = "v$V" ]
cd "$WS/Pystino"; git worktree remove "$W"; git pull -q --ff-only
echo "PYSTINO_RELEASED v$V"
