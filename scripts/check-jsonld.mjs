#!/usr/bin/env node
// Validate the JSON-LD block(s) embedded in an HTML file.
// Usage: node scripts/check-jsonld.mjs <html-file>
import { readFileSync } from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/check-jsonld.mjs <html-file>');
  process.exit(2);
}

const html = readFileSync(file, 'utf8');
const re = /<script type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g;
let m;
let found = 0;
while ((m = re.exec(html)) !== null) {
  found++;
  const data = JSON.parse(m[1]); // throws on invalid JSON
  const types = Array.isArray(data['@type']) ? data['@type'] : [data['@type']];
  if (!types.includes('ProfilePage') && !types.includes('Person')) {
    throw new Error(`unexpected @type in ${file}: ${types.join(',')}`);
  }
  if (!data.mainEntity && data['@type'] !== 'Person') {
    throw new Error('ProfilePage without mainEntity');
  }
  console.log(`OK: ${file} JSON-LD #${found} (${types.join(', ')}) valid`);
}
if (found === 0) {
  console.error(`FAIL: no JSON-LD block found in ${file}`);
  process.exit(1);
}
