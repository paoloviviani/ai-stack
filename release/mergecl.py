"""Resolve git conflict markers in kit/CHANGELOG.md by keeping both sides
(the other side's entries first, then ours). Run from the repo root."""
import pathlib

p = pathlib.Path("kit/CHANGELOG.md")
s = p.read_text()
while "<<<<<<< " in s:
    a = s.index("<<<<<<< ")
    b = s.index("=======\n", a)
    c = s.index(">>>>>>> ", b)
    cend = s.index("\n", c) + 1
    ours = s[s.index("\n", a) + 1 : b]
    theirs = s[b + 8 : c]
    s = s[:a] + theirs.rstrip("\n") + "\n" + ours + s[cend:]
p.write_text(s)
