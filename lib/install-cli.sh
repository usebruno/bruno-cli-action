#!/usr/bin/env bash
set -euo pipefail

VERSION="${BRU_VERSION:-latest}"

echo "::group::Install @usebruno/cli@${VERSION}"
npm install -g "@usebruno/cli@${VERSION}"
bru --version
echo "::endgroup::"
