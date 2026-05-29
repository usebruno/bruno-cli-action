#!/usr/bin/env bash
set -euo pipefail

: "${USER_COMMAND:?command is required}"

# Default JUnit path lives in the runner's temp dir so we don't litter the
# user's working-directory with a stray file. Used only when `command` lacks
# its own --reporter-junit flag.
DEFAULT_JUNIT="${RUNNER_TEMP:-/tmp}/bruno-junit.xml"

# Strip a leading `bru ` so users who paste their full local command don't
# end up running `bru bru run ...`. Only strips when followed by a space —
# avoids mangling subcommands that happen to start with "bru" (e.g. "brunch"
# if such a thing ever existed).
SANITIZED_COMMAND="${USER_COMMAND#bru }"

# Tokenize `command` through the shell so quoted arguments survive
# (e.g. `--env-var "API_TOKEN=hello world"`). Same pattern as
# postmanlabs/postman-cli-action. The action author already controls the
# command, so eval does not raise the trust floor.
eval "set -- ${SANITIZED_COMMAND}"
USER_ARGS=( "$@" )

# Detect --reporter-junit <path> or --reporter-junit=<path>. We only care
# about JUnit because that's what the parser reads to compute passed/failed/
# total/duration-ms. JSON and HTML reporters are pure CLI pass-through —
# users add those flags themselves if they want those files.
JUNIT_PATH=""
i=0
while [ "${i}" -lt "${#USER_ARGS[@]}" ]; do
  arg="${USER_ARGS[${i}]}"
  next_i=$((i + 1))
  case "${arg}" in
    --reporter-junit)
      [ "${next_i}" -lt "${#USER_ARGS[@]}" ] && JUNIT_PATH="${USER_ARGS[${next_i}]}"
      ;;
    --reporter-junit=*)
      JUNIT_PATH="${arg#--reporter-junit=}"
      ;;
  esac
  i=$((i + 1))
done

if [ -z "${JUNIT_PATH}" ]; then
  JUNIT_PATH="${DEFAULT_JUNIT}"
  USER_ARGS+=( --reporter-junit "${JUNIT_PATH}" )
  echo "No --reporter-junit in command; defaulted to ${JUNIT_PATH} for parsing."
fi

mkdir -p "$(dirname "${JUNIT_PATH}")"

# Absolute path so the next step (which may run in a different cwd) can find it.
ABS_JUNIT_PATH="$(cd "$(dirname "${JUNIT_PATH}")" && pwd)/$(basename "${JUNIT_PATH}")"

echo "::group::bru ${USER_ARGS[*]}"
set +e
bru "${USER_ARGS[@]}"
EXIT_CODE=$?
set -e
echo "::endgroup::"

{
  echo "junit-path=${ABS_JUNIT_PATH}"
  echo "exit-code=${EXIT_CODE}"
} >> "${GITHUB_OUTPUT}"

# Surface the JUnit path as a workflow notice so it's visible on the run page
# without having to scroll the step log. Only emit when the file actually
# landed on disk — if bru crashed before writing, the notice would be misleading.
if [ -f "${ABS_JUNIT_PATH}" ]; then
  echo "::notice title=Bruno JUnit report::Written to ${ABS_JUNIT_PATH}. Chain actions/upload-artifact to persist it as a downloadable workflow artifact."
fi

exit 0
