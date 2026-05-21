# Bruno Run Action

Official GitHub Action for running [Bruno](https://www.usebruno.com) CLI commands in CI.

Installs `@usebruno/cli`, runs an arbitrary `bru` command, and exposes machine-readable outputs (`exit-code`, `passed`, `failed`, `total`, `duration-ms`) for downstream steps.

Design pattern follows [`postmanlabs/postman-cli-action`](https://github.com/marketplace/actions/postman-cli-action) and [`kong/setup-inso`](https://github.com/marketplace/actions/setup-inso) — installer + CWD, no flag-mirroring. Every Bruno CLI flag works the day it ships in the CLI.

## Requirements

GitHub-hosted runners (`ubuntu-*`, `macos-*`, `windows-*` w/ bash) ship everything the action needs.

| Tool | Why | GH-hosted | Self-hosted |
|---|---|---|---|
| `bash` | composite scripts | ✅ | install |
| `node` | the action installs Node 20 via `actions/setup-node@v6` | ✅ (auto) | ✅ (auto) |

## Quickstart

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml'
```

`working-directory` is the Bruno collection root. `command` is everything after `bru` — the action prepends it.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `command` | yes | — | The `bru` subcommand and flags (e.g. `run --env prod --reporter-junit results.xml`). The action prepends `bru`. |
| `bru-version` | no | `latest` | Version of `@usebruno/cli` to install. |
| `working-directory` | no | `.` | Shell working directory. Typically the Bruno collection root. |

No typed inputs for `--env`, `--env-var`, `--tags`, `--bail`, `--sandbox`, `--reporter-*`, etc. They all go in `command`. This is deliberate: zero coordination cost when the CLI adds a flag.

## Outputs

| Output | Description |
|---|---|
| `passed` | Number of requests that passed. |
| `failed` | Number of requests that failed. |
| `total` | Total requests executed. |
| `duration-ms` | Sum of testsuite durations in ms. |
| `exit-code` | Raw exit code from `bru run`. |

Counts come from the JUnit XML emitted by the CLI. If `command` omits `--reporter-junit`, the action injects `--reporter-junit bruno-junit.xml` internally so the parser has something to read. JSON and HTML reporters are pure CLI pass-through — add `--reporter-json X.json` or `--reporter-html X.html` to `command` yourself if you want those files; the action does not touch their paths.

## Examples

### 1. Canonical pattern

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml'
```

### 2. Run a sub-folder

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run smoke --env prod'
```

### 3. Matrix across environments

```yaml
strategy:
  fail-fast: false
  matrix:
    env: [staging, prod]
steps:
  - uses: actions/checkout@v6
  - uses: usebruno/bruno-run-action@v1
    with:
      working-directory: tests/payments
      command: 'run --env ${{ matrix.env }} --reporter-junit ${{ matrix.env }}.xml'
```

### 4. Monorepo

Each service owns its own collection. Point `working-directory` at the per-service collection root:

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: services/payments/bruno
    command: 'run --env ci --reporter-junit results.xml'
```

### 4a. Workspace + global environment

For collections that live inside a workspace (`workspace.yml` at the root and the collection in a subfolder):

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: .
    command: >-
      run collections/payments-api
      --workspace-path .
      --global-env ci
      --tags smoke,workflow,release-gate
      --env-var "platform_name=GitHub Actions"
      --env-var "build_id=${{ github.run_id }}"
      --env-var "commit_sha=${{ github.sha }}"
```

The YAML `>-` folded scalar keeps the command readable across lines while staying a single string for the action to parse.

### 4b. Different test sets per trigger

Run the smoke tags on every PR; run everything on `main`:

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: bruno
    command: >-
      run
      --env ci
      ${{ github.event_name == 'pull_request' && '--tags smoke' || '' }}
```

### 4c. Data-driven run via CSV

```yaml
- uses: actions/checkout@v6
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: bruno
    command: 'run --env ci --csv-file-path tests/users.csv'
```

### 4d. Per-matrix-leg artifact (HTML + JUnit)

```yaml
strategy:
  fail-fast: false
  matrix:
    env: [staging, prod]
steps:
  - uses: actions/checkout@v6
  - uses: usebruno/bruno-run-action@v1
    with:
      working-directory: bruno
      command: >-
        run --env ${{ matrix.env }}
        --reporter-junit reports/${{ matrix.env }}.xml
        --reporter-html  reports/${{ matrix.env }}.html

  - if: always()
    uses: actions/upload-artifact@v7
    with:
      name: bruno-report-${{ matrix.env }}
      path: |
        bruno/reports/${{ matrix.env }}.xml
        bruno/reports/${{ matrix.env }}.html
```

### 5. PR comments via `EnricoMi/publish-unit-test-result-action`

Add `--reporter-junit results.xml` to your `command`, then point the publisher at the same path. `${{ github.workspace }}` makes the path absolute regardless of `working-directory`.

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml'

- uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: ${{ github.workspace }}/tests/payments/results.xml
```

### 6. Conditional Slack on regression

```yaml
- uses: usebruno/bruno-run-action@v1
  id: bruno
  continue-on-error: true
  with:
    working-directory: tests/payments
    command: 'run --env prod'

- if: steps.bruno.outputs.failed != '0'
  run: ./scripts/slack-notify.sh "${{ steps.bruno.outputs.failed }} failing"

- if: steps.bruno.outputs.duration-ms > 30000
  run: ./scripts/slack-notify.sh "Bruno took ${{ steps.bruno.outputs.duration-ms }} ms"
```

## Versioning

| Tag | Behaviour |
|---|---|
| `@v1` | Floating major. Receives every backwards-compatible release. |
| `@v1.2.3` | Immutable. Pinned to a specific release. |

The `v<major>` tag is retagged automatically on every published release.

## Troubleshooting

**Sandbox migration (Bruno CLI v3+).** v3 changed the default sandbox. If your tests rely on Node built-ins (`require`, `Buffer`, etc.), add `--sandbox developer` to `command`:

```yaml
command: 'run --env ci --sandbox developer'
```

**`exit-code` is non-zero but `failed` is `0`.** The `bru` process crashed before writing JUnit, or wrote an empty report. Treat as a runtime error — check the step log for stderr. See the exit-code reference below.

### Exit-code reference

`bru` exits with one of the following codes. They flow through to `steps.<id>.outputs.exit-code`:

| Code | Meaning | Common cause |
|------|---------|--------------|
| 0    | All requests, tests, and assertions passed | — |
| 1    | One or more requests, tests, or assertions failed | inspect the JUnit XML; fix the failing tests |
| 2    | Reporter output directory does not exist | create the dir or change `--reporter-junit` path |
| 3    | Request chain caused an infinite loop | break the loop in your collection |
| 4    | `bru` was invoked outside a collection root | set `working-directory` to the collection dir |
| 5    | A file referenced by `command` was not found | typo'd path in `command` |
| 6    | Environment file not found | check `environments/<env>.bru` exists |
| 7    | `--env-var` value not parsable as `name=value` | fix the quoting in `command` |
| 8    | `--env-var` format incorrect | same — see Bruno CLI docs |
| 9    | Invalid reporter format | only `json` / `junit` / `html` accepted |
| 10   | Failed to parse a `.bru` / env / config file | syntax error in the file |
| 11   | Workspace not found (when `--workspace-path` used) | check the path |
| 12   | `--global-env` used without `--workspace-path` | add `--workspace-path` |
| 13   | Global environment file not found | check the global env name |
| 137  | OS killed the process (`SIGKILL`, usually OOM) | bigger runner or split the collection |
| 130  | Job was cancelled (`SIGINT`) | check `timeout-minutes`; nothing to fix in `command` |
| 255  | Unhandled CLI crash (`ERROR_GENERIC`) | open an issue in `usebruno/bruno` with the stderr |

(Source: `packages/bruno-cli/src/constants.js` in the Bruno repo. Codes may shift across major CLI versions; the nightly smoke catches changes.)

### My job failed before bru could run

If the run log shows a red **Install Bruno CLI** step (not **Run bru**), the failure is in `npm install -g @usebruno/cli`, not in your collection. `outputs.exit-code` will be empty because `bru` never ran. Expand that step and look for one of:

| stderr substring | Likely cause | Fix |
|---|---|---|
| `E404` / `404 Not Found` | `bru-version` doesn't exist on npm | pick a real version (or `latest`) |
| `ENOTFOUND` / `ETIMEDOUT` | runner can't reach `registry.npmjs.org` | check corp proxy / network policy |
| `EACCES` | self-hosted runner missing install permission | adjust npm prefix or run with sudo |
| `ENOSPC` | self-hosted runner disk full | clear space |
| `EINTEGRITY` | corrupted npm cache | `npm cache clean --force` then re-run |

All of these surface npm exit `1`. The useful signal is the stderr text, not the exit number.

**Network timeouts.** Bruno honours `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`. Set them via `env:` on the step.

## Other CI platforms

For GitLab, Azure DevOps, Jenkins, CircleCI — use the [Bruno CLI Docker image](https://hub.docker.com/r/usebruno/cli) directly. This action is GitHub-Actions-specific by design.

## License

MIT
