#!/usr/bin/env node
'use strict';

// Parses the JUnit XML emitted by `bru run`, writes step outputs (passed,
// failed, total, duration-ms), appends a markdown summary table to
// $GITHUB_STEP_SUMMARY, and emits ::error:: annotations so failures appear
// inline on the PR's Files Changed tab. Zero npm deps — regex scan over the
// JUnit envelope, which is stable enough for our needs.
//
// Counts come from <testsuite> elements (one per request in Bruno's JUnit
// output), not <testcase> elements (one per assertion or test block). Matches
// the request-level semantics the PRD requires.

const fs = require('fs');
const path = require('path');

const junitPath = process.env.JUNIT_PATH;
const ghOutput = process.env.GITHUB_OUTPUT;
const ghSummary = process.env.GITHUB_STEP_SUMMARY;
const ghWorkspace = process.env.GITHUB_WORKSPACE;

if (!junitPath) {
  console.error('::error::JUNIT_PATH env var missing.');
  process.exit(2);
}

function writeOutput(key, value) {
  if (!ghOutput) return;
  fs.appendFileSync(ghOutput, `${key}=${value}\n`);
}

function appendSummary(text) {
  if (!ghSummary) return;
  fs.appendFileSync(ghSummary, text);
}

function emitEmpty(reason) {
  console.error(`::warning::${reason}`);
  writeOutput('passed', '0');
  writeOutput('failed', '0');
  writeOutput('total', '0');
  writeOutput('duration-ms', '0');
  appendSummary(`### Bruno run\n\n${reason}\n`);
}

if (!fs.existsSync(junitPath)) {
  emitEmpty(`JUnit XML not found at \`${junitPath}\`. Did bru crash before writing the report?`);
  process.exit(0);
}

const xml = fs.readFileSync(junitPath, 'utf8');

function decode(s) {
  return String(s)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function attr(attrs, name) {
  const re = new RegExp(`(?:^|\\s)${name}\\s*=\\s*"([^"]*)"`);
  const found = attrs.match(re);
  return found ? decode(found[1]) : null;
}

const suiteRe = /<testsuite\b([^>]*?)(\/>|>([\s\S]*?)<\/testsuite>)/g;
const suites = [];
let m;
while ((m = suiteRe.exec(xml)) !== null) {
  const attrs = m[1];
  const body = m[3] || '';
  const name = attr(attrs, 'name') || 'request';
  const file = attr(attrs, 'file') || '';
  const failures = Number(attr(attrs, 'failures') || 0);
  const errors = Number(attr(attrs, 'errors') || 0);
  const time = Number(attr(attrs, 'time') || 0);
  const isFail = failures > 0 || errors > 0;
  let firstFailureMessage = '';
  if (isFail) {
    const fm = body.match(/<(failure|error)\b([^>]*?)(\/>|>([\s\S]*?)<\/\1>)/);
    if (fm) {
      const failureAttrs = fm[2];
      const failureBody = fm[4] || '';
      firstFailureMessage = attr(failureAttrs, 'message')
        || decode(failureBody).trim().split('\n')[0]
        || (errors > 0 ? 'request errored' : 'assertion failed');
    }
  }
  suites.push({ name, file, time, isFail, firstFailureMessage });
}

const total = suites.length;
const failed = suites.filter(s => s.isFail).length;
const passed = total - failed;
const durationMs = Math.round(suites.reduce((acc, s) => acc + s.time, 0) * 1000);

writeOutput('passed', String(passed));
writeOutput('failed', String(failed));
writeOutput('total', String(total));
writeOutput('duration-ms', String(durationMs));

const rows = suites.map(s => {
  const label = s.file || s.name;
  const status = s.isFail ? '❌' : '✅';
  const ms = Math.round(s.time * 1000);
  return `| ${label} | ${status} | ${ms} ms |`;
});

let summary = '### Bruno run\n\n';
summary += '| Request | Status | Duration |\n';
summary += '|---------|--------|----------|\n';
summary += rows.length ? rows.join('\n') + '\n' : '| _no requests_ | — | — |\n';
summary += `\n**Total: ${passed} passed, ${failed} failed (of ${total}) — ${durationMs} ms**\n`;
appendSummary(summary);

function annotationFile(f) {
  if (!f) return '';
  if (!ghWorkspace) return f;
  const abs = path.isAbsolute(f) ? f : path.resolve(process.cwd(), f);
  const rel = path.relative(ghWorkspace, abs);
  return rel && !rel.startsWith('..') ? rel : f;
}

const encAttr = (s) => String(s)
  .replace(/%/g, '%25')
  .replace(/\r/g, '%0D')
  .replace(/\n/g, '%0A')
  .replace(/:/g, '%3A')
  .replace(/,/g, '%2C');

const encMsg = (s) => String(s)
  .replace(/%/g, '%25')
  .replace(/\r/g, '%0D')
  .replace(/\n/g, '%0A');

for (const s of suites) {
  if (!s.isFail) continue;
  const file = annotationFile(s.file);
  const title = s.name || s.file || 'Bruno failure';
  const msg = s.firstFailureMessage || 'failed';
  const filePart = file ? `file=${encAttr(file)},` : '';
  console.log(`::error ${filePart}title=${encAttr(title)}::${encMsg(msg)}`);
}

console.log(`Parsed JUnit: passed=${passed} failed=${failed} total=${total} duration-ms=${durationMs}`);
