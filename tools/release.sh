#!/usr/bin/env bash
# Usage: release.sh X.Y.Z <full commit sha>. Every step checked; stable moves only after E2E_OK.
V=$1; SHA=$2; T=v$V
cd /home/ubuntu/workspace/Cerea || exit 1
stop(){ echo "STOP: $*"; exit 1; }
sleep 30
for wf in ci.yml kit.yml; do
  id=""; for i in $(seq 1 20); do id=$(gh run list --workflow $wf --limit 10 --json databaseId,headSha -q "[.[]|select(.headSha==\"$SHA\")][0].databaseId"); [ -n "$id" ] && break; sleep 15; done
  [ -n "$id" ] || { echo "$wf: no run for this commit (path filter), skipping"; continue; }
  until s=$(gh run view $id --json status,conclusion -q '.status+" "+.conclusion' 2>/dev/null) && [[ $s == completed* ]]; do sleep 30; done
  echo "$wf $s"; [[ $s == *success ]] || stop "$wf failed"
done
git tag -a "$T" -m "$T" "$SHA" || stop "local tag"
ok=0; for i in 1 2 3 4 5; do git push -q origin "$T" 2>/dev/null && { ok=1; break; }; sleep 30; done
[ $ok = 1 ] || { gh api repos/paoloviviani/Cerea/git/refs -f ref=refs/tags/$T -f sha=$SHA >/dev/null && echo "tag created via API" || stop "tag push"; }
[ "$(git ls-remote origin "refs/tags/$T^{}" "refs/tags/$T" | head -1 | cut -c1-40)" != "" ] || stop "tag not on remote"
ok=0; for i in $(seq 1 10); do gh workflow run images.yml --ref "$T" 2>/dev/null && { ok=1; break; }; sleep 60; done
[ $ok = 1 ] || stop "images dispatch"
sleep 20
id=$(gh run list --workflow images.yml --limit 5 --json databaseId,headBranch -q "[.[]|select(.headBranch==\"$T\")][0].databaseId"); [ -n "$id" ] || stop "no images run"
until s=$(gh run view $id --json status,conclusion -q '.status+" "+.conclusion' 2>/dev/null) && [[ $s == completed* ]]; do sleep 30; done
echo "images $s"; [[ $s == *success ]] || stop "image build"
DOCKER_CONFIG=/tmp/anon-docker docker manifest inspect ghcr.io/paoloviviani/cerea:$V >/dev/null || stop "image not pullable"; echo "anonymous pull OK"
KIT_REF=$T CEREA_TAG=$V flock /tmp/heavy.lock /home/ubuntu/workspace/ai-stack/tools/fresh-e2e-kit.sh > /tmp/e2e-$V.log 2>&1
grep -E "checkout root|^chat |^gateway " /tmp/e2e-$V.log; grep -qx E2E_OK /tmp/e2e-$V.log || { tail -20 /tmp/e2e-$V.log; stop "fresh-kit test"; }
echo E2E_OK; echo "leftover containers: $(docker ps -aq --filter label=com.docker.compose.project=cerapub | wc -l)"
gh api -X PATCH repos/paoloviviani/Cerea/git/refs/heads/stable -f sha=$SHA >/dev/null || stop "stable"
[ "$(git ls-remote origin refs/heads/stable | cut -c1-40)" = "$SHA" ] || stop "stable not moved"
echo "stable -> $T"
