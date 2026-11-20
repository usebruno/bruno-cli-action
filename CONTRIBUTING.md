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
