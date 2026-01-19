'use strict';

const fs = require('fs');
const path = require('path');
const { Awareness } = require('loro-crdt');

const OUT_PATH = path.resolve(__dirname, '..', '..', 'awareness_fixtures.mbt');

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

function encodeSingle(peerId, state) {
  const awareness = new Awareness(peerId);
  awareness.setLocalState(state);
  return awareness.encodeAll();
}

function encodeMulti() {
  const a1 = new Awareness(1);
  const a2 = new Awareness(2);
  a1.setLocalState({ a: 1 });
  a2.setLocalState({ b: 2 });
  a1.apply(a2.encodeAll());
  return a1.encodeAll();
}

function main() {
  const simpleState = {
    n: null,
    b: true,
    i: 1,
    f: 1.5,
    s: 'hi',
    bin: new Uint8Array([1, 2, 3]),
    list: [1, 'a', false],
    map: { k: 'v' },
  };

  const simple = encodeSingle(1, simpleState);
  const multi = encodeMulti();

  const peerV1 = encodeSingle(1, { v: 1 });
  const peerV2 = (() => {
    const awareness = new Awareness(1);
    awareness.setLocalState({ v: 1 });
    awareness.setLocalState({ v: 2 });
    return awareness.encodeAll();
  })();

  const blocks = [
    renderBytesConst(
      'awareness_fixture_simple',
      simple,
      'Generated via loro-crdt Awareness for mixed value types.',
    ),
    renderBytesConst(
      'awareness_fixture_multi',
      multi,
      'Generated via loro-crdt Awareness with two peers.',
    ),
    renderBytesConst(
      'awareness_fixture_peer_v1',
      peerV1,
      'Generated via loro-crdt Awareness peer=1 clock=1.',
    ),
    renderBytesConst(
      'awareness_fixture_peer_v2',
      peerV2,
      'Generated via loro-crdt Awareness peer=1 clock=2.',
    ),
  ];

  fs.writeFileSync(OUT_PATH, `${blocks.join('\n')}`, 'utf8');
  console.log(`Wrote fixtures to ${OUT_PATH}`);
  process.exit(0);
}

main();
