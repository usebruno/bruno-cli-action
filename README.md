# Bruno CLI GitHub Action

Official GitHub Action for running [Bruno CLI](https://docs.usebruno.com/bru-cli/overview) commands in CI/CD workflows with full support for collection runs and exposes machine-readable counts (`exit-code`, `passed`, `failed`, `total`, `duration-ms`) for downstream steps. 

- [Usage](#usage)
- [Customize](#customize)
  - [Inputs](#inputs)
  - [Outputs](#outputs)
  - [Behavior](#behavior)
- [Versioning](#versioning)
- [Examples](#examples)
- [Other CI Platforms](#other-ci-platforms)
- [Resources](#resources)

## Usage

The following shows the minimum setup to configure the GitHub Action with a command and return counts as outputs. Learn about the [supported inputs](#inputs) you can use to customize the GitHub Action.

```yaml
name: API Tests

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Run Bruno Collection
        uses: usebruno/bruno-cli-action@v1
        with:
          working-directory: tests/payments
          command: 'run --env prod'
```

**What you'll see:** the workflow step turns red on assertion failure (green on success). Outputs are populated for downstream conditional steps.

UI rendering, artifact upload, PR comments, and soft-fail semantics are delegated to the GitHub Actions ecosystem (`EnricoMi/publish-unit-test-result-action`, `dorny/test-reporter`, `actions/upload-artifact`, `continue-on-error`). See [Examples](#examples) for canonical recipes.

## Customize

Customize the Bruno CLI GitHub Action to suit your API project's CI/CD workflow.

### Inputs

| Name | Type | Description |
|---|---|---|
| `command` | String | **Required.** The Bruno CLI command to run and its options (e.g. `run --env prod`). The action prepends `bru`. |
| `bru-version` | String | Version of `@usebruno/cli` to install. (Default: `latest`) |
| `working-directory` | String | Path of the Bruno collection directory. (Default: `.`) |

**Example using all inputs:**

```yaml
- name: Run Bruno collection
  uses: usebruno/bruno-cli-action@v1
  with:
    command: 'run --env prod --reporter-junit results.xml'
    bru-version: '3.5.0'
    working-directory: tests/payments
```

### Outputs

Available as `${{ steps.<id>.outputs.<name> }}` in subsequent steps:

| Name | Description |
|---|---|
| `exit-code` | Exit code from the Bruno CLI command. 0 indicates success, non-zero indicates failure. |
| `passed` | Number of passed requests. |
| `failed` | Number of failed requests (assertion failures or runtime errors). |
| `total` | Total number of requests run. |
| `duration-ms` | Total run duration in milliseconds. |

## Versioning

| Tag | Behaviour |
|---|---|
| `@v1` | Floating major. Receives every backwards-compatible release. |
| `@v1.0.0` | Immutable. Pinned to a specific release. |

The `v<major>` tag is retagged automatically on every published release.

## Examples

The following examples cover some of the reporting and artifact use case. Use `--reporter-junit` flag to emit clean JUnit XML; downstream actions render it for the user-visible surface needed or upload it as a workflow artifact.

- [PR comment on every run (sticky)](#pr-comment-on-every-run-sticky)
- [Checks tab UI via dorny/test-reporter](#checks-tab-ui-via-dornytest-reporter)
- [Artifact upload with header sanitization](#artifact-upload-with-header-sanitization)
- [Multiple report formats (JUnit + HTML + JSON)](#multiple-report-formats-junit--html--json)
- [Slack notification on failure](#slack-notification-on-failure)
- [Simple non-sticky PR comment via gh CLI](#simple-non-sticky-pr-comment-via-gh-cli)

### PR comment on every run (sticky)

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
      - uses: usebruno/bruno-cli-action@v1
        with:
          working-directory: tests/payments
          command: 'run --env prod --reporter-junit results.xml'

      - uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: tests/payments/results.xml
```

**What you'll see:** a single Bruno-themed comment in the PR Conversation tab that updates in place on every re-run, plus a check run with structured per-test results in the PR Checks tab.

### Checks tab UI via dorny/test-reporter

If you have a polyglot test stack (Jest, Pytest, Bruno) and want all results in the same Checks tab UI, dorny is the better tool than EnricoMi:

```yaml
- uses: usebruno/bruno-cli-action@v1
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

### Artifact upload with header sanitization

Bruno's CLI handles sensitive-header redaction; pass the flag in `command`. Chain `actions/upload-artifact@v7` to persist the report:

```yaml
- uses: usebruno/bruno-cli-action@v1
  with:
    working-directory: tests/payments
    command: 'run --env prod --reporter-junit results.xml --reporter-skip-headers "Authorization Cookie X-Tenant-Token"'

- uses: actions/upload-artifact@v7
  if: always()
  with:
    name: bruno-report-${{ github.run_id }}-${{ github.job }}
    path: tests/payments/results.xml
```

**What you'll see:** an artifact named `bruno-report-<run_id>-<job>` on the workflow run page, downloadable for 90 days (GitHub default retention).

### Multiple report formats (JUnit + HTML + JSON)

Pass multiple reporter flags in `command`. Chain `actions/upload-artifact@v7` with a path list:

```yaml
- uses: usebruno/bruno-cli-action@v1
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

### Slack notification on failure

Use the action's `failed` output as a conditional. Use `continue-on-error: true` so the notification step still runs:

```yaml
- id: bruno
  uses: usebruno/bruno-cli-action@v1
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

### Simple non-sticky PR comment via gh CLI

For users who do not want EnricoMi's full setup and only need a quick "post a comment with the counts" pattern (no stickiness, each run adds a new comment):

```yaml
- id: bruno
  uses: usebruno/bruno-cli-action@v1
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
**What you'll see:** a new comment posted to the PR on every workflow run. Each re-run adds another comment (no in-place update). Use EnricoMi (above) if you want stickiness.

## Other CI platforms

Bruno's CLI works on Jenkins, Azure DevOps, GitLab CI, and Bitbucket Pipelines via direct CLI invocation. The [Bruno CLI Docker image](https://hub.docker.com/r/usebruno/cli) is the recommended primitive there. See the [Bruno CLI Docker docs](https://docs.usebruno.com/bru-cli/docker) for platform-specific examples.

## Resources

- [Bruno CLI documentation](https://docs.usebruno.com/bru-cli/overview)
- [Bruno CLI command options](https://docs.usebruno.com/bru-cli/commandOptions)
- [Bruno NPM package](https://www.npmjs.com/package/@usebruno/cli)
- [Main Bruno repo](https://github.com/usebruno/bruno)

## License

MIT
