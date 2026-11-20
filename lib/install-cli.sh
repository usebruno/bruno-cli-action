#!/usr/bin/env bash
set -euo pipefail

VERSION="${BRU_VERSION:-latest}"
COOLDOWN_DAYS="${COOLDOWN_DAYS:-2}"

echo "::group::Install @usebruno/cli@${VERSION}"
npm install -g --min-release-age="${COOLDOWN_DAYS}" "@usebruno/cli@${VERSION}"
bru --version
echo "::endgroup::"
