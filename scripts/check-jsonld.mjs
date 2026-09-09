#!/usr/bin/env node
// Validate the JSON-LD block(s) embedded in an HTML file, and verify the CSP
// hash that pins them.
//
// The strict CSP in site/_headers allows inline scripts only via
// 'sha256-...'. If the JSON-LD changes without updating that hash, Chrome
// silently refuses the block — so this check fails loudly instead.
//
// Usage: node scripts/check-jsonld.mjs <html-file> [headers-file]
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/check-jsonld.mjs <html-file> [headers-file]');
  process.exit(2);
}
const headersFile = process.argv[3] || join(dirname(file), '_headers');

const html = readFileSync(file, 'utf8');
const headers = readFileSync(headersFile, 'utf8');
const re = /<script type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g;
let m;
let found = 0;

while ((m = re.exec(html)) !== null) {
  found++;
  const source = m[1];
  const data = JSON.parse(source); // throws on invalid JSON
  const types = Array.isArray(data['@type']) ? data['@type'] : [data['@type']];
  if (!types.includes('ProfilePage') && !types.includes('Person')) {
    throw new Error(`unexpected @type in ${file}: ${types.join(',')}`);
  }
  if (!data.mainEntity && data['@type'] !== 'Person') {
    throw new Error('ProfilePage without mainEntity');
  }

  // CSP hashes are computed over the element's exact text content.
  const hash = createHash('sha256').update(source, 'utf8').digest('base64');
  if (!headers.includes(`'sha256-${hash}'`)) {
    console.error(
      `FAIL: ${file} JSON-LD #${found} is not pinned by the CSP in ${headersFile}.\n` +
      `      Expected script-src to contain: 'sha256-${hash}'`
    );
    process.exit(1);
  }
  console.log(`OK: ${file} JSON-LD #${found} (${types.join(', ')}) valid + CSP hash matches`);
}

if (found === 0) {
  console.error(`FAIL: no JSON-LD block found in ${file}`);
  process.exit(1);
}
