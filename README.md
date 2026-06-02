# Bruno CLI GitHub Action

Official GitHub Action for running [Bruno](https://www.usebruno.com) CLI commands in CI.

Installs `@usebruno/cli`, runs an arbitrary `bru` command, parses the emitted JUnit XML, and exposes machine-readable counts (`exit-code`, `passed`, `failed`, `total`, `duration-ms`) for downstream steps. UI rendering, artifact upload, PR comments, and soft-fail semantics are delegated to the GitHub Actions ecosystem (`EnricoMi/publish-unit-test-result-action`, `dorny/test-reporter`, `actions/upload-artifact`, `continue-on-error`). See [Pairing with downstream actions](#pairing-with-downstream-actions) for canonical recipes.

Design pattern follows [`postmanlabs/postman-cli-action`](https://github.com/postmanlabs/postman-cli-action) and [`kong/setup-inso`](https://github.com/kong/setup-inso): minimal-input pass-through, no flag mirroring.

## Quickstart

```yaml
# Minimal — installs the CLI, runs the collection, returns counts as outputs.
# Step fails (red) on assertion failure, succeeds (green) on success.
# No UI surfaces, no artifact upload by default.
# See "Pairing with downstream actions" for PR comments, annotations,
# Step Summary, artifact upload, soft-fail, and more.
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod'
```

**What you'll see:** the workflow step turns red on assertion failure (green on success). No PR comments, no annotations, no Step Summary, no uploaded artifact. Outputs are populated for downstream conditional steps.

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `command` | yes | — | The `bru` subcommand and flags (e.g. `run --env prod`). The action prepends `bru`. Reporter flags are optional; `--reporter-junit` is auto-injected if absent. |
| `bru-version` | no | `latest` | Version of `@usebruno/cli` to install. |
| `working-directory` | no | `.` | Shell working directory. Typically the Bruno collection root. |

No typed inputs for `--env`, `--env-var`, `--tags`, `--bail`, `--sandbox`, `--reporter-*`, etc. They all go in `command`. Every CLI flag works the day it ships in the CLI, with zero coordination cost.

## Outputs

Available as `${{ steps.<id>.outputs.<name> }}` in subsequent steps:

| Output | Description |
|---|---|
| `exit-code` | The `bru` process exit code. |
| `passed` | Number of passed requests. |
| `failed` | Number of failed requests (assertion failures or runtime errors). |
| `total` | Total requests run. |
| `duration-ms` | Total run duration in milliseconds. |

Report file paths are intentionally **not** outputs. Users who chain to downstream actions pass an explicit `--reporter-junit <path>` in `command` and reference that path directly in the next step.

## Behavior

### JUnit auto-injection (always-on)

If the user's `command` does not contain `--reporter-junit`, the action appends `--reporter-junit "$RUNNER_TEMP/bruno-junit.xml"` before invoking `bru`. JUnit is required for output extraction; auto-injection means a minimal `command: 'run'` produces count outputs without the user having to remember reporter flags. The file lives in the runner's temp dir and is auto-cleaned post-job.

If the user explicitly passes `--reporter-junit some/path.xml`, the action honors that path and parses from there.

### Exit code propagation

The action propagates `bru`'s exit code naturally. The workflow step succeeds on exit 0 and fails on non-zero. Users who want the workflow to continue past failures use GitHub Actions' built-in `continue-on-error: true` (see recipe #12).

## Pairing with downstream actions

This section covers every reporting and artifact use case. The action emits clean JUnit XML; downstream actions render it for the user-visible surface needed or upload it as a workflow artifact.

### 1. PR comment on every run (sticky, updated in place)

The most common ask. `EnricoMi/publish-unit-test-result-action` posts a single comment per PR with structured results, updated on re-runs. Adds a check run with rich annotations as a side benefit.

```yaml
name: API Tests
on: [pull_request]

permissions:
  pull-requests: write
  checks: write
  contents: read

jobs:
  bruno:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: usebruno/bruno-run-action@v1
        with:
          working-directory: tests/payments
          command: 'run --env prod --reporter-junit results.xml'

      - uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: tests/payments/results.xml
```

**Prerequisites:** `pull-requests: write` and `checks: write` permissions in the workflow file.
**What you'll see:** a single Bruno-themed comment in the PR Conversation tab that updates in place on every re-run, plus a check run with structured per-test results in the PR Checks tab.
**Why `if: always()`:** EnricoMi must run even when the Bruno step fails the build, otherwise users do not see the comment on failure.

### 2. PR comment only when there are failures

For teams who do not want a green-passes-everywhere comment polluting the conversation:

```yaml
- uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/payments/results.xml
    comment_mode: failures   # post a comment only when something failed
```

**What you'll see:** PR comment appears only when at least one assertion failed. Successful runs leave no comment behind.
**Other `comment_mode` values:** `always` (default), `failures`, `errors`, `off`.

### 3. Step Summary on the workflow run page (without PR comment)

EnricoMi writes a Step Summary by default. If you want the workflow-page digest but no PR comment noise:

```yaml
- uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/payments/results.xml
    comment_mode: off              # disable PR comment
    job_summary: true              # default true; shown for clarity
```

**What you'll see:** a markdown summary on the workflow run page (visible by clicking into the run from the Actions tab). No PR Conversation comment, no Checks-tab check run annotations.

### 4. Workflow-level annotations (errors visible on the PR Checks card)

EnricoMi posts annotations via the Check Runs API. These appear in the PR Checks tab attached to EnricoMi's check run:

```yaml
- uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/payments/results.xml
    report_individual_runs: true   # one annotation per failed test
```

**What you'll see:** the PR Checks tab shows the EnricoMi check run with one annotation per failed assertion, expandable for failure details.
**Note:** line-anchored annotations on `.bru` source lines would require the CLI to emit `file=` and `line=` in JUnit. Not currently planned.

### 5. Checks tab UI via dorny/test-reporter

If you have a polyglot test stack (Jest, Pytest, Bruno) and want all results in the same Checks tab UI, dorny is the better tool than EnricoMi:

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml'

- uses: dorny/test-reporter@v1
  if: always()
  with:
    name: Bruno API tests
    path: tests/payments/results.xml
    reporter: java-junit
```

**What you'll see:** a separate check run in the PR Checks tab labeled "Bruno API tests" with structured per-test results and expandable failure details. Visually consistent with check runs from your other JUnit-emitting test suites.

### 6. EnricoMi + dorny together (PR comment + rich Checks tab)

When you want both: a PR Conversation comment from EnricoMi and a polished Checks tab UI from dorny:

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml'

- uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/payments/results.xml
    comment_mode: always

- uses: dorny/test-reporter@v1
  if: always()
  with:
    name: Bruno API tests
    path: tests/payments/results.xml
    reporter: java-junit
```

**What you'll see:** PR Conversation gets the EnricoMi sticky comment; PR Checks tab shows two check runs (one from each downstream action) plus the EnricoMi annotations.

### 7. Artifact upload with header sanitization

Bruno's CLI handles sensitive-header redaction; pass the flag in `command`. Chain `actions/upload-artifact@v7` to persist the report:

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml --reporter-skip-headers "Authorization Cookie X-Tenant-Token"'

- uses: actions/upload-artifact@v7
  if: always()
  with:
    name: bruno-report-${{ github.run_id }}-${{ github.job }}
    path: tests/payments/results.xml
```

**What you'll see:** an artifact named `bruno-report-<run_id>-<job>` on the workflow run page, downloadable for 90 days (GitHub default retention). `Authorization`, `Cookie`, and `X-Tenant-Token` headers are redacted in the JUnit XML before upload.

To customize retention or use compression options, see `actions/upload-artifact@v7`'s own inputs (`retention-days`, `compression-level`, `if-no-files-found`).

### 8. Multiple report formats (JUnit + HTML + JSON)

Pass multiple reporter flags in `command`. Chain `actions/upload-artifact@v7` with a path list:

```yaml
- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml --reporter-html report.html --reporter-json report.json'

- uses: actions/upload-artifact@v7
  if: always()
  with:
    name: bruno-reports-${{ github.run_id }}
    path: |
      tests/payments/results.xml
      tests/payments/report.html
      tests/payments/report.json
```

**What you'll see:** an artifact containing all three report files. Download to a browser to view the rich HTML report; JSON is consumable by custom dashboards or aggregators.

### 9. Slack notification on failure

Use the JUnit-derived `failed` output as a conditional. Use `continue-on-error: true` so the notification step still runs:

```yaml
- id: bruno
  uses: usebruno/bruno-run-action@v1
  continue-on-error: true
  with:
    working-directory: tests/payments
    command: 'run --env prod'

- if: steps.bruno.outputs.failed != '0'
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Bruno tests failed: ${{ steps.bruno.outputs.failed }}/${{ steps.bruno.outputs.total }} requests failed on ${{ github.ref_name }}",
        "blocks": [{
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "*Bruno test failures on ${{ github.ref_name }}*\n${{ steps.bruno.outputs.failed }}/${{ steps.bruno.outputs.total }} requests failed in ${{ steps.bruno.outputs.duration-ms }}ms. <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View run>"
          }
        }]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

**Prerequisites:** `SLACK_WEBHOOK_URL` secret configured in the repository.
**What you'll see:** the Bruno step shows red on failure (honest signal) but the workflow continues; a Slack message lands in the channel mapped to the webhook with counts, branch, duration, and a link to the workflow run.

### 10. Simple non-sticky PR comment via gh CLI (lightweight alternative to EnricoMi)

For users who do not want EnricoMi's full setup and only need a quick "post a comment with the counts" pattern (no stickiness, each run adds a new comment):

```yaml
- id: bruno
  uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod'

- if: always() && github.event_name == 'pull_request'
  run: |
    if [ "${{ steps.bruno.outputs.failed }}" -gt 0 ]; then
      ICON="❌"
      STATUS="${{ steps.bruno.outputs.passed }}/${{ steps.bruno.outputs.total }} passed, ${{ steps.bruno.outputs.failed }} failed"
    else
      ICON="✅"
      STATUS="${{ steps.bruno.outputs.total }}/${{ steps.bruno.outputs.total }} passed"
    fi
    gh pr comment ${{ github.event.pull_request.number }} \
      --body "${ICON} **Bruno:** ${STATUS} in ${{ steps.bruno.outputs.duration-ms }}ms · [view run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Prerequisites:** `pull-requests: write` permission and the workflow triggered on `pull_request`.
**What you'll see:** a new comment posted to the PR on every workflow run. Each re-run adds another comment (no in-place update). Use EnricoMi (recipe #1) if you want stickiness.

### 11. Matrix across environments

Use distinct JUnit paths and artifact names per matrix leg. Chain EnricoMi and `actions/upload-artifact@v7` per leg:

```yaml
on: [pull_request]

permissions:
  pull-requests: write
  checks: write
  contents: read

jobs:
  bruno:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [staging, prod]
    steps:
      - uses: actions/checkout@v6
      - uses: usebruno/bruno-run-action@v1
        with:
          working-directory: tests/payments
          command: 'run --env ${{ matrix.env }} --reporter-junit results-${{ matrix.env }}.xml'

      - uses: actions/upload-artifact@v7
        if: always()
        with:
          name: bruno-report-${{ matrix.env }}
          path: tests/payments/results-${{ matrix.env }}.xml

      - uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          check_name: Bruno (${{ matrix.env }})
          files: tests/payments/results-${{ matrix.env }}.xml
          comment_mode: failures
```

**What you'll see:** two matrix legs running in parallel against staging and prod. Each leg produces its own artifact (`bruno-report-staging`, `bruno-report-prod`), its own check run (`Bruno (staging)` / `Bruno (prod)`) in the PR Checks tab, and a PR comment only when that leg fails.
**Note:** include the matrix key in both `--reporter-junit` and the artifact `name` to avoid `actions/upload-artifact@v7`'s duplicate-name error across matrix legs.

### 12. Soft-fail recipe

Record results without failing the build, then notify selectively. Use GitHub Actions' built-in `continue-on-error: true`:

```yaml
- id: bruno
  uses: usebruno/bruno-run-action@v1
  continue-on-error: true
  with:
    working-directory: tests/payments
    command: 'run --env prod'

- if: steps.bruno.outputs.failed != '0'
  run: ./notify-slack.sh ${{ steps.bruno.outputs.failed }}
```

**What you'll see:** the Bruno step appears red in the workflow run UI when assertions fail (honest signal that something went wrong), but downstream steps still run because `continue-on-error` lets the workflow proceed. Outputs are populated for the conditional notification step.

### 13. Forked-PR caveat

GitHub restricts `GITHUB_TOKEN` to read-only for workflows triggered by `pull_request` events from forked repositories, regardless of the `permissions` block in the workflow file. EnricoMi and any PR comment poster need write permission, which means workflows running on community contributions must use `pull_request_target` (with care: it runs with the base branch's permissions and secrets). See the [GitHub docs](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#permissions-for-the-github_token) and [EnricoMi's fork PR docs](https://github.com/EnricoMi/publish-unit-test-result-action#support-fork-repositories-and-dependabot-branches) for the trade-offs.

## Enterprise patterns (mTLS, custom CA)

Marshall secrets via shell, pass paths to bru:

```yaml
- run: |
    mkdir -p /tmp/certs && chmod 700 /tmp/certs
    echo "$CA_CERT" > /tmp/certs/ca.pem
    echo "$CLIENT_CERT_CONFIG" > /tmp/certs/client.json
  env:
    CA_CERT: ${{ secrets.API_CA_CERT }}
    CLIENT_CERT_CONFIG: ${{ secrets.API_CLIENT_CERT_CONFIG }}

- uses: usebruno/bruno-run-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --cacert /tmp/certs/ca.pem --client-cert-config /tmp/certs/client.json'
```

**Prerequisites:** `API_CA_CERT` and `API_CLIENT_CERT_CONFIG` secrets configured.
**What you'll see:** Bruno runs against an internal mTLS-protected API. Secrets never appear in logs (GitHub auto-masks); cert files are written to a temp dir and cleaned up when the runner is destroyed.

## Other CI platforms

Bruno's CLI works on Jenkins, Azure DevOps, GitLab CI, and Bitbucket Pipelines via direct CLI invocation. The [Bruno CLI Docker image](https://hub.docker.com/r/usebruno/cli) is the recommended primitive there. See the [Bruno CLI docs](https://docs.usebruno.com/bru-cli/overview) for platform-specific examples.

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

**Verifying which flags `bru` was invoked with.** The action prints the full `bru` invocation inside a `::group::` block in the run log, including any flags it auto-injected (`--reporter-junit "$RUNNER_TEMP/bruno-junit.xml"`). Expand the group to confirm what ran.

### Exit-code reference

`bru` exits with one of the following codes, available as `steps.<id>.outputs.exit-code`:

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

(Source: `packages/bruno-cli/src/constants.js` in the Bruno repo. Codes may shift across major CLI versions; the nightly workflow catches changes.)

### Job failed before bru could run

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

## License

MIT
