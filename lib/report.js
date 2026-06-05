#!/usr/bin/env node
'use strict';

// Parse the JUnit XML emitted by `bru run`, write four step outputs:
// passed, failed, total, duration-ms.
//
// Counts come from <testsuite> elements (one per request in Bruno's JUnit
// output), not <testcase> elements (one per assertion / test block). PRD
// outputs are request-level.
//
// Uses fast-xml-parser, installed into the action's own node_modules at
// runtime by the "Install action dependencies" step in action.yml. Resolved
// from the action root so the consumer's cwd / NODE_PATH don't matter.

const fs = require('fs');
const path = require('path');

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

const actionRoot = path.resolve(__dirname, '..');
let XMLParser;
try {
  ({ XMLParser } = require(path.join(actionRoot, 'node_modules', 'fast-xml-parser')));
} catch (err) {
  console.error('::error::fast-xml-parser is not installed. The "Install action dependencies" step must run before this.');
  process.exit(2);
}

const xml = fs.readFileSync(junitPath, 'utf8');
const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
});
const data = parser.parse(xml);

// Bruno wraps suites in <testsuites>. fast-xml-parser returns the inner
// <testsuite> as a single object when there is one suite, or an array when
// there are multiple. Normalise to an array.
let suites = data && data.testsuites && data.testsuites.testsuite;
if (!suites) suites = [];
if (!Array.isArray(suites)) suites = [suites];

let failed = 0;
let timeSeconds = 0;
for (const s of suites) {
  if (!s) continue;
  const failures = Number(s['@_failures'] || 0);
  const errors = Number(s['@_errors'] || 0);
  if (failures > 0 || errors > 0) failed += 1;
  timeSeconds += Number(s['@_time'] || 0);
}

const total = suites.length;
const passed = total - failed;
const durationMs = Math.round(timeSeconds * 1000);

writeOutput('passed', String(passed));
writeOutput('failed', String(failed));
writeOutput('total', String(total));
writeOutput('duration-ms', String(durationMs));

console.log(`Parsed JUnit: passed=${passed} failed=${failed} total=${total} duration-ms=${durationMs}`);
