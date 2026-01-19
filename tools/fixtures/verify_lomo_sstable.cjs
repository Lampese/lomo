'use strict';

const { execSync } = require('child_process');
const path = require('path');
const { LoroDoc } = require('loro-crdt');

function parseSnapshot(output) {
  const lines = output.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  for (const line of lines) {
    if (line.startsWith('snapshot_large ')) {
      const hex = line.slice('snapshot_large '.length);
      return Buffer.from(hex, 'hex');
    }
  }
  throw new Error('missing snapshot_large output');
}

function normalize(value) {
  if (value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(normalize);
  }
  if (typeof value === 'object') {
    const out = {};
    const keys = Object.keys(value).sort();
    for (const key of keys) {
      out[key] = normalize(value[key]);
    }
    return out;
  }
  return value;
}

function checkMatch(label, expected, actual) {
  const exp = normalize(expected);
  const act = normalize(actual);
  const expText = JSON.stringify(exp);
  const actText = JSON.stringify(act);
  if (expText !== actText) {
    throw new Error(`${label} mismatch`);
  }
}

function buildExpectedDoc() {
  const doc1 = new LoroDoc();
  doc1.setPeerId(1);
  const root1 = doc1.getMap('root');
  const big = 'a'.repeat(1500);
  root1.set('p1', big);

  const doc2 = new LoroDoc();
  doc2.setPeerId(2);
  const root2 = doc2.getMap('root');
  root2.set('p2', big);

  doc2.import(doc1.export({ mode: 'update' }));
  doc1.import(doc2.export({ mode: 'update' }));
  return doc1;
}

function main() {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const output = execSync('moon run cmd/compat_export_large', {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  const snapshot = parseSnapshot(output);
  const expectedDoc = buildExpectedDoc();
  const expected = expectedDoc.toJSON();

  const docSnapshot = new LoroDoc();
  docSnapshot.import(new Uint8Array(snapshot));
  checkMatch('snapshot_large', expected, docSnapshot.toJSON());

  console.log('sstable compat check ok');
  process.exit(0);
}

main();
