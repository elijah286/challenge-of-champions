# Versioning & release governance — LabVIEW CI

This is the single, authoritative policy for the version number the tooling shows and
**how and when to bump it.** It exists so that:

1. A consumer can **clearly tell when they need to update** to get the latest features.
2. Anyone can **see and confirm that an update is actually live** on the dashboard.
3. Every change that ships is recorded, tagged, and explainable.

> **Baseline:** the tooling is at **`1.0.0`** as of 2026‑06‑15. Everything currently in
> the repository is `1.0.0`. All future changes bump up from there.

---

## 1. The version is `A.B.C` (semantic, consumer‑facing)

The version is **not** an internal build counter. It answers one question for a consumer:
*"How urgently, and how carefully, do I need to update?"*

| Part | Name | Bump when… | What it tells a consumer |
|------|------|-----------|--------------------------|
| **A** | MAJOR | A change is **breaking** for a consumer — updating needs work beyond a normal `install --update`. | **Action required.** Read the notes before updating. |
| **B** | MINOR | A **new, backward‑compatible capability or feature** ships. | **New features available** — update to get them. |
| **C** | PATCH | A **backward‑compatible fix or refinement** ships (no new capability surface). | **Routine, safe update.** |

The number that matters most for *"a client needs the latest features"* is **B (MINOR)** —
a MINOR (or MAJOR) bump is the signal that there is something genuinely new to pull.

### What counts as MAJOR (A) — breaking

Bump **A** (and reset B and C to 0) when updating requires the consumer to do more than
re‑run the updater and commit. For example:

- A new **required** GitHub Actions variable or secret.
- A change to the **config schema** of `.github/labview-ci.yml` that existing configs must migrate.
- A **removed or renamed** capability, workflow, status context, or Pages route.
- A change to the **published Pages layout** that needs manual migration.
- Anything that would make an un‑migrated consumer's pipeline fail after updating.

### What counts as MINOR (B) — new feature

Bump **B** (and reset C to 0) for backward‑compatible additions:

- A new capability in `catalog.json` (a new workflow / check / report).
- A new dashboard column, panel, page, or a meaningful new behavior.
- A new optional variable or input that defaults safely.

### What counts as PATCH (C) — fix / refinement

Bump **C** for backward‑compatible changes that add no new capability surface:

- Bug fixes, report/formatting fixes, performance, reliability.
- Documentation, comments, internal refactors.
- Dependency / pinned‑version bumps that don't change behavior for consumers.

> When in doubt between two levels, pick the **higher** one. Under‑signalling an update is
> worse than over‑signalling it — a consumer who updates "for a feature" and gets a fix too
> is fine; a consumer who never learns a feature shipped is not.

---

## 2. The golden rule — every push bumps

**Any push to `main` that changes tooling files MUST bump the version by at least PATCH.**

"Tooling files" are the paths the CI enforcement watches:

```
.github/workflows/**
.github/labview/**
.github/labview-ci/**
.github/pages/**
.github/docker/**
```

(The repository's own LabVIEW source — `*.vi`, `*.lvproj`, … — is **not** tooling and does
not require a bump. Bumping `version` + adding the release note is itself the only change
that is exempt from "needs a bump," since it *is* the bump.)

This rule is enforced automatically — see [§5](#5-enforcement).

---

## 3. The source of truth

The version lives in exactly one place:

```
.github/labview-ci/catalog.json   →   "version": "A.B.C"
```

and the matching, human‑readable release note lives next to it:

```
.github/labview-ci/catalog.json   →   history.releases[0]
```

**Invariant:** `version` MUST equal `history.releases[0].version`. The newest release entry
always documents the current version. Everything else (dashboard badge, What's New dialog,
installer, configurator) reads from here — never hard‑code a version anywhere else.

---

## 4. How to bump (one command)

Use the helper; it keeps the invariant and writes the release note for you:

```bash
# From the repo root. Pick the level per §1.
python3 .github/labview-ci/bump-version.py minor \
  --title "Docs generation" \
  --summary "Adds an Antidoc-based documentation report to the dashboard." \
  --highlight "New 'Docs' column linking to generated project documentation." \
  --highlight "Documentation is regenerated on every push that changes VIs."
```

- `level` is `major`, `minor`, or `patch` (or `A` / `B` / `C`).
- `--title` / `--summary` / `--highlight` populate the release note. Highlights repeat.
- `--date` overrides the date (defaults to today, UTC).
- `--check` validates the invariant **without** changing anything (used by CI).

The helper edits **only** `catalog.json`: it raises `version` and prepends a
`history.releases` entry. Review with `git diff`, commit, and push.

### Recommended commit message

Tag the level in the commit so it's auditable at a glance:

```
feat(ci): docs generation report   [release: minor]
```

---

## 5. Enforcement

[`.github/workflows/version-guard.yml`](../workflows/version-guard.yml) makes the golden rule real:

- **On a pull request** that touches tooling paths: the guard **fails** unless
  `catalog.json`'s `version` is greater than the base branch's, and the invariant in
  [§3](#3-the-source-of-truth) holds. The failure message tells you to run `bump-version.py`.
- **On push to `main`:**
  - If `version` increased vs the previous commit, the guard **creates the annotated tag
    `v<version>` and a matching GitHub Release** from the release note. This is what lets a
    consumer pin an update to a specific version, and it is the permanent record that the
    release shipped.
  - If tooling changed but `version` did **not** increase, the guard posts a **warning**
    (it cannot block a commit that is already on `main`) so the miss is visible and can be
    corrected by the next bump.

The guard never rewrites history or auto‑commits to `main` — bumping is a deliberate,
reviewable act, which keeps it safe even while several changes are in flight at once.

---

## 6. How a consumer learns they need to update

The dashboard is the delivery surface:

- A **version badge** in the dashboard toolbar shows the tooling version the repository runs.
- On a **consumer** repository (one whose `catalog.source` points at a *different* source
  repo), the badge live‑checks the source repo's `catalog.json`. If the source is ahead, the
  badge lights up with an update dot and opens the **What's New** dialog
  ([`whats-new.html`](../pages/whats-new.html)), which lists every release the consumer does
  not yet have and prints the exact `install … --update` command — pinned to the version they
  pick.

Because the update signal is driven entirely by the version number, **bumping correctly is
the whole mechanism.** A MINOR/MAJOR bump is how a consumer finds out a feature is waiting.

---

## 7. How to confirm an update is live on the page

The dashboard shows a **liveness line** under the title:

```
LabVIEW CI v1.0.0 · deployed 2026-06-15 14:32 UTC · a1b2c3d
```

- the **version** is baked from `catalog.json` at build time,
- the **deployed** timestamp is when the page was generated,
- the short **commit** is the source commit the page was built from.

After you push a bump, watch the dashboard: when the version, timestamp, and commit change to
your new values, the update is confirmed live. (On the source repo's own dashboard the badge
also reflects the new version, since the source always runs the latest.)

---

## 8. Quick checklist for shipping a change

1. Make the change under a tooling path.
2. Decide the level with [§1](#1-the-version-is-abc-semantic-consumer-facing) (prefer the higher one when unsure).
3. `python3 .github/labview-ci/bump-version.py <level> --title … --summary … --highlight …`
4. `git diff` → commit (tag the level in the message) → push.
5. The guard tags `v<version>` + cuts a Release; the dashboard redeploys with the new version.
6. Confirm the liveness line shows your new version/commit.
