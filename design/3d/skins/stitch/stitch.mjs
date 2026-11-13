// Paper-stitch (紙本縫線) set: layered paper cut-outs on kraft, a running stitch sewn inside every edge.
import rough from 'roughjs';
import fs from 'node:fs';
import path from 'node:path';

const C = { navy: '#2F4A6D', mustard: '#E3A82B', rust: '#C9573F', cream: '#F7F0E1', olive: '#7C8C4B', kraft: '#E9DCC3' };
const SHADOW = 'rgba(80,52,24,.24)';
const gen = rough.generator();
let seed = 11;

// ---- geometry helpers
const P = pts => 'M' + pts.map(p => p.join(' ')).join(' L') + ' Z';
const circleD = (cx, cy, r) => `M${cx - r} ${cy} a${r} ${r} 0 1 0 ${r * 2} 0 a${r} ${r} 0 1 0 ${-r * 2} 0 Z`;
function inset(pts, d) {
  // offset a simple polygon inward by d
  let a = 0; for (let i = 0; i < pts.length; i++) { const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length]; a += x1 * y2 - x2 * y1; }
  const s = a > 0 ? 1 : -1, n = pts.length, lines = [];
  for (let i = 0; i < n; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % n]; const len = Math.hypot(x2 - x1, y2 - y1) || 1;
    const nx = -(y2 - y1) / len * s, ny = (x2 - x1) / len * s;
    lines.push([[x1 + nx * d, y1 + ny * d], [x2 + nx * d, y2 + ny * d]]);
  }
  return lines.map((l, i) => {
    const m = lines[(i - 1 + n) % n];
    const [[x1, y1], [x2, y2]] = m, [[x3, y3], [x4, y4]] = l;
    const den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (Math.abs(den) < 1e-6) return l[0];
    const t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
    return [x1 + t * (x2 - x1), y1 + t * (y2 - y1)];
  });
}
const rectPts = (x, y, w, h) => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];

// ---- drawing primitives (return svg strings)
function cut(d, fill) {
  const out = [`<path d="${d}" fill="${SHADOW}" transform="translate(3 4)"/>`];
  for (const p of gen.toPaths(gen.path(d, { fill, fillStyle: 'solid', stroke: 'none', roughness: 0.55, seed: seed++ })))
    out.push(`<path d="${p.d}" fill="${p.fill === 'none' ? 'none' : fill}" stroke="none"/>`);
  return out.join('');
}
const stitch = (d, thread, w = 2.2) => `<path d="${d}" fill="none" stroke="${thread}" stroke-width="${w}" stroke-dasharray="6 5" stroke-linecap="round" stroke-linejoin="round"/>`;
const poly = (pts, fill, thread, d = 6) => cut(P(pts), fill) + (thread ? stitch(P(inset(pts, d)), thread) : '');
const disc = (cx, cy, r, fill, thread, d = 6) => cut(circleD(cx, cy, r), fill) + (thread ? stitch(circleD(cx, cy, r - d), thread) : '');
const thread = (d, color, w = 3) => `<path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const rect = (x, y, w, h, fill, th, d) => poly(rectPts(x, y, w, h), fill, th, d);

function svg(w, h, body, pad = 0) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-pad} ${-pad} ${w + pad * 2} ${h + pad * 2}" width="${w * 2}" height="${h * 2}">${body}</svg>`;
}
const icon = body => svg(200, 200, body, 22);

// ---- the set
const one = (dx = 0) => [[52 + dx, 48], [84 + dx, 48], [84 + dx, 164], [52 + dx, 164], [52 + dx, 82], [34 + dx, 88], [32 + dx, 64]];
const three = [[106, 48], [192, 48], [192, 164], [106, 164], [106, 138], [164, 138], [164, 118], [124, 118], [124, 94], [164, 94], [164, 74], [106, 74]];
const I = {
  blocks_13: () => svg(260, 210, rect(10, 16, 240, 180, C.cream, C.navy, 8) + poly(one(), C.navy, C.cream, 5) + poly(three, C.mustard, C.navy, 5), 26),
  blocks_12: () => svg(260, 210, rect(10, 16, 240, 180, C.cream, C.navy, 8) + poly(one(), C.navy, C.cream, 5) +
    poly([[106, 48], [192, 48], [192, 100], [138, 138], [192, 138], [192, 164], [106, 164], [106, 140], [164, 100], [164, 74], [106, 74]], C.mustard, C.navy, 5), 26),
  blocks_1: () => svg(260, 210, rect(70, 16, 120, 180, C.cream, C.navy, 8) + poly(one(64), C.navy, C.cream, 5), 26),
  // find ETF → folded paper map with a stitched route and a pin
  icon_magnifier: () => icon(
    poly([[26, 52], [78, 40], [80, 160], [28, 172]], C.cream, C.navy) +
    poly([[78, 40], [128, 54], [128, 174], [80, 160]], '#EADFC8', C.navy) +
    poly([[128, 54], [176, 42], [176, 162], [128, 174]], C.cream, C.navy) +
    `<path d="M46 146 C70 120 92 150 112 118 S140 96 150 92" fill="none" stroke="${C.rust}" stroke-width="3" stroke-dasharray="7 6" stroke-linecap="round"/>` +
    cut('M150 104 C134 84 134 58 150 58 C166 58 166 84 150 104 Z', C.rust) + disc(150, 74, 7, C.cream)),
  // dividends → paper jar full of coins, stitched label
  icon_stack: () => icon(
    rect(48, 60, 104, 118, C.cream, C.navy) +
    disc(78, 150, 16, C.mustard) + disc(112, 152, 16, C.mustard) + disc(95, 128, 16, C.mustard) + disc(128, 126, 14, C.mustard) +
    rect(56, 40, 88, 24, C.rust, C.cream, 5) + rect(70, 82, 60, 28, C.navy, C.cream, 5)),
  // pocket → tote bag with a sewn-on pocket and a coin
  pocket_icon: () => icon(
    thread('M66 74 C66 26 134 26 134 74', C.navy, 9) + stitch('M66 74 C66 26 134 26 134 74', C.cream, 1.8) +
    poly([[36, 70], [164, 70], [152, 182], [48, 182]], C.mustard, C.navy, 7) +
    disc(100, 108, 18, C.cream) +
    poly([[64, 112], [136, 112], [136, 166], [64, 166]], C.navy, C.cream, 6)),
  // DCA calculator → tape measure
  icon_calc: () => icon(
    rect(110, 120, 82, 34, C.mustard, null) +
    [120, 132, 144, 156, 168, 180].map((x, i) => thread(`M${x} 120 L${x} ${i % 2 ? 132 : 140}`, C.navy, 2.4)).join('') +
    disc(86, 108, 62, C.rust, C.cream, 8) + disc(86, 108, 22, C.cream, C.rust, 5)),
  // fee comparison → two price tags
  icon_bars: () => icon(
    poly([[30, 104], [96, 92], [128, 124], [104, 160], [38, 170]], C.cream, C.navy) + disc(108, 126, 6, C.kraft) +
    poly([[56, 40], [124, 40], [156, 74], [124, 108], [56, 108]], C.mustard, C.navy) + disc(136, 74, 7, C.kraft) +
    thread('M142 72 C162 60 170 40 182 34', C.rust, 2.4) + thread('M114 126 C134 140 150 160 172 166', C.rust, 2.4) +
    thread('M76 64 L108 64 M76 84 L100 84', C.navy, 4)),
  // dividend reminder → note pinned with a sewing pin
  icon_bell: () => icon(
    poly([[40, 54], [160, 44], [166, 164], [48, 172]], C.mustard, C.navy, 7) +
    thread('M66 96 L140 90 M68 120 L130 116 M70 144 L112 141', C.navy, 3.4) +
    thread('M100 58 L128 22', '#8A8F98', 3) + disc(100, 58, 11, C.rust)),
  // goals / achievements → paper rosette with ribbon tails
  icon_target: () => {
    const pts = []; for (let i = 0; i < 28; i++) { const a = i / 28 * Math.PI * 2, r = i % 2 ? 58 : 70; pts.push([100 + Math.cos(a) * r, 84 + Math.sin(a) * r]); }
    return icon(poly([[72, 120], [96, 128], [84, 190], [70, 176], [56, 186]], C.navy, C.cream, 4) +
      poly([[128, 120], [104, 128], [116, 190], [130, 176], [144, 186]], C.navy, C.cream, 4) +
      cut(P(pts), C.rust) + disc(100, 84, 44, C.cream, C.rust, 6) + disc(100, 84, 22, C.mustard));
  },
  // membership → stitched badge patch with a star
  icon_crown: () => {
    const hex = []; for (let i = 0; i < 6; i++) { const a = Math.PI / 6 + i * Math.PI / 3; hex.push([100 + Math.cos(a) * 80, 100 + Math.sin(a) * 80]); }
    const star = []; for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, r = i % 2 ? 18 : 40; star.push([100 + Math.cos(a) * r, 102 + Math.sin(a) * r]); }
    return icon(poly(hex, C.navy, C.cream, 9) + poly(star, C.mustard, C.navy, 4));
  },
  // first dividend / splash → coin patch with an embroidered $
  dollar: () => icon(disc(100, 100, 82, C.mustard, C.navy, 9) + disc(100, 100, 58, C.cream, C.mustard, 5) +
    thread('M120 74 C110 64 82 66 82 84 C82 104 120 96 120 118 C120 138 88 138 78 126', C.navy, 9) + thread('M100 56 L100 146', C.navy, 6)),
  // lobby backing: the cream cloth patch the numerals are sewn onto (same as blocks_12's backing)
  patch: () => svg(260, 210, rect(10, 16, 240, 180, C.cream, C.navy, 8), 26),
};

// ---- numerals 0–9: paper cut-outs on the same 86×116 grid as the 1, 2 and 3 above.
// Each glyph is a list of rings: the outline first, then any holes. Two colourways alternate in the lobby:
// digit_N = navy paper, cream thread; digit_N_b = mustard paper, navy thread.
const flip = pts => pts.map(([x, y]) => [86 - x, 116 - y]);
const DIGITS = [
  [[[12, 0], [74, 0], [86, 12], [86, 104], [74, 116], [12, 116], [0, 104], [0, 12]], [[26, 24], [60, 24], [60, 92], [26, 92]]],
  [[[37, 0], [69, 0], [69, 116], [37, 116], [37, 34], [19, 40], [17, 16]]],
  [[[0, 0], [86, 0], [86, 52], [32, 90], [86, 90], [86, 116], [0, 116], [0, 92], [58, 52], [58, 26], [0, 26]]],
  [[[0, 0], [86, 0], [86, 116], [0, 116], [0, 90], [58, 90], [58, 70], [18, 70], [18, 46], [58, 46], [58, 26], [0, 26]]],
  [[[0, 0], [26, 0], [26, 62], [52, 62], [52, 0], [78, 0], [78, 62], [86, 62], [86, 86], [78, 86], [78, 116], [52, 116], [52, 86], [0, 86]]],
  [[[0, 0], [86, 0], [86, 26], [26, 26], [26, 46], [86, 46], [86, 116], [0, 116], [0, 90], [60, 90], [60, 70], [0, 70]]],
  [[[0, 0], [86, 0], [86, 24], [26, 24], [26, 44], [86, 44], [86, 116], [0, 116]], [[26, 68], [60, 68], [60, 92], [26, 92]]],
  [[[0, 0], [86, 0], [86, 26], [50, 116], [22, 116], [56, 26], [0, 26]]],
  [[[10, 0], [76, 0], [86, 10], [86, 48], [80, 58], [86, 68], [86, 106], [76, 116], [10, 116], [0, 106], [0, 68], [6, 58], [0, 48], [0, 10]],
    [[26, 22], [60, 22], [60, 46], [26, 46]], [[26, 70], [60, 70], [60, 94], [26, 94]]],
];
DIGITS.push([flip(DIGITS[6][0]), flip(DIGITS[6][1])]);

// A cut-out with holes: one shadow and one paper path, both even-odd, then a stitch inside every edge.
function holed(rings, fill, th, d = 5) {
  const all = rings.map(P).join(' ');
  const paper = rings.map(r => gen.toPaths(gen.path(P(r), { fill, fillStyle: 'solid', stroke: 'none', roughness: 0.55, seed: seed++ }))
    .filter(p => p.fill !== 'none').map(p => p.d).join(' ')).join(' ');
  return `<path d="${all}" fill="${SHADOW}" fill-rule="evenodd" transform="translate(3 4)"/>` +
    `<path d="${paper}" fill="${fill}" fill-rule="evenodd" stroke="none"/>` +
    rings.map((r, i) => stitch(P(inset(r, i ? -d : d)), th)).join('');
}
DIGITS.forEach((rings, n) => {
  I[`digit_${n}`] = () => svg(86, 116, holed(rings, C.navy, C.cream), 22);
  I[`digit_${n}_b`] = () => svg(86, 116, holed(rings, C.mustard, C.navy), 22);
});

const OUT = process.argv.slice(2);
for (const dir of OUT) fs.mkdirSync(dir, { recursive: true });
for (const [n, f] of Object.entries(I)) { const s = f(); for (const dir of OUT) fs.writeFileSync(path.join(dir, `${n}.svg`), s); }
const sheet = Object.keys(I).map(n => `<figure style="margin:0;text-align:center;font:13px sans-serif;color:#7A5A36"><img src="${n}.svg" style="width:200px;height:200px"><figcaption>${n}</figcaption></figure>`).join('');
fs.writeFileSync(path.join(OUT[0], 'sheet.html'), `<!doctype html><body style="margin:0;background:${C.kraft};display:grid;grid-template-columns:repeat(4,220px);gap:20px;padding:30px">${sheet}</body>`);
console.log('ok', Object.keys(I).length);
