'use strict';

const fs = require('fs');
const path = require('path');
const {
  LoroDoc,
  LoroText,
  LoroList,
  LoroMap,
  LoroMovableList,
  LoroTree,
  LoroCounter,
} = require('loro-crdt');

const OUT_PATH = path.resolve(__dirname, '..', '..', 'loro_fixtures.mbt');

function configTextStyles(doc) {
  doc.configTextStyle({
    bold: { expand: 'after' },
    link: { expand: 'none' },
  });
}

function addLargeData(doc) {
  const bigMap = doc.getMap('big_map');
  for (let i = 0; i < 200; i += 1) {
    bigMap.set(`k${i}`, `v${i}`);
  }
  const bigMapText = bigMap.setContainer('notes', new LoroText());
  bigMapText.insert(0, 'big map notes');

  const bigList = doc.getList('big_list');
  for (let i = 0; i < 200; i += 1) {
    bigList.insert(i, `item-${i}`);
  }
  const bigListMeta = bigList.insertContainer(100, new LoroMap());
  bigListMeta.set('seed', 'ok');
  bigList.delete(120, 5);
  bigList.insert(120, 'item-120b');

  const bigText = doc.getText('big_text');
  const blocks = [];
  for (let i = 0; i < 200; i += 1) {
    blocks.push(`block-${i}: ${'x'.repeat(40)}\n`);
  }
  bigText.insert(0, blocks.join(''));
  bigText.mark({ start: 0, end: 12 }, 'bold', true);

  const bigTree = doc.getTree('big_tree');
  bigTree.disableFractionalIndex();
  const bigRoot = bigTree.createNode();
  bigRoot.data.set('title', 'BigRoot');
  for (let i = 0; i < 10; i += 1) {
    const child = bigRoot.createNode();
    child.data.set('title', `Node ${i}`);
    for (let j = 0; j < 5; j += 1) {
      const leaf = child.createNode();
      leaf.data.set('title', `Node ${i}.${j}`);
    }
  }
}

function buildMergedDoc() {
  const doc1 = new LoroDoc();
  doc1.setPeerId(1);
  configTextStyles(doc1);

  const profile = doc1.getMap('profile');
  profile.set('name', 'Ada');
  profile.set('role', 'writer');
  profile.set('active', true);

  const tags = profile.setContainer('tags', new LoroList());
  tags.insert(0, 'crdt');
  tags.insert(1, 'moonbit');

  const bio = profile.setContainer('bio', new LoroText());
  bio.insert(0, 'loro');

  const items = doc1.getList('items');
  items.insert(0, 'alpha');
  items.insert(1, 'beta');
  items.delete(1, 1);
  items.insert(1, 'gamma');
  const listText = items.insertContainer(2, new LoroText());
  listText.insert(0, 'list text');
  const listMap = items.insertContainer(3, new LoroMap());
  listMap.set('k', 'v');

  const note = doc1.getText('note');
  note.insert(0, 'Hello World!');
  note.mark({ start: 0, end: 5 }, 'bold', true);
  note.mark({ start: 6, end: 11 }, 'link', 'https://example.com');
  note.unmark({ start: 2, end: 4 }, 'bold');
  note.delete(11, 1);
  note.insert(11, ' 世界');

  const movable = doc1.getMovableList('movable');
  movable.insert(0, 'a');
  movable.insert(1, 'b');
  movable.insert(2, 'c');
  const movableNested = movable.insertContainer(3, new LoroList());
  movableNested.insert(0, 'nested');
  movable.move(2, 0);
  movable.set(1, 'alpha');
  movable.delete(2, 1);

  const tree = doc1.getTree('outline');
  const root = tree.createNode();
  root.data.set('title', 'Root');
  const childA = root.createNode();
  childA.data.set('title', 'A');
  const childB = root.createNode();
  childB.data.set('title', 'B');
  const sub = childA.createNode();
  sub.data.set('title', 'A1');
  const treeTags = childA.data.setContainer('tags', new LoroList());
  treeTags.insert(0, 'x');
  treeTags.insert(1, 'y');
  tree.move(childB.id, root.id, 0);

  const counter = doc1.getCounter('counter');
  counter.increment(3);
  counter.decrement(1);

  addLargeData(doc1);

  const doc2 = new LoroDoc();
  doc2.setPeerId(2);
  configTextStyles(doc2);

  const peer2Map = doc2.getMap('peer2_map');
  peer2Map.set('status', 'online');
  const peer2Notes = peer2Map.setContainer('notes', new LoroText());
  peer2Notes.insert(0, 'hi from peer2');

  const peer2List = doc2.getList('peer2_list');
  peer2List.insert(0, 'p2');

  const peer2Text = doc2.getText('peer2_text');
  peer2Text.insert(0, 'peer2');

  const peer2Counter = doc2.getCounter('peer2_counter');
  peer2Counter.increment(4);

  doc2.import(doc1.export({ mode: 'update' }));
  doc1.import(doc2.export({ mode: 'update' }));

  return doc1;
}

function toHexArray(bytes) {
  const lines = [];
  const width = 16;
  for (let i = 0; i < bytes.length; i += width) {
    const slice = bytes.slice(i, i + width);
    const items = [];
    for (const value of slice) {
      items.push(`0x${value.toString(16).padStart(2, '0')}`);
    }
    lines.push(`  ${items.join(', ')}`);
  }
  return `[\n${lines.join(',\n')}\n]`;
}

function renderBytesConst(name, bytes, comment) {
  const header = comment ? `// ${comment}\n` : '';
  return `///|\n${header}pub let ${name} : Bytes = ${toHexArray(bytes)}\n`;
}

function main() {
  const doc = buildMergedDoc();
  const update = doc.export({ mode: 'update' });
  const snapshot = doc.export({ mode: 'snapshot' });
  const shallow = doc.export({
    mode: 'shallow-snapshot',
    frontiers: doc.oplogFrontiers(),
  });

  const blocks = [
    renderBytesConst(
      'loro_fixture_updates',
      update,
      'Generated via loro-crdt export({ mode: "update" }).',
    ),
    renderBytesConst(
      'loro_fixture_snapshot',
      snapshot,
      'Generated via loro-crdt export({ mode: "snapshot" }).',
    ),
    renderBytesConst(
      'loro_fixture_shallow_snapshot',
      shallow,
      'Generated via loro-crdt export({ mode: "shallow-snapshot" }).',
    ),
  ];

  fs.writeFileSync(OUT_PATH, `${blocks.join('\n')}`, 'utf8');
  console.log(`Wrote fixtures to ${OUT_PATH}`);
}

main();
