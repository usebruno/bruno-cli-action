#!/usr/bin/env node
'use strict';

// Parse the JUnit XML emitted by `bru run`, write four step outputs:
// passed, failed, total, duration-ms.
//
// Counts come from <testsuite> elements (one per request in Bruno's JUnit
// output), not <testcase> elements (one per assertion / test block). PRD
// outputs are request-level.

const fs = require('fs');

const junitPath = process.env.JUNIT_PATH;
const ghOutput = process.env.GITHUB_OUTPUT;

if (!junitPath) {
  console.error('::error::JUNIT_PATH env var missing.');
  process.exit(2);
}

function writeOutput(key, value) {
  if (!ghOutput) return;
  fs.appendFileSync(ghOutput, `${key}=${value}\n`);
}

function emitEmpty(reason) {
  console.error(`::warning::${reason}`);
  writeOutput('passed', '0');
  writeOutput('failed', '0');
  writeOutput('total', '0');
  writeOutput('duration-ms', '0');
}

if (!fs.existsSync(junitPath)) {
  emitEmpty(`JUnit XML not found at \`${junitPath}\`. Did bru crash before writing the report?`);
  process.exit(0);
}

const xml = fs.readFileSync(junitPath, 'utf8');

function attr(attrs, name) {
  const re = new RegExp(`(?:^|\\s)${name}\\s*=\\s*"([^"]*)"`);
  const found = attrs.match(re);
  return found ? found[1] : null;
}

const suiteOpenRe = /<testsuite\b[^>]*>/g;
let total = 0;
let failed = 0;
let timeSeconds = 0;
let m;
while ((m = suiteOpenRe.exec(xml)) !== null) {
  const tag = m[0];
  total += 1;
  const failures = Number(attr(tag, 'failures') || 0);
  const errors = Number(attr(tag, 'errors') || 0);
  if (failures > 0 || errors > 0) failed += 1;
  timeSeconds += Number(attr(tag, 'time') || 0);
}

const passed = total - failed;
const durationMs = Math.round(timeSeconds * 1000);

writeOutput('passed', String(passed));
writeOutput('failed', String(failed));
writeOutput('total', String(total));
writeOutput('duration-ms', String(durationMs));

console.log(`Parsed JUnit: passed=${passed} failed=${failed} total=${total} duration-ms=${durationMs}`);
