#!/usr/bin/env python3
"""
build-gallery.py — Build manifest.json and commits.json for the VI Browser.

Usage:
    python3 build-gallery.py \
        --snapshot-dir  path/to/vi-snapshots/COMMIT_SHA \
        --workspace-dir path/to/repo-root \
        --commit-sha    abc1234 \
        --commit-msg    "commit message" \
        --author        "Author Name" \
        --output-dir    path/to/output

Outputs:
    manifest.json  — list of all exported VI HTML files with project-tree metadata
    commits.json   — updated rolling list of commits that have snapshots (for the VI Browser)
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree as ET


# ---------------------------------------------------------------------------
# Parse .lvproj to extract project tree structure
# ---------------------------------------------------------------------------

def parse_lvproj(lvproj_path: Path) -> dict[str, list[str]]:
    """
    Returns a dict mapping library/class name → list of VI relative paths.
    """
    tree: dict[str, list[str]] = {}
    try:
        root = ET.parse(lvproj_path).getroot()
        # Flatten all Item elements that reference .vi or .ctl files
        for item in root.iter('Item'):
            url  = item.get('URL', '')
            name = item.get('Name', '')
            if not url.endswith(('.vi', '.ctl')):
                continue
            # Convert URL to a normalized relative path
            rel = url.lstrip('./ \\').replace('/', os.sep).replace('\\', os.sep)
            # Group by nearest containing library/class ancestor
            group = _find_group(item)
            tree.setdefault(group, []).append(rel)
    except Exception as e:
        print(f"Warning: could not parse {lvproj_path}: {e}", file=sys.stderr)
    return tree


def _find_group(element) -> str:
    """Walk up to find the nearest lvlib/lvclass parent item name."""
    # ElementTree doesn't expose parent references natively;
    # we rely on the Name attribute heuristic
    name = element.get('Name', '')
    if name.endswith(('.lvlib', '.lvclass')):
        return name
    return 'Project'


# ---------------------------------------------------------------------------
# Build manifest
# ---------------------------------------------------------------------------

def build_manifest(
    snapshot_dir: Path,
    workspace_dir: Path,
    commit_sha: str,
) -> list[dict]:
    """
    Walk snapshot_dir for .html files and enrich with project-tree info.
    """
    # Build project tree index from all .lvproj files
    project_tree: dict[str, list[str]] = {}
    for lvproj in workspace_dir.rglob('*.lvproj'):
        project_tree.update(parse_lvproj(lvproj))

    # Invert: vi_rel_path → group
    vi_to_group: dict[str, str] = {}
    for group, vis in project_tree.items():
        for vi in vis:
            vi_to_group[vi.lower()] = group

    entries = []
    for html_file in sorted(snapshot_dir.rglob('*.html')):
        rel_html = html_file.relative_to(snapshot_dir)
        # Reverse safe-name encoding: dashes back to path separators
        # The safe name is <rel_path_with_slashes_replaced_by_dashes>.html
        vi_rel_guess = str(rel_html).replace('-', os.sep).removesuffix('.html')
        group = vi_to_group.get(vi_rel_guess.lower(), 'Unknown')
        vi_name = html_file.stem.split('-')[-1] if '-' in html_file.stem else html_file.stem
        entries.append({
            'html':       str(rel_html).replace(os.sep, '/'),
            'vi_name':    vi_name,
            'group':      group,
            'vi_rel':     vi_rel_guess.replace(os.sep, '/'),
            'commit_sha': commit_sha,
        })

    return entries


# ---------------------------------------------------------------------------
# Rolling commits.json
# ---------------------------------------------------------------------------

def update_commits_json(
    commits_file: Path,
    commit_sha: str,
    commit_msg: str,
    author: str,
    vi_count: int,
) -> list[dict]:
    existing: list[dict] = []
    if commits_file.exists():
        try:
            existing = json.loads(commits_file.read_text(encoding='utf-8-sig'))
        except Exception:
            existing = []

    # Remove duplicate entry for same SHA
    existing = [c for c in existing if c.get('sha') != commit_sha]

    new_entry = {
        'sha':      commit_sha,
        'short':    commit_sha[:7],
        'message':  commit_msg[:120],
        'author':   author,
        'date':     datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'vi_count': vi_count,
    }
    existing.insert(0, new_entry)
    return existing[:200]  # keep last 200 commits


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description='Build VI Browser gallery manifest.')
    parser.add_argument('--snapshot-dir',  required=True, help='Dir with exported .html VI snapshots')
    parser.add_argument('--workspace-dir', required=True, help='Repo root (for .lvproj parsing)')
    parser.add_argument('--commit-sha',    required=True)
    parser.add_argument('--commit-msg',    default='')
    parser.add_argument('--author',        default='')
    parser.add_argument('--output-dir',    required=True, help='Dir to write manifest.json / commits.json')
    args = parser.parse_args()

    snap_dir      = Path(args.snapshot_dir)
    workspace_dir = Path(args.workspace_dir)
    output_dir    = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Building manifest for commit {args.commit_sha[:7]}...")
    manifest = build_manifest(snap_dir, workspace_dir, args.commit_sha)
    print(f"  {len(manifest)} VI snapshots found")

    manifest_file = output_dir / 'manifest.json'
    manifest_file.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )
    print(f"  manifest.json → {manifest_file}")

    commits_file = output_dir / 'commits.json'
    commits = update_commits_json(
        commits_file,
        args.commit_sha,
        args.commit_msg,
        args.author,
        len(manifest),
    )
    commits_file.write_text(
        json.dumps(commits, indent=2, ensure_ascii=False),
        encoding='utf-8',
    )
    print(f"  commits.json  → {commits_file} ({len(commits)} entries)")


if __name__ == '__main__':
    main()
