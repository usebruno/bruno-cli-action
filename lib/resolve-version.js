// Resolve a bru-version spec (exact version, range or dist-tag) to a concrete
// @usebruno/cli version, honouring a release-age cooldown, and report whether
// that version has a committed lockfile.
//
//   npm view @usebruno/cli versions time dist-tags --json |
//     node resolve-version.js <spec> <cooldown-days> <lockfiles-dir>
//
// Prints "<version> locked" or "<version> unlocked". Exits 1 with an
// ::error:: annotation when nothing matches.
'use strict';

const fs = require('fs');
const path = require('path');
const semver = require('semver');

const [spec, cooldownArg, lockRoot] = process.argv.slice(2);
const cooldownDays = Number(cooldownArg);

function fail(message) {
  console.log(`::error::${message}`);
  process.exit(1);
}

if (!Number.isInteger(cooldownDays) || cooldownDays < 0) {
  fail(`cooldown-days must be a non-negative integer, got '${cooldownArg}'.`);
}

const meta = JSON.parse(fs.readFileSync(0, 'utf8'));
const distTags = meta['dist-tags'] || {};
const cutoff = Date.now() - cooldownDays * 864e5;
const allVersions = meta.versions || [];
const pastCooldown = allVersions.filter((v) => Date.parse(meta.time[v]) <= cutoff);

// Mirrors npm: a dist-tag picks the tagged version, or with a date filter the
// newest version <= the tag. A range prefers the `latest` tag when it
// satisfies, otherwise the highest satisfying version.
function pick(candidates) {
  if (Object.prototype.hasOwnProperty.call(distTags, spec)) {
    const tagged = distTags[spec];
    const allowPre = semver.prerelease(tagged) !== null;
    const eligible = candidates.filter(
      (v) => semver.lte(v, tagged) && (allowPre || semver.prerelease(v) === null),
    );
    return semver.rsort(eligible)[0] || null;
  }
  const range = semver.validRange(spec);
  if (range === null) {
    fail(`bru-version '${spec}' is not a version, range or dist-tag of @usebruno/cli.`);
  }
  const latest = distTags.latest;
  if (latest && candidates.includes(latest) && semver.satisfies(latest, range)) {
    return latest;
  }
  return semver.maxSatisfying(candidates, range);
}

const version = pick(pastCooldown);
if (!version) {
  const ignoringCooldown = pick(allVersions);
  if (ignoringCooldown) {
    fail(
      `@usebruno/cli@${spec} resolves to ${ignoringCooldown}, published less than ` +
        `${cooldownDays} day(s) ago. Wait for the cooldown or lower cooldown-days.`,
    );
  }
  fail(`No @usebruno/cli version matches '${spec}'.`);
}

const locked =
  /^\d+\.\d+\.\d+$/.test(version) &&
  fs.existsSync(path.join(lockRoot, version, 'package-lock.json'));

console.log(`${version} ${locked ? 'locked' : 'unlocked'}`);
