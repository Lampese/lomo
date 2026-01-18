'use strict';

const { execSync } = require('child_process');
const path = require('path');
const {
  LoroDoc,
  LoroList,
  LoroMap,
} = require('loro-crdt');

function parseHexOutput(output) {
  const lines = output.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  let updates = null;
  let snapshot = null;
  for (const line of lines) {
    if (line.startsWith('updates ')) {
      updates = line.slice('updates '.length);
    } else if (line.startsWith('snapshot ')) {
      snapshot = line.slice('snapshot '.length);
    }
  }
  if (!updates || !snapshot) {
    throw new Error('missing updates or snapshot output');
  }
  return {
    updates: Buffer.from(updates, 'hex'),
    snapshot: Buffer.from(snapshot, 'hex'),
  };
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

function buildExpectedDoc() {
  const doc = new LoroDoc();
  doc.setPeerId(1);

  const root = doc.getMap('root');
  root.set('title', 'Loro');
  const items = root.setContainer('items', new LoroList());
  items.insert(0, 1);
  items.insert(1, 'two');

  const list = doc.getList('list');
  list.insert(0, 'a');
  list.insert(1, 'b');
  const nested = list.insertContainer(1, new LoroMap());
  nested.set('nested', true);
  list.delete(2, 1);
  list.insert(2, 'b2');
  list.delete(0, 1);

  const mlist = doc.getMovableList('mlist');
  mlist.insert(0, 'm1');
  mlist.insert(1, 'm2');
  mlist.move(0, 1);
  mlist.set(1, 'm1x');
  mlist.delete(0, 1);

  const text = doc.getText('text');
  text.insert(0, 'Hello world');
  text.mark({ start: 0, end: 5 }, 'bold', true);
  text.delete(5, 1);

  const tree = doc.getTree('tree');
  const root1 = tree.createNode();
  const root2 = tree.createNode();
  const child = root1.createNode();
  child.data.set('name', 'child');
  tree.move(child.id, root2.id);
  tree.delete(root1.id);

  const counter = doc.getCounter('counter');
  counter.increment(2);
  counter.increment(3);

  return doc;
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

function main() {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const output = execSync('moon run cmd/compat_export', {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  const { updates, snapshot } = parseHexOutput(output);

  const expectedDoc = buildExpectedDoc();
  const expected = expectedDoc.toJSON();

  const docUpdates = new LoroDoc();
  docUpdates.import(new Uint8Array(updates));
  checkMatch('updates', expected, docUpdates.toJSON());

  const docSnapshot = new LoroDoc();
  docSnapshot.import(new Uint8Array(snapshot));
  checkMatch('snapshot', expected, docSnapshot.toJSON());

  console.log('compat check ok');
}

main();
