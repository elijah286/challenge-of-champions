#!/usr/bin/env bash
# .github/labview/publish-pages.sh
# Race-safe publish of a directory into the gh-pages branch.
#
# WHY THIS EXISTS
#   Every CI capability (mass compile, VI Analyzer, VIDiff, VI snapshots, ...) used
#   to publish via peaceiris/actions-gh-pages, which clones -> commits -> pushes the
#   gh-pages branch. Two jobs pushing at once make the loser bounce with
#   "! [rejected] (fetch first)", so its report never deploys (dashboard 404). The
#   old workaround was a shared `report-pages-deploy` concurrency group that
#   serialized the whole job — which also serialized the expensive container compute
#   and, because a GitHub concurrency group keeps only one running + one pending run
#   (extra pending runs are cancelled), could silently drop reports under fan-out.
#
#   This script instead makes the *publish* concurrency-safe so the compute can run
#   fully in parallel across revisions: it commits into a per-revision subpath and
#   pushes with a fetch-rebase-retry loop. Because every writer targets a DISJOINT
#   by-SHA / by-blob destination, re-applying onto another writer's push never
#   conflicts. A sparse checkout materializes only the destination subtree, which
#   also sidesteps Windows MAX_PATH on the (large, deeply nested) gh-pages tree.
#
# USAGE (env in):
#   PP_SRC       local dir whose CONTENTS are copied into the destination (required)
#   PP_DEST      target subpath inside gh-pages, e.g. vi-analyzer/<sha> (required; never ".")
#   PP_REMOTE    authenticated git remote URL for this repo (required)
#   PP_MSG       commit message (default: "Deploy to gh-pages")
#   PP_ATTEMPTS  max push attempts (default: 10)
#
# NOTE: keep this POSIX-bash friendly (no associative arrays / ${var,,}) so it runs
# identically on ubuntu bash and the Windows runners' Git Bash.
set -uo pipefail

src="${PP_SRC:?PP_SRC required}"
dest="${PP_DEST:?PP_DEST required}"
remote="${PP_REMOTE:?PP_REMOTE required}"
msg="${PP_MSG:-Deploy to gh-pages}"
attempts="${PP_ATTEMPTS:-10}"

# Normalize destination: strip leading "./" and trailing "/"; forbid root/absolute.
dest="${dest#./}"; dest="${dest%/}"
case "$dest" in
  ""|".") echo "::error::PP_DEST must be a non-root subpath"; exit 1 ;;
  /*)     echo "::error::PP_DEST must be relative, got: $dest"; exit 1 ;;
esac
if [ ! -d "$src" ]; then echo "::error::PP_SRC not found: $src"; exit 1; fi

# Absolute source so it survives the cd into the work tree.
case "$src" in
  /*)    abssrc="$src" ;;
  [A-Za-z]:*) abssrc="$src" ;;   # Windows drive-absolute (Git Bash)
  *)     abssrc="$PWD/$src" ;;
esac

work="$(mktemp -d)"
git config --global core.longpaths true >/dev/null 2>&1 || true

# Clone gh-pages WITHOUT a full checkout (fast; avoids MAX_PATH on a huge tree).
if ! git clone --no-checkout --depth=1 --single-branch --branch gh-pages "$remote" "$work" 2>/dev/null; then
  echo "gh-pages branch not found; creating it."
  git clone --no-checkout --depth=1 "$remote" "$work" || { echo "::error::clone failed"; exit 1; }
  ( cd "$work" && git checkout --orphan gh-pages && git reset --hard ) || true
fi

cd "$work" || { echo "::error::cannot enter work tree"; exit 1; }
git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Materialize ONLY the destination subtree (everything else stays skip-worktree and
# is preserved in commits — i.e. keep_files:true semantics, for free).
git sparse-checkout set "$dest" >/dev/null 2>&1 || git sparse-checkout set --cone "$dest"
git checkout gh-pages >/dev/null 2>&1 || git checkout -b gh-pages

published=0
i=1
while [ "$i" -le "$attempts" ]; do
  mkdir -p "$dest"
  cp -R "$abssrc/." "$dest/" || { echo "::error::copy failed"; exit 1; }
  git add -A "$dest"
  if git diff --cached --quiet; then
    echo "Nothing to publish for $dest (already current)."
    published=1; break
  fi
  git commit -q -m "$msg"
  if git push origin gh-pages >"$work/.push.log" 2>&1; then
    echo "Published $dest (attempt $i)."
    published=1; break
  fi
  echo "Push rejected for $dest (attempt $i); reconciling with remote tip:"
  sed 's/^/    /' "$work/.push.log" 2>/dev/null || true
  # Drop our commit, fast-forward to the latest remote tip, retry. Disjoint
  # destination paths guarantee a conflict-free re-apply.
  git fetch --depth=1 origin gh-pages >/dev/null 2>&1 || true
  git reset --hard FETCH_HEAD >/dev/null 2>&1 || true
  git sparse-checkout reapply >/dev/null 2>&1 || true
  sleep "$(( (RANDOM % 3) + i ))"
  i=$(( i + 1 ))
done

cd /
rm -rf "$work"
if [ "$published" != 1 ]; then
  echo "::error::Failed to publish $dest after $attempts attempts."
  exit 1
fi
