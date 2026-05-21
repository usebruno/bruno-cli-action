#!/usr/bin/env bash
set -uo pipefail

: "${USER_COMMAND:?command is required}"

DEFAULT_JUNIT="bruno-junit.xml"

# Strip a leading `bru ` (or just `bru`) so users who paste their full local
# command don't end up running `bru bru run ...`.
SANITIZED_COMMAND="${USER_COMMAND#bru }"
SANITIZED_COMMAND="${SANITIZED_COMMAND#bru}"

# Tokenize `command` through the shell so quoted arguments survive
# (e.g. `--env-var "API_TOKEN=hello world"`). Same pattern as
# postmanlabs/postman-cli-action. The action author already controls the
# command, so eval does not raise the trust floor.
eval "set -- ${SANITIZED_COMMAND}"
USER_ARGS=( "$@" )

# Detect any --reporter-{junit,json,html} <path> or --reporter-{junit,json,html}=<path>
# in user args. We only inject a default for junit (parser requires it); json
# and html stay opt-in per the pass-through design.
JUNIT_PATH=""
JSON_PATH=""
HTML_PATH=""

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
    --reporter-json)
      [ "${next_i}" -lt "${#USER_ARGS[@]}" ] && JSON_PATH="${USER_ARGS[${next_i}]}"
      ;;
    --reporter-json=*)
      JSON_PATH="${arg#--reporter-json=}"
      ;;
    --reporter-html)
      [ "${next_i}" -lt "${#USER_ARGS[@]}" ] && HTML_PATH="${USER_ARGS[${next_i}]}"
      ;;
    --reporter-html=*)
      HTML_PATH="${arg#--reporter-html=}"
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

# Resolve absolute paths for any reporter that was set, so downstream steps
# (running from a different cwd) can consume them.
abs_path() {
  local p="$1"
  [ -z "${p}" ] && { echo ""; return; }
  local dir
  dir="$(dirname "${p}")"
  mkdir -p "${dir}" 2>/dev/null || true
  echo "$(cd "${dir}" && pwd)/$(basename "${p}")"
}

ABS_JUNIT_PATH="$(abs_path "${JUNIT_PATH}")"
ABS_JSON_PATH="$(abs_path "${JSON_PATH}")"
ABS_HTML_PATH="$(abs_path "${HTML_PATH}")"

echo "::group::bru ${USER_ARGS[*]}"
set +e
bru "${USER_ARGS[@]}"
EXIT_CODE=$?
set -e
echo "::endgroup::"

{
  echo "report-junit=${ABS_JUNIT_PATH}"
  echo "report-json=${ABS_JSON_PATH}"
  echo "report-html=${ABS_HTML_PATH}"
  echo "exit-code=${EXIT_CODE}"
} >> "${GITHUB_OUTPUT}"

exit 0
