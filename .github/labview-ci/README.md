# LabVIEW CI — portable CI/CD for any LabVIEW repository

This folder makes a set of LabVIEW CI/CD capabilities **portable** so they can be
installed into any LabVIEW repository — from the command line or from the
**"Integrate this CI pipeline"** button on the CI dashboard.

| Capability | What it does | OS |
|---|---|---|
| **Dashboard** | GitHub Pages dashboard aggregating every commit's CI status + the configurator | Linux runner |
| **Mass Compile** | Compiles every VI to catch broken/mutated code; reports % compiled | Windows |
| **VI Analyzer** | Runs the VI Analyzer test suite; native + friendly report | Windows / Linux |
| **VIDiff** | Side-by-side visual diff reports per changed VI; PR comments | Windows / Linux |
| **VI Snapshots** | Browseable gallery of every VI's block diagram (the VI Browser) | Windows |
| **Shared image** | Builds the LabVIEW CI container image to GHCR | Windows / Linux |
| **Unit Tests** | *Planned* — placeholder showing how new capabilities slot in | Windows / Linux |

Everything is driven by [`catalog.json`](catalog.json) — a single capability
registry that **both** the configurator UI and the installer read. Adding a new
capability is a one-entry change (see [Adding a capability](#adding-a-capability)).

## How it fits together

```
catalog.json ──────┬──────────────► integrate.html  (the dashboard configurator UI)
 (capability        │                  • pick version / OS / activities
  registry,         │                  • emits an install command + a downloadable bundle
  single source)    │
                    └──────────────► install.py      (the installer brain)
                                       • copies the selected capabilities' files
                                       • rebrands cosmetic strings for the target repo
                                       • writes .github/labview-ci.yml (manifest)
install.sh / install.ps1  ───────────► thin bootstrappers: fetch tooling, find Python, run install.py
```

The design separates three concerns so each is distributed the right way:

- **Heavy, version-pinned** — the multi-GB LabVIEW container image — is built
  **once** and published to GHCR; consumers pull it (they never rebuild it).
- **Logic** — the `.ps1` / `.sh` / `.py` scripts — travels *with* the workflows.
- **Repo-local wiring** — push/PR/`workflow_run`/`status` triggers and the Pages
  publish — must live in each repo, so the installer drops thin copies in.

**Functional wiring adapts at runtime, not at install time.** The image name,
Pages URL, and LabVIEW version derive from the GitHub context and optional
Actions variables, so the same workflow file works unchanged in any repo. The
installer only rewrites *cosmetic* branding (report titles), which keeps installs
robust and upgrades trivial.

## Install from the command line

From the root of the repo you want to add CI to:

```bash
# macOS / Linux / Git Bash
curl -fsSL https://raw.githubusercontent.com/elijah286/challenge-of-champions/main/.github/labview-ci/install.sh \
  | bash -s -- --activities masscompile,vi-analyzer,vidiff,dashboard \
               --os windows,linux --labview-version 2026
```

```powershell
# Windows PowerShell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/elijah286/challenge-of-champions/main/.github/labview-ci/install.ps1))) `
    --activities masscompile,vi-analyzer,vidiff,dashboard --os windows,linux --labview-version 2026
```

Or, from a checkout of the tooling, drive `install.py` directly:

```bash
python3 .github/labview-ci/install.py --list                 # show capabilities
python3 .github/labview-ci/install.py --target /path/to/repo \
    --activities masscompile,dashboard --os windows --dry-run
```

The installer **only writes files into the working tree** — it never runs
LabVIEW, commits, or pushes. Review the result with `git diff`, then follow the
printed next steps (enable Pages, set Actions permissions, commit & push).

### Installer flags

| Flag | Meaning |
|---|---|
| `--activities a,b,c` | Capability ids (default: the recommended set) |
| `--os windows,linux` | Target operating systems |
| `--labview-version` | LabVIEW year (default 2026) |
| `--image-name` | GHCR image name override |
| `--repo owner/name` | Target repo (default: inferred from the git remote) |
| `--dry-run` | Show what would change without writing |
| `--force` | Overwrite files that already exist |
| `--list` | List capabilities and exit |

## Adding a capability

The system is built to scale. To add, say, **Unit Tests**:

1. Add the workflow + script files under `.github/workflows/` and `.github/labview/`.
2. Add (or, for the existing placeholder, edit) one entry in
   [`catalog.json`](catalog.json):

   ```jsonc
   {
     "id": "unit-tests",
     "name": "Unit Tests",
     "summary": "Run Caraya/VI Tester unit tests and publish results.",
     "status": "stable",            // flip from "planned"
     "recommended": true,
     "supportsOs": ["windows", "linux"],
     "requires": [],
     "recommends": ["dashboard"],
     "statusContext": "CI / Unit Tests",
     "files": {
       "any":     ["..."],
       "windows": [".github/workflows/unit-tests-windows.yml", ".github/labview/run-unit-tests.ps1"],
       "linux":   [".github/workflows/unit-tests-linux.yml",  ".github/labview/run-unit-tests.sh"]
     }
   }
   ```

That's it. The capability now appears automatically in the configurator UI and
in `install.py` — no UI code and no installer code to change. `status` controls
presentation: `stable`, `advanced` (opt-in), or `planned` (shown but disabled).

## Files in this folder

| File | Role |
|---|---|
| `catalog.json` | Capability registry — the single source of truth |
| `install.py` | Installer brain (stdlib-only Python) |
| `install.sh` / `install.ps1` | Bootstrappers for `curl \| bash` / PowerShell |
| `config.example.yml` | Documented configuration/manifest schema |
| `README.md` | This document |

The configurator UI lives at [`.github/pages/integrate.html`](../pages/integrate.html)
and is published next to the dashboard.
