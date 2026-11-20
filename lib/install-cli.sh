#!/usr/bin/env bash
# Install @usebruno/cli. bru-version (exact, range or dist-tag) is resolved to
# a concrete version past the cooldown. If lockfiles/<version>/ exists, install
# that pre-resolved dependency tree; otherwise fall back to a plain npm install.
set -euo pipefail

SPEC="${BRU_VERSION:-latest}"
COOLDOWN_DAYS="${COOLDOWN_DAYS:-2}"
ACTION_ROOT="${GITHUB_ACTION_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCK_ROOT="${ACTION_ROOT}/lockfiles"

RESOLVED="$(npm view @usebruno/cli versions time dist-tags --json |
  node "${ACTION_ROOT}/lib/resolve-version.js" "${SPEC}" "${COOLDOWN_DAYS}" "${LOCK_ROOT}")" || {
  # resolve-version.js prints its own ::error:: line on stdout.
  [ -n "${RESOLVED:-}" ] && echo "${RESOLVED}"
  exit 1
}
VERSION="${RESOLVED% *}"
SOURCE="${RESOLVED#* }"
echo "bru-version '${SPEC}' resolves to ${VERSION} (cooldown ${COOLDOWN_DAYS} days, ${SOURCE})."

if [ "${SOURCE}" = "locked" ]; then
  INSTALL_DIR="${RUNNER_TEMP:-$(mktemp -d)}/bruno-cli-${VERSION}"
  rm -rf "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  cp "${LOCK_ROOT}/${VERSION}/package.json" "${LOCK_ROOT}/${VERSION}/package-lock.json" "${INSTALL_DIR}/"

  echo "::group::Install @usebruno/cli@${VERSION} from lockfile"
  # --ignore-scripts: no dependency lifecycle scripts run. The only one in the
  # tree (protobufjs) is not needed at runtime.
  (cd "${INSTALL_DIR}" && npm ci --ignore-scripts --no-audit --no-fund)
  "${INSTALL_DIR}/node_modules/.bin/bru" --version
  echo "::endgroup::"

  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "${INSTALL_DIR}/node_modules/.bin" >> "${GITHUB_PATH}"
  fi
else
  echo "::warning::@usebruno/cli ${VERSION} has no lockfile in this action; installing with npm, which resolves its dependencies at run time."
  echo "::group::Install @usebruno/cli@${VERSION}"
  npm install -g --min-release-age="${COOLDOWN_DAYS}" "@usebruno/cli@${VERSION}"
  bru --version
  echo "::endgroup::"
fi
