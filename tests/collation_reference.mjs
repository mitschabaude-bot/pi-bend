// Differential corpus for runtime/collation.bend: records pi's reference
// String.prototype.localeCompare signs under Node's ICU (en-US, defaults).
// Usage: node tests/collation_reference.mjs <pairs.tsv> <sort.tsv>
// Strings are written as space-separated hex code points; lone surrogates are
// ordinary code points on the Bend side.
import fs from 'node:fs';

const expected = { icu: '78.3', unicode: '17.0', cldr: '48.0' };
for (const key of Object.keys(expected)) {
  if (process.versions[key] !== expected[key]) throw Error(`reference ${key} ${process.versions[key]} != ${expected[key]}`);
}
if (new Intl.Collator().resolvedOptions().locale !== 'en-US') throw Error('default locale must be en-US (run with LANG=en_US.UTF-8)');
const collator = new Intl.Collator('en-US');

let seed = 0x5eed1234;
const random = () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const int = (n) => Math.floor(random() * n);
const pick = (values) => values[int(values.length)];
const str = (cp) => String.fromCodePoint(cp);
const word = (alphabet, min, max) => {
  let out = '';
  for (let n = min + int(max - min + 1); n > 0; n--) out += pick(alphabet);
  return out;
};
const hex = (text) => Array.from(text, (c) => c.codePointAt(0).toString(16).toUpperCase()).join(' ');

const pairs = [];
const add = (a, b, bendA = hex(a), bendB = hex(b)) => {
  const sign = Math.sign(a.localeCompare(b));
  if (Math.sign(collator.compare(a, b)) !== sign || Math.sign(b.localeCompare(a)) !== -sign) throw Error('inconsistent reference');
  pairs.push(`${bendA}\t${bendB}\t${sign}`);
};
const assigned = (cp) => !/\p{Cn}/u.test(str(cp));

// Every BMP code point (assigned or not, surrogates and noncharacters too)
// against its code-point neighbour, then against its collation neighbour.
const bmp = [];
for (let cp = 0; cp < 0x10000; cp++) bmp.push(str(cp));
for (let cp = 0; cp < 0xffff; cp++) add(bmp[cp], bmp[cp + 1]);
const sortedBmp = [...bmp].sort(collator.compare);
for (let i = 0; i + 1 < sortedBmp.length; i++) add(sortedBmp[i], sortedBmp[i + 1]);

// Assigned supplementary code points with explicit weights, every one; the
// implicit-weight blocks (Han, Tangut, Khitan, Nushu) are sampled.
const implicitBlock = (cp) => /\p{Unified_Ideograph}|\p{Script=Tangut}|\p{Script=Nushu}|\p{Script=Khitan_Small_Script}/u.test(str(cp));
const supplementary = [];
for (let cp = 0x10000; cp < 0x110000; cp++) {
  if (assigned(cp) && (!implicitBlock(cp) || cp % 61 === 0 || int(97) === 0)) supplementary.push(str(cp));
}
const sortedSupplementary = supplementary.sort(collator.compare);
for (let i = 0; i + 1 < sortedSupplementary.length; i++) add(sortedSupplementary[i], sortedSupplementary[i + 1]);

// Whole code space samples: unassigned planes, private use, noncharacters,
// lone surrogates, Han core/extension, Tangut/Nushu/Khitan boundaries.
const edges = [0, 0x7f, 0x80, 0xd7ff, 0xd800, 0xdbff, 0xdc00, 0xdfff, 0xe000, 0xf8ff, 0xf900, 0xfa0e, 0xfa6d, 0xfdd0, 0xfdef, 0xfffd, 0xfffe, 0xffff,
  0x10000, 0x1fffe, 0x1ffff, 0x17000, 0x187ff, 0x18800, 0x18aff, 0x18b00, 0x18cff, 0x18d00, 0x18d08, 0x18d09, 0x18d7f, 0x18d80, 0x1b170, 0x1b2fb, 0x1b2fc,
  0x3400, 0x4dbf, 0x4dc0, 0x4e00, 0x9fff, 0x20000, 0x2a6df, 0x2a6e0, 0x2ebe0, 0x2ee5d, 0x2ee5e, 0x30000, 0x3134a, 0x31350, 0x33479, 0x3347a,
  0xe0000, 0xe0001, 0xe007f, 0xe0100, 0xe01ef, 0xeffff, 0xf0000, 0xffffd, 0x100000, 0x10fffd, 0x10ffff];
const anywhere = () => (int(4) === 0 ? pick(edges) + int(3) - 1 : int(0x110000));
const clamp = (cp) => Math.max(0, Math.min(0x10ffff, cp));
for (let i = 0; i < 12000; i++) {
  const a = clamp(anywhere()), b = clamp(int(2) ? anywhere() : a + int(5) - 2);
  add(str(a), str(b));
  add(str(a) + 'a', str(b));
  add('x' + str(a) + '\u0301', 'x' + str(b));
}
for (const a of edges) for (const b of edges) add(str(a), str(b));

// Mixed scripts, case and diacritics, digits, punctuation and symbols.
const latin = [...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', ...'\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e6\u00e7\u00e8\u00e9\u00ea\u00eb\u00ec\u00ed\u00ee\u00ef\u00f1\u00f2\u00f3\u00f4\u00f5\u00f6\u00f8\u00f9\u00fa\u00fb\u00fc\u00fd\u00ff\u00df\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00c6\u00c7\u00c8\u00c9\u00ca\u00cb\u00cc\u00cd\u00ce\u00cf\u00d1\u00d2\u00d3\u00d4\u00d5\u00d6\u00d8\u00d9\u00da\u00db\u00dc\u00dd\u0178\u0153\u0152\u0133\u0132\u01c6\u01c4\u017f\u1e9e\u00aa\u00ba'];
const marks = ['\u0300', '\u0301', '\u0302', '\u0303', '\u0308', '\u030a', '\u030c', '\u0323', '\u0327', '\u0328', '\u031b', '\u0334', '\u0345', '\u05b0', '\u0591', '\u0f71', '\u0f72', '\u0f74', '\u0f80', '\u093c', '\u094d', '\u3099', '\u1dce', '\u20d2', '\u0306', '\u0653', '\u0654', '\u0655'];
const digits = [...'0123456789\u0660\u0661\u0662\u0663\u0966\u0967\u0968\uff13\uff14\u2075\u00bd\u2460\u216b'];
const punct = [...' !"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~\u00a0\u00ad\u2010\u2013\u2014\u2026\u00b7\u0387\u3000\u200b\u200c\u200d\ufeff\t\n\r\u00a1\u00bf\u00a7\u00b6\u00a9\u00ae\u00b0\u00b1\u00d7\u00f7\u20ac\u00a3\u00a5\u20bf'];
const scripts = [...'\u03b1\u03b2\u03b3\u03b4\u03b5\u03b6\u0391\u0392\u0393\u0394\u03ac\u03ad\u03ae\u03af\u03cc\u03cd\u03ce\u03ca\u03cb\u0390\u03b0\u0430\u0431\u0432\u0433\u0434\u0435\u0451\u0436\u0437\u0438\u0439\u043a\u043b\u043c\u043d\u0418\u0419\u0438\u0419\u0490\u0491\u040e\u045e\u0407\u0457\u05d0\u05d1\u05d2\u05d3\u05d4\u0648\u062e\u062d\u062c\u062b\u062a\u0628\u0627\u0661\u0636\u0635\u0642\u0633\u0634\u0905\u0906\u0907\u0915\u0916\u0917\u0918\u0921\u093c\u0915\u094d\u0937\u0995\u0996\u0997\u09d7\u09cb\u0995\u09cb\u0995\u09cc\u0b95\u0bca\u0b95\u0bcb\u0b95\u0bcc\u0d24\u0d4a\u0d24\u0d4b\u0d24\u0d57\u0c95\u0cca\u0c95\u0ccb\u0c95\u0ccc\u0e01\u0e02\u0e04\u0e40\u0e01\u0e41\u0e01\u0e42\u0e01\u0e43\u0e01\u0e44\u0e01\u0e81\u0e82\u0ec0\u0e81\u0ec1\u0e81\u0ec2\u0e81\u0f40\u0f41\u0f42\u0fb2\u0f80\u0fb3\u0f80\u0f71\u0f71\u0f72\u0f71\u0f74\u0f40\u0fb5\uac00\uac01\uac04\uac08\uac10\u1100\u1101\uac01\u11a8\u1102\u1161\u3131\u3134\u314f\u65e5\u672c\u8a9e\u4e2d\u6587\u6f22\u5b57\u6771\u4eac\u5927\u5b66\u4f60\u597d\u4e16\u754c\u3002\u3001\u30a2\u30a4\u30a6\u30a8\u30aa\u30ab\u30ac\u30ad\u30ae\u30a2\uff71\uff76\uff9e\u30fc\u30fd\u30fe\u309d\u309e\u1b51\u1b05\u1b35\u1b06'];
const emoji = ['\u{1f600}', '\u{1f601}', '\u{1f44d}', '\u{1f44d}\u{1f3fb}', '\u{1f44d}\u{1f3ff}', '\u{1f469}', '\u{1f469}\u200d\u{1f4bb}', '\u{1f468}\u200d\u{1f469}\u200d\u{1f467}\u200d\u{1f466}', '\u{1f3f3}\ufe0f\u200d\u{1f308}', '\u{1f1e9}\u{1f1ea}', '\u{1f1fa}\u{1f1f8}', '\u{1f1e6}', '\u2764', '\u2764\ufe0f', '\u263a', '\u263a\ufe0f', '\ufe0f', '\ufe0e', '\u{1f9d1}\u{1f3fd}\u200d\u{1f680}', '\u{1fae0}', '\u{1fabf}', '#\ufe0f\u20e3', '1\ufe0f\u20e3', '\u00a9\ufe0f'];
const everything = [...latin, ...marks, ...digits, ...punct, ...scripts, ...emoji];
for (let i = 0; i < 12000; i++) {
  const a = word(everything, 0, 6);
  const mutate = int(6);
  const b = mutate === 0 ? a.toUpperCase() : mutate === 1 ? a + pick(everything) : mutate === 2 ? a.normalize(pick(['NFC', 'NFD', 'NFKC', 'NFKD'])) : mutate === 3 ? a.slice(0, int(a.length + 1)) + pick(everything) + a.slice(int(a.length + 1)) : word(everything, 0, 6);
  add(a, b);
}
for (let i = 0; i < 6000; i++) {
  const stem = word(latin, 1, 4);
  add(stem + word([...latin, ...marks], 0, 3), stem + word([...latin, ...marks], 0, 3));
  const cased = [...stem].map((c) => (int(2) ? c.toUpperCase() : c.toLowerCase())).join('');
  add(stem, cased);
  add(stem + pick(punct) + word(digits, 1, 2), stem + pick(punct) + word(digits, 1, 2));
}

// Contractions, including discontiguous matches, and canonical equivalence
// with marks in canonical and non-canonical order.
const families = [
  [...'Ll\u0130\u0131\u00b7\u0387\u0301\u0327', '\u0323'],
  [...'\u0418\u0438\u0419\u0439\u0423\u0443\u040e\u045e\u0406\u0456\u0407\u0457\u0415\u0435\u0401\u0451\u0306\u0308\u0323\u0301\u0327'],
  [...'\u0627\u0623\u0625\u0622\u0648\u0624\u064a\u0626\u0649\u0653\u0654\u0655\u064b\u0651\u0670'],
  [...'\u09c7\u09cb\u09cc\u09be\u09d7\u0995\u09bc\u09cd'], [...'\u0b47\u0b48\u0b4b\u0b4c\u0b3e\u0b56\u0b57\u0b15\u0b3c\u0b4d'], [...'\u0b92\u0b94\u0bd7\u0bc6\u0bc7\u0bca\u0bcb\u0bbe\u0b95\u0bcd'],
  [...'\u0c46\u0c47\u0c48\u0c56\u0c15\u0c3c\u0c4d'], [...'\u0cbf\u0cc0\u0cc6\u0cc7\u0cc8\u0cca\u0ccb\u0cc2\u0cd5\u0cd6\u0c95\u0cbc\u0ccd'], [...'\u0d46\u0d47\u0d4a\u0d4b\u0d4c\u0d3e\u0d57\u0d15\u0d3b\u0d4d'], [...'\u0dd9\u0dda\u0ddb\u0ddc\u0ddd\u0dde\u0dcf\u0ddf\u0dca\u0d9a\u0dca'],
  [...'\u0e40\u0e41\u0e42\u0e43\u0e44\u0e01\u0e02\u0e03\u0e04\u0e05\u0e06\u0e07\u0e08\u0e09\u0e0a\u0e0b\u0e0c\u0e0d\u0e2e\u0e30\u0e32\u0e33\u0e31\u0e34\u0e38\u0e39\u0e3a\u0e47\u0e48\u0e49\u0e4d\u0e4e'],
  [...'\u0ec0\u0ec1\u0ec2\u0ec3\u0ec4\u0e81\u0e82\u0e84\u0e87\u0e88\u0e8a\u0e8d\u0e94\u0eae\u0edc\u0edd\u0ede\u0edf\u0eb0\u0eb2\u0eb3\u0eb4\u0eb8\u0eb9\u0eba\u0ec8\u0ec9\u0ecd'],
  [...'\u0f71\u0f72\u0f73\u0f74\u0f75\u0f76\u0f77\u0f78\u0f79\u0f80\u0f81\u0fb2\u0fb3\u0f80\u0f40\u0f42\u0f40\u0fb5\u0f39\u0f7a\u0f7c\u0f82\u0f83'],
  [...'\u1025\u102e\u1026\u1000\u1037\u103a'], [...'\u19b5\u19b6\u19b7\u19ba\u1980\u1981\u1982\u1983\u1984\u1985\u19b0\u19c8'],
  [...'\u1b05\u1b07\u1b09\u1b0b\u1b0d\u1b11\u1b3a\u1b3c\u1b3e\u1b3f\u1b42\u1b35\u1b34\u1b44'], [...'\uaab5\uaab6\uaab9\uaabb\uaabc\uaa80\uaa81\uaa82\uaa83\uaa84\uaa85\uaab0\uaab2\uaab4\uaabf'],
  ['\u{105d2}', '\u{105da}', '\u0307', '\u0301', '\u0323'], ['\u{11131}', '\u{11132}', '\u{11127}', '\u{11103}', '\u{11134}'],
  ['\u{11347}', '\u{1133e}', '\u{11357}', '\u{1134b}', '\u{1133c}', '\u{1134d}'],
  ['\u{11382}', '\u{11384}', '\u{1138b}', '\u{11390}', '\u{113c2}', '\u{113c9}', '\u{113bb}', '\u{113b8}', '\u{113c5}', '\u{113ce}', '\u{113d0}'],
  ['\u{114b9}', '\u{114ba}', '\u{114b0}', '\u{114bd}', '\u{114bb}', '\u{114be}', '\u{114c2}', '\u{114c3}'],
  ['\u{115b8}', '\u{115b9}', '\u{115af}', '\u{115ba}', '\u{115bb}', '\u{115c0}'], ['\u{11935}', '\u{11930}', '\u{11938}', '\u{1193e}', '\u{11943}'],
  ['\u{1611e}', '\u{1611f}', '\u{16120}', '\u{16121}', '\u{16122}', '\u{16129}', '\u{16125}', '\u{1612f}', '\u{16126}', '\u{16127}', '\u{16128}'],
  ['\u{16d63}', '\u{16d67}', '\u{16d68}', '\u{16d69}', '\u{16d6a}', '\u{16d40}'],
  [...'\uac00\uac01\uac03\u1100\u1101\u1102\u1161\u1162\u1163\u11a8\u11a9\u11aa\u11a7\ua960\ud7b0\ud7cb\u3131\u314f\u302e\u302f'],
  [...'aeiouAEIOU\u00e7\u00c7\u0300\u0301\u0302\u0303\u0308\u0323\u0327\u0328\u031b\u0345\u0334\u0338\u05b0\u0e3a\u302a\u302b\u1dfa'],
];
for (const family of families) {
  const alphabet = [...family, 'a', 'b'];
  for (let i = 0; i < 1500; i++) {
    const a = word(alphabet, 1, 6);
    const mutate = int(4);
    const b = mutate === 0 ? a.normalize(pick(['NFC', 'NFD'])) : mutate === 1 ? [...a].reverse().join('') : mutate === 2 ? a + pick(alphabet) : word(alphabet, 1, 6);
    add(a, b);
  }
}

// Every canonical composite (supplementary ones too) followed by marks of
// low and high combining classes: FCD input, non-FCD input and its NFD.
const lowMarks = ['\u0334', '\u0f71', '\u0f72', '\u0f80', '\u05b0', '\u0327', '\u031b', '\u0323', '\u0301', '\u0345', '\u{1d165}', '\u{1d16e}', '\u093c', '\u3099', '\u{113ce}', '\u{1612f}', '\u0f74'];
for (let cp = 0xc0; cp < 0x110000; cp++) {
  if (cp >= 0xac00 && cp < 0xd7a4) continue;
  const c = str(cp), d = c.normalize('NFD');
  if (d === c) continue;
  add(c, d);
  for (const m of lowMarks) {
    if (int(3) !== 0) continue;
    add(c + m, d + m);
    add(c + m, (d + m).normalize('NFD'));
    add(m + c, m + d);
    add('a' + c + m + 'b', 'a' + c + 'b');
  }
}
for (const c of ['\u0f73', '\u0f75', '\u0f81', '\u0344', '\u0958', '\u{1d15f}', '\u{1d1bb}', '\u{1109a}', '\u{1134b}', '\u{114bc}', '\u{115ba}', '\u{11938}', '\u{113c5}', '\u{16121}', '\u{16d68}', '\u{105c9}']) {
  for (const a of lowMarks) for (const b of lowMarks) {
    add('\u0fb2' + a + c + b, '\u0fb2' + (a + c + b).normalize('NFD'));
    add(c + a + b, c + b + a);
  }
}

// ICU's alphabetic-index boundary contractions U+FDD0/U+FDD1 + first letter.
for (let i = 0; i < sortedBmp.length; i += 3) {
  add('\ufdd1' + sortedBmp[i], sortedBmp[i]);
  add('\ufdd0' + sortedBmp[i], sortedBmp[i + 1] ?? 'a');
  add('\ufdd1' + sortedBmp[i], '\ufdd0' + sortedBmp[i + 1]);
}
for (let i = 0; i < sortedSupplementary.length; i += 5) add('\ufdd1' + sortedSupplementary[i], sortedSupplementary[i]);
for (const x of ['L', 'l', 'A', 'Z', '0', '4', '\uff21', '\uff3a', '\u03a9', '\u042f', '\u05d0']) {
  for (const y of ['', '\u00b7', '\u0387', 'a', '\u0301']) {
    add('\ufdd0' + x + y, x + y);
    add('\ufdd1' + x + y, 'L\u00b7' + y);
    add('\ufdd0' + x + '\u00b7', '\ufdd0' + x + '.');
  }
}
for (const [a, b] of [['L\u00b7', 'L'], ['L\u00b7', 'L.'], ['l\u00b7l', 'll'], ['L\u0301\u00b7', 'L\u00b7'], ['\u013f', 'L\u00b7'], ['\u0140', 'l\u00b7'], ['a\u00b7', 'a'], ['L\u0387', 'L\u00b7'], ['\ufdd0L\u00b7', '\ufdd0L']]) add(a, b);

// Hangul syllables against jamo sequences and compatibility jamo.
const lead = (n) => str(0x1100 + n), vowel = (n) => str(0x1161 + n), tail = (n) => str(0x11a8 + n);
for (let i = 0; i < 4000; i++) {
  const s = 0xac00 + int(11172);
  const jamo = str(s).normalize('NFD');
  add(str(s), jamo);
  add(str(s), str(s + int(3) - 1));
  add(str(s) + lead(int(19)), jamo + pick([lead(int(19)), vowel(int(21)), tail(int(27)), str(0xa960 + int(29)), str(0xd7b0 + int(23)), str(0x3131 + int(51))]));
  add(lead(int(19)) + vowel(int(21)) + (int(2) ? tail(int(27)) : ''), str(0xac00 + int(11172)));
}

// Emoji, ZWJ sequences, modifiers, flags and keycaps.
for (let i = 0; i < 4000; i++) add(word(emoji, 1, 3), word([...emoji, ...latin.slice(0, 4)], 1, 3));

// File-name-like strings compared exactly as the ls tool does.
const stems = ['file', 'File', 'FILE', 'readme', 'README', 'index', 'a', 'b', 'z', 'Z', '_hidden', '.env', '.git', 'node_modules', 'package-lock', 'package', 'my-file', 'my_file', 'myFile', 'test', 'test-utils', 'test_utils', 'Makefile', '\u00e9clair', '\u00c9clair', '\u00fcber', 'resume', 'r\u00e9sum\u00e9', '\u65e5\u672c', 'se\u00f1or'];
const extensions = ['', '.ts', '.js', '.json', '.md', '.MD', '.tar.gz', '.d.ts', '.test.ts', '~', '.bak', '.1', '.10', '.9'];
const names = () => pick(stems) + (int(2) ? String(int(3) ? int(20) : int(1000)) : '') + pick(['', '-', '_', '.', ' ', '(1)', ' copy']) + (int(2) ? String(int(12)) : '') + pick(extensions);
for (let i = 0; i < 8000; i++) {
  const a = names(), b = names();
  add(a, b);
  add(a.toLowerCase(), b.toLowerCase());
}
for (const [a, b] of [['file9', 'file10'], ['file10', 'file9'], ['file1', 'file01'], ['a.b', 'a-b'], ['a_b', 'a-b'], ['a b', 'a-b'], ['a', 'A'], ['a', '\u00e1'], ['A', '\u00e1'], ['ab', 'Ab'], ['ab', 'aB'], ['co-op', 'coop'], ['.a', 'a'], ['_a', 'a'], ['-a', 'a'], ['1', 'a'], ['9', '10'], ['Z', 'a'], ['ch', 'cz'], ['ch', 'h'], ['ll', 'lz'], ['\u00df', 'ss'], ['\u00df', 'st'], ['\u00e6', 'ae'], ['\u0153', 'oe'], ['\u0133', 'ij'], ['\u00c5', '\u00c5'], ['\u00c5', '\u00c5']]) add(a, b);

// Empty strings, ignorables and prefixes.
const small = ['', 'a', 'A', 'ab', 'a\u0000', '\u0000', '\u0000a', '\u200b', '\u00ad', 'a\u00ad', '\u0301', 'a\u0301', '\u00e1', '\u00e4', '\ufffe', '\uffff', '\ufffd', ' ', '-', '1', '\u0000\u0000', '\ufeff'];
for (const a of small) for (const b of small) add(a, b);
for (let i = 0; i < 3000; i++) {
  const a = word(everything, 1, 8), n = int(a.length + 1);
  add(a.slice(0, n), a);
  add(a, a.slice(0, n) + '\u0000' + a.slice(n));
}

// Long inputs: linear work and no deep recursion on either lane.
add('a'.repeat(20000), 'a'.repeat(19999) + 'b');
add('a' + '\u0301\u0327'.repeat(5000), 'a' + '\u0327'.repeat(5000) + '\u0301'.repeat(5000));
add('\u0fb2' + '\u0301\u0327\u0f80'.repeat(3000) + '\u0f71', '\u0fb2\u0f71');
add('\uac00'.repeat(10000), '\u4e00'.repeat(10000));

// Lone surrogates in context. A Bend string may also hold an adjacent
// high/low pair as separate code points: compare it as JavaScript does.
const surrogates = ['\ud800', '\udbff', '\udc00', '\udfff', '\ud83d', '\ude00', '\ud834', '\udd1e'];
for (let i = 0; i < 2000; i++) add(word([...surrogates, 'a', 'Z', '\u0301', '\u{1f600}', '\ufffd', '\uffff'], 1, 4), word([...surrogates, 'a', '\ufffd', '\u{1f600}', '\u{10ffff}'], 1, 4));
const split = (text) => Array.from(text.split(''), (c) => c.charCodeAt(0).toString(16).toUpperCase()).join(' ');
for (const [a, b] of [['\u{1f600}', '\u{1f601}'], ['a\u{1f600}', 'a\ud83d'], ['\u{1d11e}x', 'x'], ['\u{10ffff}', '\uffff'], ['x\u{20000}', 'x\u4e00'], ['\u{1f600}\u0301', '\u{1f600}']]) {
  add(a, b, split(a), hex(b));
  add(a, b, split(a), split(b));
}

// Adversarial mixes of contraction starters, combining marks of every class,
// composites and supplementary marks, compared with canonical equivalents and
// permutations: this exercises ICU's FCD segmentation and discontiguous matching.
const starters = ['\u0418', '\u0438', '\u0627', '\u0648', '\u064a', '\u09c7', '\u0b47', '\u0bc6', '\u0c46', '\u0cc6', '\u0d46', '\u0dd9', '\u0ddc', '\u0f71', '\u0fb2', '\u0fb3', '\u1025', 'L', 'l', '\u{105d2}', '\u{105da}', '\u{11347}', '\u{113c2}', '\u{114b9}', '\u{1611e}', '\u{16d63}', '\u{16d67}', '\u0e40', '\u0ec0', '\u19b5', '\uaab5'];
const anyMarks = ['\u0301', '\u0306', '\u0308', '\u0323', '\u0327', '\u031b', '\u0334', '\u0345', '\u05b8', '\u06d9', '\u0653', '\u0654', '\u0655', '\u0f71', '\u0f72', '\u0f74', '\u0f80', '\u0e38', '\u0dca', '\u0dcf', '\u0b3e', '\u0b56', '\u0bbe', '\u0bd7', '\u0c56', '\u0cd5', '\u0cc2', '\u0d3e', '\u102e', '\u20da', '\u1dce', '\u0307', '\u00b7', '\u0387', '\u{10a0d}', '\u{1e008}', '\u{16b32}', '\u{1d165}', '\u{1d16e}', '\u{11f42}', '\u{1e2ed}', '\u{10f50}', '\u{1e136}', '\u{1e4ec}', '\u{1133e}', '\u{11357}', '\u{113b8}', '\u{113c9}', '\u{114b0}', '\u{114ba}', '\u{114bd}', '\u{1611f}', '\u{16120}', '\u{16129}', '\u{16d68}'];
const composites = ['\u0344', '\u0f73', '\u0f75', '\u0f81', '\u1eea', '\u00e9', '\u1fc1', '\u1e4e', '\u0419', '\u0439', '\u0622', '\u0623', '\u0625', '\u0624', '\u0626', '\u09cb', '\u0b4b', '\u0bca', '\u0c48', '\u0cca', '\u0d4a', '\u0dda', '\u0ddd', '\u{1d15f}', '\u{1d1bb}', '\u{1134b}', '\u{113c5}', '\u{114bc}', '\u{16121}', '\u{16125}', '\u{16d69}', '\u{105c9}'];
const adversarial = [...starters, ...anyMarks, ...anyMarks, ...composites, 'a', '\u4e00', '\u0e01', '\u0e81'];
for (let i = 0; i < 60000; i++) {
  const a = word(adversarial, 1, 9);
  const mutate = int(4);
  const b = mutate === 0 ? a.normalize('NFD') : mutate === 1 ? [...a].sort(() => random() - 0.5).join('') : mutate === 2 ? a.normalize('NFC') : word(adversarial, 1, 9);
  add(a, b);
}
// Starter, marks, a supplementary mark and U+0344: ICU's backward
// re-segmentation misses the supplementary/BMP FCD violation and its
// look-ahead backs up past the starter, repeating the starter's weights
// forever. Partners without U+0344 (or with its NFD) are finite.
const highMarks = ['\u0301', '\u0302', '\u06d9', '\u0345', '\u0653', '\u0654', '\u0308', '\u1dce'];
const lowerSupplementaryMarks = ['\u{10a0d}', '\u{10f50}', '\u{1d165}', '\u{1d16e}', '\u{11f42}'];
for (let i = 0; i < 3000; i++) {
  const s = pick(starters), tail = word(['', 'a', '\u1eea', '\u034c', '\u4e00', '\u{16125}'], 0, 2);
  const a = s + word(anyMarks.filter((m) => m !== '\u00b7' && m !== '\u0387'), 0, 1) + pick(highMarks) + pick(lowerSupplementaryMarks) + '\u0344' + tail;
  const k = 1 + int(8);
  add(a, s.repeat(k));
  add(a, s.repeat(k) + pick(['z', '\u0f40', '\u{10000}', '\uffff']));
  add(a, a.replace('\u0344', '\u0308\u0301'));
  add(a, a.slice(0, 2) + 'a');
}

fs.writeFileSync(process.argv[2], pairs.join('\n') + '\n');

// Sorting: a few thousand random strings must come out in Node's exact order
// (Array.prototype.sort is stable, so ties keep their input order).
const sortable = [];
for (let i = 0; i < 4000; i++) {
  const kind = int(4);
  sortable.push(kind === 0 ? names() : kind === 1 ? names().toLowerCase() : kind === 2 ? word(everything, 0, 5) : word(pick(families), 1, 4));
}
const order = sortable.map((_, i) => i).sort((i, j) => sortable[i].localeCompare(sortable[j]));
fs.writeFileSync(process.argv[3], sortable.map((text) => '.' + hex(text)).join('\n') + '\n');
fs.writeFileSync(process.argv[3] + '.order', order.join(' ') + '\n');
console.log(`${pairs.length} pairs, ${sortable.length} sorted strings`);
