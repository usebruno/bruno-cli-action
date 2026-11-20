#!/usr/bin/env bash
# Print stable @usebruno/cli versions >= MIN_VERSION (default 3.0.0) that
# have no lockfiles/<version>/ directory and were published at least
# COOLDOWN_DAYS ago (default 2), oldest first. This includes backports to
# older lines (e.g. 3.5.4 after 4.3.0). Older majors are locked selectively
# by hand, so they are not proposed automatically.
set -euo pipefail

COOLDOWN_DAYS="${COOLDOWN_DAYS:-2}"
MIN_VERSION="${MIN_VERSION:-3.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

npm view @usebruno/cli time --json --registry=https://registry.npmjs.org/ |
  node -e '
    const fs = require("fs");
    const path = require("path");
    const [days, min, dir] = [Number(process.argv[1]), process.argv[2], process.argv[3]];
    const times = JSON.parse(fs.readFileSync(0, "utf8"));
    const isStable = (v) => /^\d+\.\d+\.\d+$/.test(v);
    const cmp = (a, b) => {
      const x = a.split(".").map(Number), y = b.split(".").map(Number);
      return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
    };
    const cutoff = Date.now() - days * 864e5;
    Object.keys(times)
      .filter(isStable)
      .filter((v) => cmp(v, min) >= 0)
      .filter((v) => Date.parse(times[v]) <= cutoff)
      .filter((v) => !fs.existsSync(path.join(dir, v)))
      .sort(cmp)
      .forEach((v) => console.log(v));
  ' "${COOLDOWN_DAYS}" "${MIN_VERSION}" "${ROOT}/lockfiles"
