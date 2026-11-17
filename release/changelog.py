"""Turn kit/CHANGELOG.md's "## Unreleased" into a dated release section.

changelog.py <cerea version> <pystino version> [extra.txt]
extra.txt (optional): extra sentences appended to the "To update" line.
"""
import datetime
import pathlib
import sys

v, p = sys.argv[1], sys.argv[2]
extra = ""
if len(sys.argv) > 3 and pathlib.Path(sys.argv[3]).is_file():
    extra = " " + pathlib.Path(sys.argv[3]).read_text().strip()
path = pathlib.Path("kit/CHANGELOG.md")
s = path.read_text()
old = "## Unreleased\n\n"
if s.count(old) == 0 and pathlib.Path(__file__).with_name("changelog-bullets.md").read_text().strip():
    # No Unreleased section on main: the bullets file supplies it, above the first release heading.
    first = s.index("\n## v") + 1
    s = s[:first] + old + s[first:]
assert s.count(old) == 1, "no single '## Unreleased' section"
# Optional extra bullets for this release (changelog-bullets.md next to this script), added at the
# top of the Unreleased list; the file is emptied by hand after the release.
bullets = pathlib.Path(__file__).with_name("changelog-bullets.md")
if bullets.is_file() and bullets.read_text().strip():
    s = s.replace(old, old + bullets.read_text().strip() + "\n", 1)
head = (
    f"## v{v} — {datetime.date.today().isoformat()}\n\n"
    f"Pins: Cerea `{v}` (chat and `cerea-documents`), Pystino `{p}`.\n"
    "**To update:** `cd ~/cerea/kit && git pull` (or `./get-kit.sh`), then\n"
    f"`docker compose pull && docker compose up -d`.{extra}\n\n"
)
path.write_text(s.replace(old, head, 1))
