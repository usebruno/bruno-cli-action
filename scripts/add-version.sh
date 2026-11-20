#!/usr/bin/env bash
# Generate lockfiles/<version>/{package.json,package-lock.json} for one or more
# @usebruno/cli versions.
#
#   scripts/add-version.sh 4.3.0 [4.2.1 ...]
#
# Env:
#   COOLDOWN_DAYS  Only lock package versions published at least this many days
#                  ago, including @usebruno/cli itself (default 2).
#   FORCE=1        Regenerate a version that already has a lockfile.
#
# Needs npm >= 11.10.0 for --min-release-age.
set -euo pipefail

COOLDOWN_DAYS="${COOLDOWN_DAYS:-2}"
REGISTRY="https://registry.npmjs.org/"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <version> [<version> ...]" >&2
  exit 2
fi

node -e '
  const [maj, min] = process.argv[1].split(".").map(Number);
  if (maj < 11 || (maj === 11 && min < 10)) {
    console.error(`npm ${process.argv[1]} is too old; need >= 11.10.0 for --min-release-age.`);
    process.exit(1);
  }
' "$(npm -v)"

for VERSION in "$@"; do
  if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: '${VERSION}' is not an exact x.y.z version" >&2
    exit 2
  fi

  DEST="${ROOT}/lockfiles/${VERSION}"
  if [ -e "${DEST}" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "skip: ${VERSION} already has a lockfile (FORCE=1 to regenerate)"
    continue
  fi

  WORK="$(mktemp -d)"
  trap 'rm -rf "${WORK}"' EXIT

  cat > "${WORK}/package.json" <<EOF
{
  "name": "bruno-cli-${VERSION}",
  "private": true,
  "dependencies": {
    "@usebruno/cli": "${VERSION}"
  }
}
EOF

  echo "::group::Lock @usebruno/cli@${VERSION}"
  (
    cd "${WORK}"
    npm install --package-lock-only --ignore-scripts --no-audit --no-fund \
      --registry="${REGISTRY}" --min-release-age="${COOLDOWN_DAYS}"
  )
  echo "::endgroup::"

  # Sanity checks: right CLI version, and every package comes from the public
  # registry (no git/tarball/file sources that scanners can't see).
  node -e '
    const lock = require(process.argv[1]);
    const want = process.argv[2];
    const pkgs = lock.packages;
    const got = pkgs["node_modules/@usebruno/cli"]?.version;
    if (got !== want) {
      console.error(`expected @usebruno/cli ${want} in lockfile, got ${got}`);
      process.exit(1);
    }
    const bad = Object.entries(pkgs)
      .filter(([k, v]) => k && !v.link && !String(v.resolved).startsWith("https://registry.npmjs.org/"))
      .map(([k]) => k);
    if (bad.length) {
      console.error("non-registry packages:\n  " + bad.join("\n  "));
      process.exit(1);
    }
    console.log(`locked @usebruno/cli ${want}: ${Object.keys(pkgs).length - 1} packages`);
  ' "${WORK}/package-lock.json" "${VERSION}"

  mkdir -p "${DEST}"
  cp "${WORK}/package.json" "${WORK}/package-lock.json" "${DEST}/"
  rm -rf "${WORK}"
  trap - EXIT
done
