# Contributing

Notes for maintainers of this action. Consumer-facing documentation is in [README.md](README.md).

## How Bruno CLI installs work

`lib/install-cli.sh` resolves `bru-version` to a concrete `@usebruno/cli` version with `lib/resolve-version.js`. It accepts exact versions (with or without a leading `v`), ranges and dist-tags, the way npm does, and only considers versions published at least `cooldown-days` ago.

- **Locked:** if `lockfiles/<version>/package-lock.json` exists, the script copies it into `$RUNNER_TEMP`, runs `npm ci --ignore-scripts`, and adds that folder's `node_modules/.bin` to `$GITHUB_PATH`. Bruno's dependencies are never resolved at run time.
- **Fallback:** otherwise it prints a `::warning::` and runs `npm install -g --min-release-age=<cooldown-days>`, which resolves dependencies at run time.

Lockfiles exist for every 3.x and 4.x release, plus the most-downloaded 1.x and 2.x releases (each had at least 500 weekly downloads when it was added). Every locked package resolves from registry.npmjs.org, and GitHub's dependency graph and Dependabot alerts scan each lockfile.

Locking a version doesn't make it safe. Many lockfiles contain vulnerable dependencies that Bruno itself pins, and the old unlocked install got the same ones. To see the known issues for a version, run this in its folder:

```sh
npm audit --package-lock-only
```

## Adding or regenerating a lockfile

`scripts/add-version.sh` needs npm 11.10 or newer for `--min-release-age`:

```sh
scripts/add-version.sh 4.3.0           # add
FORCE=1 scripts/add-version.sh 4.3.0   # regenerate, picking up in-range dependency fixes
```

It runs `npm install --package-lock-only --ignore-scripts` in a temp folder with a 2-day release-age cooldown (`COOLDOWN_DAYS`), so neither Bruno nor any of its dependencies can be locked until it has been published for 2 days. It then checks that the locked CLI version is the one requested and that every package comes from registry.npmjs.org.

Lockfiles don't pick up dependency fixes on their own. Regenerate a version with `FORCE=1` to pick up fixes that fall within Bruno's semver ranges.

## Automated lockfile PRs

`.github/workflows/add-bruno-version.yml` runs daily and on manual dispatch. `scripts/missing-versions.sh` lists every stable release from `MIN_VERSION` (default 3.0.0) onwards that is past the cooldown and has no lockfile, including backports to older lines. The workflow opens one PR per version on a `bruno-lockfile/<version>` branch.

- If one version can't be locked, the others still get PRs, and the run fails listing the version that failed.
- If an earlier run pushed a branch but never opened its PR, the next run opens it.
- To decline a version, close its PR without deleting the branch, and it won't be proposed again.
- Older majors are locked selectively by hand.
- PRs opened with `GITHUB_TOKEN` don't trigger other workflows, so run the smoke tests manually on the PR branch.
- After merging, cut a release so `@v1` consumers get the new lockfile.

### Human review

These PRs always need a human to review them. The workflow opens them as drafts, never enables auto-merge, and requests review from the comma-separated GitHub usernames in the `LOCKFILE_REVIEWERS` repository variable. Teams can't be requested with the workflow's `GITHUB_TOKEN`, so use `CODEOWNERS` for team review.

To make a human approval mandatory, set up the repository:

- Protect `main` with a branch protection rule or ruleset that requires at least one approving review and blocks direct pushes.
- Add a `CODEOWNERS` entry for `/lockfiles/` and turn on "Require review from Code Owners", so an approval from the `github-actions` bot never counts.
- Turn on "Allow GitHub Actions to create and approve pull requests" so the workflow can open PRs. The same setting lets the bot approve PRs, which is why the Code Owners requirement matters.

## What consumers download

The Actions runner downloads the archive GitHub generates for a ref, not a clone. Anything consumers don't need at runtime (`tests/`, `.github/`, `scripts/` and this file) is marked `export-ignore` in `.gitattributes` to keep that archive small. `lib/` and `lockfiles/` are needed at runtime and must never be excluded. Check what consumers receive with:

```sh
git archive HEAD | tar -t
```
