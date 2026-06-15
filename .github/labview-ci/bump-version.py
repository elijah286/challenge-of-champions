#!/usr/bin/env python3
"""
bump-version.py - the one supported way to change the LabVIEW CI tooling version.

Governance for *when* to use major/minor/patch lives in VERSIONING.md (next to this
file). This helper enforces the mechanics so the version stays consistent:

  * raises catalog.json's top-level "version" by the requested level, and
  * prepends a matching history.releases[] entry (the release note),

keeping the invariant  version == history.releases[0].version.

Usage
-----
  python3 .github/labview-ci/bump-version.py <level> [options]

  level            major | minor | patch   (aliases: A | B | C)

  --title T        Release title           (default: "LabVIEW CI <new-version>")
  --summary S      One-line summary of the release
  --highlight H    A bullet for the notes  (repeatable)
  --date D         Release date YYYY-MM-DD  (default: today, UTC)
  --catalog PATH   catalog.json to edit     (default: alongside this script)
  --check          Validate the invariant and exit; change nothing
  --print-version  Print the current version and exit

Exit code is non-zero on any error or failed --check, so CI can gate on it.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path

LEVELS = {"major": 0, "minor": 1, "patch": 2, "a": 0, "b": 1, "c": 2}
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
DEFAULT_CATALOG = Path(__file__).resolve().parent / "catalog.json"


def die(msg: str) -> "None":
    print(f"bump-version: error: {msg}", file=sys.stderr)
    raise SystemExit(2)


def load_catalog(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"catalog not found: {path}")
    except json.JSONDecodeError as exc:
        die(f"catalog.json is not valid JSON: {exc}")


def parse_version(v: str) -> tuple[int, int, int]:
    if not isinstance(v, str) or not SEMVER.match(v):
        die(f"version must be A.B.C with integer parts, got: {v!r}")
    a, b, c = (int(p) for p in v.split("."))
    return a, b, c


def bumped(version: str, level: str) -> str:
    a, b, c = parse_version(version)
    idx = LEVELS[level]
    if idx == 0:
        a, b, c = a + 1, 0, 0
    elif idx == 1:
        a, b, c = a, b + 1, 0
    else:
        a, b, c = a, b, c + 1
    return f"{a}.{b}.{c}"


def releases_list(cat: dict) -> list:
    hist = cat.get("history") or {}
    if isinstance(hist, list):
        return hist
    return hist.get("releases") or []


def validate(cat: dict, path: Path) -> None:
    """Enforce: version is valid semver and equals releases[0].version."""
    version = cat.get("version")
    parse_version(version if isinstance(version, str) else "")
    rels = releases_list(cat)
    if not rels:
        die("history.releases is empty; the current version needs a release note")
    top = rels[0].get("version") if isinstance(rels[0], dict) else None
    if top != version:
        die(
            "invariant broken: catalog version "
            f"{version!r} != history.releases[0].version {top!r}. "
            "The newest release entry must document the current version."
        )
    print(f"OK: {path} version {version} is consistent with its release note.")


def render_entry(entry: dict, base_indent: int, had_existing: bool) -> str:
    """Render one release note as text matching the file's existing indentation.

    base_indent is the indent of the `"releases":` line; the entry object sits two
    spaces deeper, its fields four, and highlight items six. A trailing comma is
    added only when an existing entry follows.
    """
    ind = " " * base_indent
    o = ind + "  "   # object brace
    f = ind + "    "  # field
    h = ind + "      "  # highlight item
    lines = [o + "{"]
    lines.append(f + '"version": ' + json.dumps(entry["version"]) + ",")
    lines.append(f + '"date": ' + json.dumps(entry["date"]) + ",")
    tail = "," if ("summary" in entry or "highlights" in entry) else ""
    lines.append(f + '"title": ' + json.dumps(entry["title"]) + tail)
    if "summary" in entry:
        sc = "," if "highlights" in entry else ""
        lines.append(f + '"summary": ' + json.dumps(entry["summary"]) + sc)
    if "highlights" in entry:
        lines.append(f + '"highlights": [')
        n = len(entry["highlights"])
        for i, hl in enumerate(entry["highlights"]):
            lines.append(h + json.dumps(hl) + ("," if i < n - 1 else ""))
        lines.append(f + "]")
    lines.append(o + ("}," if had_existing else "}"))
    return "\n".join(lines)


def apply_bump(text: str, old_version: str, new_version: str,
               entry: dict, had_existing: bool) -> str:
    """Surgically edit the catalog TEXT: bump the top-level version and insert the
    new release entry, leaving every other byte (single-line arrays, blank lines,
    comments) untouched so the diff stays reviewable."""
    pat = re.compile(r'("version"\s*:\s*")' + re.escape(old_version) + r'(")')
    text2, n = pat.subn(r"\g<1>" + new_version + r"\g<2>", text, count=1)
    if n == 0:
        die("could not locate the top-level version string to update")
    m = re.search(r'\n([ \t]*)"releases"\s*:\s*\[[ \t]*\n', text2)
    if not m:
        die('could not locate "releases": [ to insert the release note')
    base_indent = len(m.group(1))
    entry_text = render_entry(entry, base_indent, had_existing)
    at = m.end()
    return text2[:at] + entry_text + "\n" + text2[at:]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        prog="bump-version.py",
        description="Bump the LabVIEW CI tooling version (see VERSIONING.md).",
    )
    ap.add_argument("level", nargs="?", help="major | minor | patch (A | B | C)")
    ap.add_argument("--title", default="")
    ap.add_argument("--summary", default="")
    ap.add_argument("--highlight", action="append", default=[], dest="highlights")
    ap.add_argument("--date", default="")
    ap.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    ap.add_argument("--check", action="store_true", help="validate invariant, change nothing")
    ap.add_argument("--print-version", action="store_true")
    args = ap.parse_args(argv)

    path = Path(args.catalog)
    cat = load_catalog(path)

    if args.print_version:
        print(cat.get("version", ""))
        return 0

    if args.check:
        validate(cat, path)
        return 0

    if not args.level:
        die("a level is required: major | minor | patch (or --check / --print-version)")
    level = args.level.lower()
    if level not in LEVELS:
        die(f"unknown level {args.level!r}; use major | minor | patch (A | B | C)")

    current = cat.get("version")
    new_version = bumped(current if isinstance(current, str) else "", level)
    date = args.date or _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%d")
    if args.date and not re.match(r"^\d{4}-\d{2}-\d{2}$", args.date):
        die(f"--date must be YYYY-MM-DD, got {args.date!r}")

    entry: dict = {
        "version": new_version,
        "date": date,
        "title": args.title or f"LabVIEW CI {new_version}",
    }
    if args.summary:
        entry["summary"] = args.summary
    if args.highlights:
        entry["highlights"] = list(args.highlights)

    # Surgical text edit (keeps the rest of the file byte-for-byte), then re-parse
    # to prove the result is valid JSON and still satisfies the invariant.
    had_existing = len(releases_list(cat)) > 0
    old_text = path.read_text(encoding="utf-8")
    new_text = apply_bump(old_text, current, new_version, entry, had_existing)
    try:
        result = json.loads(new_text)
    except json.JSONDecodeError as exc:
        die(f"internal error: bump produced invalid JSON ({exc}); nothing written")
    if result.get("version") != new_version:
        die("internal error: version not updated as expected; nothing written")
    validate(result, path)  # fail loudly if we somehow broke the invariant
    path.write_text(new_text, encoding="utf-8")

    print(f"Bumped {current} -> {new_version} ({level}).")
    print(f"Added release note: {entry['title']}")
    print("Review with `git diff`, then commit and push. The version guard will tag "
          f"v{new_version} on main.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
