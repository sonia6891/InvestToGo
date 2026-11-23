// 收成 (harvest) set: rice-farm subjects cut from paper. Every piece is a slightly irregular polygon with a soft
// paper shadow under it; the larger pieces carry a lighter sheet inset 6 units, as layered paper cuts do.
// Usage: node harvest.mjs <dir> [<dir> …]. Deterministic: each file draws from its own fixed-seed PRNG, so a re-run
// writes byte-identical files. Imports nothing outside node:fs and node:path.
import fs from 'node:fs';
import path from 'node:path';

const C = { gold: '#E9C46A', deep: '#B7791F', green: '#5E7D32', paper: '#FFFAEC', ink: '#3A2614' };
const SHADOW = 'rgba(80,52,24,.24)';
const JITTER = 1.5;

// ---- deterministic randomness: mulberry32, seeded from the file name (FNV-1a) so one drawing never moves another
function mulberry32(a) {
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const fnv = s => [...s].reduce((h, c) => Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0, 2166136261);
let rand = mulberry32(1);
const wobble = (amp = JITTER) => (rand() * 2 - 1) * amp;

// ---- geometry
const f = v => +v.toFixed(1);
const D = ring => 'M' + ring.map(([x, y]) => `${f(x)} ${f(y)}`).join(' L') + ' Z';
const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
const circle = (cx, cy, r, n = 40, rot = 0) => Array.from({ length: n }, (_, i) => {
  const a = rot + i / n * Math.PI * 2; return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
});
const ellipse = (cx, cy, rx, ry, n = 44) => Array.from({ length: n }, (_, i) => {
  const a = i / n * Math.PI * 2; return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
});
const rect = (x, y, w, h) => [[x, y], [x + w, y], [x + w, y + h], [x, y + h]];
function cubic(p0, p1, p2, p3, n = 24) {
  const out = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, u = 1 - t;
    out.push([u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
      u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]]);
  }
  return out;
}
// Offset a simple polygon inward by d (outward when d < 0), mitring the corners.
function inset(pts, d) {
  let a = 0; for (let i = 0; i < pts.length; i++) { const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length]; a += x1 * y2 - x2 * y1; }
  const s = a > 0 ? 1 : -1, n = pts.length, lines = [];
  for (let i = 0; i < n; i++) {
    const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % n]; const len = Math.hypot(x2 - x1, y2 - y1) || 1;
    const nx = -(y2 - y1) / len * s, ny = (x2 - x1) / len * s;
    lines.push([[x1 + nx * d, y1 + ny * d], [x2 + nx * d, y2 + ny * d]]);
  }
  return lines.map((l, i) => {
    const [[x1, y1], [x2, y2]] = lines[(i - 1 + n) % n], [[x3, y3], [x4, y4]] = l;
    const den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (Math.abs(den) < 1e-6) return l[0];
    const t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
    return [x1 + t * (x2 - x1), y1 + t * (y2 - y1)];
  });
}
// Scissor edges: long edges are split so they waver, and every vertex moves by up to ±JITTER.
function scissor(ring, seg = 14, amp = JITTER) {
  const out = [];
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i], b = ring[(i + 1) % ring.length], k = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / seg));
    for (let j = 0; j < k; j++) { const p = lerp(a, b, j / k); out.push([p[0] + wobble(amp), p[1] + wobble(amp)]); }
  }
  return out;
}
// A band of paper along a polyline; width(t) gives its width from start (t = 0) to end (t = 1).
function strip(line, width) {
  const L = [], R = [];
  line.forEach((p, i) => {
    const a = line[Math.max(0, i - 1)], b = line[Math.min(line.length - 1, i + 1)];
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, nx = -(b[1] - a[1]) / len, ny = (b[0] - a[0]) / len;
    const w = (typeof width === 'function' ? width(i / (line.length - 1)) : width) / 2;
    L.push([p[0] + nx * w, p[1] + ny * w]); R.push([p[0] - nx * w, p[1] - ny * w]);
  });
  return L.concat(R.reverse());
}
// A pointed lens (a rice grain, a leaf tip) centred on c, long along angle a.
function lens(c, a, len, wid, n = 7) {
  const ux = Math.cos(a), uy = Math.sin(a), pts = [];
  for (let i = 0; i <= n; i++) { const t = i / n, x = (t - 0.5) * len, y = Math.sin(Math.PI * t) ** 0.8 * wid / 2; pts.push([c[0] + ux * x - uy * y, c[1] + uy * x + ux * y]); }
  for (let i = n - 1; i > 0; i--) { const t = i / n, x = (t - 0.5) * len, y = -(Math.sin(Math.PI * t) ** 0.8) * wid / 2; pts.push([c[0] + ux * x - uy * y, c[1] + uy * x + ux * y]); }
  return pts;
}
const moved = (ring, dx, dy) => ring.map(([x, y]) => [x + dx, y + dy]);

// ---- paper pieces (each returns SVG markup)
// One cut: its soft shadow, then the paper. Several rings cut as one piece use the even-odd rule (holes).
function cut(rings, fill, { seg = 14, amp = JITTER } = {}) {
  const list = typeof rings[0][0] === 'number' ? [rings] : rings;
  const d = list.map(r => D(scissor(r, seg, amp))).join(' ');
  const rule = list.length > 1 ? ' fill-rule="evenodd"' : '';
  return `<path d="${d}" fill="${SHADOW}"${rule} transform="translate(3 4)"/>\n<path d="${d}" fill="${fill}"${rule}/>\n`;
}
// A piece with a lighter sheet laid on it, inset 6 units.
const layered = (ring, fill, light, d = 6) => cut(ring, fill) + cut(inset(ring, d), light);
const disc = (cx, cy, r, fill, light, d = 6) => cut(circle(cx, cy, r, Math.max(24, Math.round(r * 0.9))), fill) +
  (light ? cut(circle(cx, cy, r - d, Math.max(24, Math.round(r * 0.9))), light) : '');
// A grain: a deep-gold piece with a gold one slightly smaller on top.
const grain = (c, a, len, wid, top = C.gold, under = C.deep) =>
  cut(lens(c, a, len + 3, wid + 3), under, { seg: 99, amp: 0.6 }) + cut(lens([c[0] - 0.6, c[1] - 0.8], a, len - 1, wid - 1.5), top, { seg: 99, amp: 0.5 });

// A rice ear: a stalk along a cubic curve, grains alternating along its head, one grain at the tip.
function ear(p0, p1, p2, p3, { head = 0.42, grains = 9, len = 15, wid = 8, stalk = 4.5, splay = 0.62, stalkFill = C.deep, top = C.gold, under = C.deep } = {}) {
  const line = cubic(p0, p1, p2, p3, 30);
  let out = cut(strip(line, t => stalk * (1 - 0.45 * t)), stalkFill, { seg: 99, amp: 0.5 });
  const at = t => { const i = Math.min(line.length - 2, Math.floor(t * (line.length - 1))); const a = line[i], b = line[i + 1]; return [lerp(a, b, t * (line.length - 1) - i), Math.atan2(b[1] - a[1], b[0] - a[0])]; };
  for (let g = 0; g < grains; g++) {
    const t = head + (0.97 - head) * g / grains, [p, a] = at(t), side = g % 2 ? 1 : -1, s = 1 - 0.25 * g / grains;
    const ga = a + side * splay, l = len * s;
    out += grain([p[0] + Math.cos(ga) * l * 0.42, p[1] + Math.sin(ga) * l * 0.42], ga, l, wid * s, top, under);
  }
  const [tip, ta] = at(0.999);
  out += grain([tip[0] + Math.cos(ta) * len * 0.3, tip[1] + Math.sin(ta) * len * 0.3], ta, len * 0.8, wid * 0.75, top, under);
  return out;
}
// A rice leaf: a blade along a cubic curve, widest near its base, pointed at the tip.
const leaf = (p0, p1, p2, p3, w = 10, fill = C.green) =>
  cut(strip(cubic(p0, p1, p2, p3, 20), t => w * Math.sin(Math.PI * (0.18 + 0.82 * t)) ** 0.7 + 0.4), fill, { seg: 99, amp: 0.7 });

function svg(w, h, body, pad) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-pad} ${-pad} ${w + pad * 2} ${h + pad * 2}" width="${w * 2}" height="${h * 2}">\n${body}</svg>\n`;
}
const icon = body => svg(200, 200, body, 22);

// ---- the set
const I = {};

// hero_dollar → a gold coin stamped with a rice ear
I.dollar = () => icon(disc(100, 100, 86, C.deep, C.gold) +
  cut([circle(100, 100, 66, 56), circle(100, 100, 60, 52)], C.deep) +
  leaf([76, 150], [60, 128], [54, 104], [64, 82], 11) +
  ear([82, 158], [84, 104], [104, 52], [140, 92], { grains: 10, len: 17, wid: 9, stalk: 6, top: C.deep, under: C.deep }));

// pocket / pocket_icon → a woven harvest basket with rice ears spilling over its rim
I.pocket_icon = () => {
  let s = '';
  s += leaf([84, 96], [70, 70], [52, 58], [30, 66], 10);
  s += leaf([118, 96], [134, 66], [156, 56], [178, 64], 10);
  s += ear([70, 98], [56, 60], [30, 52], [18, 92], { grains: 8, len: 17, wid: 9 });
  s += ear([92, 98], [88, 50], [94, 22], [118, 18], { grains: 8, len: 17, wid: 9 });
  s += ear([112, 98], [124, 54], [150, 34], [176, 56], { grains: 9, len: 17, wid: 9 });
  const body = [[38, 98], [162, 98], [148, 178], [52, 178]];
  s += layered(body, C.deep, C.gold);
  // the weave: offset rows of short deep-gold slats between the sides
  for (let row = 0; row < 4; row++) {
    const y = 112 + row * 16, k = (y - 98) / 80, xl = 38 + 14 * k + 12, xr = 162 - 14 * k - 12;
    for (let x = xl + (row % 2 ? 9 : 0); x + 12 <= xr; x += 20) s += cut(rect(x, y, 12, 8), C.deep, { amp: 0.6 });
  }
  s += layered([[28, 86], [172, 86], [168, 106], [32, 106]], C.deep, C.gold, 5);
  return icon(s);
};

// find → a bamboo sieve (竹篩) with grains on it and a few falling through
I.icon_magnifier = () => {
  let s = '';
  s += cut(ellipse(100, 98, 88, 62, 56), C.deep) + cut(ellipse(100, 98, 82, 56, 52), C.gold);
  s += cut([ellipse(100, 98, 70, 46, 48), ellipse(100, 98, 64, 41, 44)], C.deep);
  // the woven floor: a checker of deep-gold squares inside the inner rim
  for (let y = 66; y <= 124; y += 11) for (let x = 40; x <= 156; x += 11) {
    if (((x - 40) / 11 + (y - 66) / 11) % 2) continue;
    const cx = x + 4.5, cy = y + 4.5;
    if (((cx - 100) / 58) ** 2 + ((cy - 98) / 35) ** 2 > 1) continue;
    s += cut(rect(x, y, 9, 9), C.deep, { amp: 0.5 });
  }
  const pile = [[118, 92, -0.4], [132, 96, 0.5], [124, 104, 0.1], [108, 102, -0.9], [140, 104, 1.1], [116, 112, 0.7], [132, 112, -0.3], [100, 92, 0.9]];
  for (const [x, y, a] of pile) s += grain([x, y], a, 15, 8, C.paper, C.deep);
  for (const [x, y, a] of [[84, 176, 1.2], [110, 186, 0.4], [134, 172, 1.9]]) s += grain([x, y], a, 15, 8);
  return icon(s);
};

// dividends → a bundle of rice sheaves, tied at the waist
I.icon_stack = () => {
  let s = '';
  s += ear([88, 96], [70, 70], [40, 60], [22, 96], { grains: 8 });
  s += ear([112, 96], [130, 70], [160, 60], [178, 96], { grains: 8 });
  s += ear([94, 94], [86, 60], [70, 34], [48, 34], { grains: 8 });
  s += ear([106, 94], [114, 60], [130, 34], [152, 34], { grains: 8 });
  s += ear([100, 94], [100, 60], [102, 28], [112, 10], { grains: 7, len: 14 });
  const body = [[66, 92], [134, 92], [114, 130], [146, 186], [54, 186], [86, 130]];
  s += layered(body, C.deep, C.gold);
  for (const [top, bot] of [[80, 70], [92, 90], [108, 110], [120, 130]]) s += cut(strip([[top, 100], [100 + (top - 100) * 0.3, 130], [bot, 178]], 3.2), C.deep, { seg: 99, amp: 0.4 });
  s += layered([[80, 120], [120, 120], [124, 140], [76, 140]], C.green, C.gold, 5);
  return icon(s);
};

// tools / calc → a wooden grain measure (斗) heaped with grain
I.icon_calc = () => {
  let s = '';
  s += cut(cubic([30, 94], [44, 30], [156, 30], [170, 94], 20).concat([[170, 96], [30, 96]]), C.deep);
  s += cut(cubic([38, 92], [52, 40], [148, 40], [162, 92], 20), C.gold);
  for (const [x, y, a] of [[76, 70, -0.6], [100, 56, 0.2], [122, 72, 0.9], [92, 80, 1.4], [140, 84, -0.3], [62, 86, 0.4], [112, 86, -1.1]]) s += grain([x, y], a, 14, 7, C.gold, C.deep);
  const front = [[34, 98], [166, 98], [146, 184], [54, 184]];
  s += layered(front, C.deep, C.gold);
  for (const y of [126, 154]) { const k = (y - 98) / 86; s += cut(rect(34 + 20 * k + 6, y, 132 - 40 * k - 12, 5), C.deep, { amp: 0.5 }); }
  s += layered([[24, 88], [176, 88], [172, 106], [28, 106]], C.ink, C.deep, 5);
  for (const [x, y] of [[44, 172], [156, 172]]) s += cut(circle(x, y, 6, 14), C.ink);
  return icon(s);
};

// fees → three rice stalks of rising height on a strip of paddy
I.icon_bars = () => {
  let s = '';
  const stalks = [[50, 128], [100, 92], [150, 54]];
  stalks.forEach(([x, top], i) => {
    s += leaf([x, 176], [x - 18, 160 - i * 6], [x - 30, 150 - i * 12], [x - 36, 132 - i * 16], 9);
    s += cut(strip([[x, 180], [x, top]], 11), C.green, { seg: 16 });
    s += ear([x, top + 2], [x, top - 28], [x + 30, top - 38], [x + 38, top + 6], { grains: 8, len: 19, wid: 10.5, stalk: 6, head: 0.34 });
  });
  s += layered([[10, 172], [190, 172], [186, 194], [14, 194]], C.deep, C.gold, 5);
  return icon(s);
};

// reminder → a granary bell on its rope, a rice ear cast on it
I.icon_bell = () => {
  let s = '';
  s += cut(strip([[100, 2], [100, 36]], 7), C.ink, { seg: 99, amp: 0.5 });
  s += cut([circle(100, 38, 13, 20), circle(100, 38, 6, 14)], C.ink);
  s += disc(100, 176, 13, C.ink);
  const half = cubic([100, 42], [62, 42], [60, 70], [58, 104], 12).concat(cubic([58, 104], [56, 136], [44, 146], [26, 162], 10).slice(1));
  const right = half.map(([x, y]) => [200 - x, y]).reverse();
  const body = half.concat([[26, 172], [174, 172]], right.slice(0, -1));
  s += layered(body, C.deep, C.gold);
  s += cut(strip([[38, 148], [100, 150], [162, 148]], 7), C.deep, { amp: 0.5 });
  s += leaf([90, 134], [80, 118], [74, 102], [78, 84], 8);
  s += ear([98, 136], [96, 104], [104, 74], [126, 84], { grains: 8, len: 12, wid: 7, stalk: 4, top: C.deep, under: C.deep });
  return icon(s);
};

// achievements / goal → a granary (穀倉) on stilts, thatched, with a rice-ear finial
I.icon_target = () => {
  let s = '';
  for (const x of [60, 100, 140]) s += cut(rect(x - 6, 158, 12, 28), C.ink) + cut(rect(x - 11, 182, 22, 8), C.deep);
  const body = [[48, 96], [152, 96], [156, 164], [44, 164]];
  s += layered(body, C.deep, C.gold);
  for (const x of [68, 132]) s += cut(strip([[x, 104], [x + (x < 100 ? -1 : 1) * 2, 158]], 4), C.deep, { seg: 99, amp: 0.4 });
  s += layered([[84, 116], [116, 116], [116, 164], [84, 164]], C.ink, C.deep, 5);
  s += ear([100, 36], [98, 20], [104, 6], [118, 4], { grains: 6, len: 12, wid: 7, stalk: 4 });
  const roof = cubic([100, 30], [80, 46], [44, 84], [14, 108], 12).concat(cubic([186, 108], [156, 84], [120, 46], [100, 30], 12).slice(0, -1));
  s += cut(roof, C.ink);
  for (const y of [62, 86]) { const w = (y - 30) * 1.0 + 6; s += cut(strip([[100 - w, y + 8], [100, y], [100 + w, y + 8]], 5), C.deep, { seg: 99, amp: 0.5 }); }
  return icon(s);
};

// crown → a bamboo hat (斗笠) with its chin strap
I.icon_crown = () => {
  let s = '';
  s += cut(strip(cubic([50, 128], [56, 176], [144, 176], [150, 128], 18), 5), C.ink, { seg: 99, amp: 0.5 });
  const rim = cubic([188, 124], [150, 150], [50, 150], [12, 124], 18);
  const hat = [[100, 34]].concat(rim);
  s += layered(hat, C.deep, C.gold);
  for (let i = 1; i < 8; i++) { const [x, y] = rim[Math.round(i * 18 / 8)]; s += cut(strip([lerp([100, 40], [x, y], 0.16), lerp([100, 40], [x, y], 0.9)], 3.4), C.deep, { seg: 99, amp: 0.4 }); }
  s += cut(strip(cubic([30, 120], [70, 138], [130, 138], [170, 120], 18), 5), C.deep, { seg: 99, amp: 0.5 });
  s += disc(100, 38, 9, C.ink, null);
  return icon(s);
};

// badge → a round paper seal, scalloped, with a rice ear
I.badge = () => {
  const scallop = (r, bump) => Array.from({ length: 96 }, (_, i) => {
    const a = i / 96 * Math.PI * 2, rr = r + bump * Math.abs(Math.cos(a * 8)); return [100 + Math.cos(a) * rr, 100 + Math.sin(a) * rr];
  });
  let s = cut(scallop(88, 8), C.deep) + cut(scallop(82, 7), C.gold);
  s += disc(100, 100, 68, C.deep, C.paper, 5);
  s += leaf([86, 156], [64, 136], [58, 108], [70, 84], 12);
  s += ear([92, 162], [92, 104], [110, 52], [144, 96], { grains: 10, len: 17, wid: 9, stalk: 6 });
  return icon(s);
};

// patch → the rice-paper slip the hero digits sit on: a green mat with a paper sheet on it. The lobby stretches it
// behind the digits, so it fills its frame (a 6-unit margin for the shadow) and carries nothing that would distort.
I.patch = () => svg(260, 210, cut(rect(0, 0, 260, 210), C.green, { seg: 10 }) + cut(rect(8, 8, 244, 194), C.paper, { seg: 10 }), 6);

// ---- digits 0–9: chunky scissor-cut numerals on an 86×116 grid, gold on a deep-gold under-layer
const flip = pts => pts.map(([x, y]) => [86 - x, 116 - y]);
const DIGITS = [
  [[[16, 0], [70, 0], [86, 16], [86, 100], [70, 116], [16, 116], [0, 100], [0, 16]], [[32, 26], [54, 26], [60, 32], [60, 84], [54, 90], [32, 90], [26, 84], [26, 32]]],
  [[[12, 20], [38, 0], [62, 0], [62, 92], [80, 92], [80, 116], [8, 116], [8, 92], [36, 92], [36, 36], [18, 44]]],
  [[[0, 16], [16, 0], [70, 0], [86, 16], [86, 54], [36, 90], [86, 90], [86, 116], [0, 116], [0, 90], [60, 52], [60, 26], [26, 26], [26, 38], [0, 38]]],
  [[[0, 0], [70, 0], [86, 16], [86, 46], [78, 58], [86, 70], [86, 100], [70, 116], [0, 116], [0, 90], [60, 90], [60, 70], [22, 70], [22, 46], [60, 46], [60, 26], [0, 26]]],
  [[[2, 0], [28, 0], [26, 62], [52, 62], [52, 0], [78, 0], [78, 62], [86, 62], [86, 86], [78, 86], [78, 116], [52, 116], [52, 86], [0, 86]]],
  [[[0, 0], [86, 0], [86, 26], [26, 26], [26, 44], [70, 44], [86, 60], [86, 100], [70, 116], [0, 116], [0, 90], [60, 90], [60, 70], [0, 70]]],
  [[[16, 0], [86, 0], [86, 24], [26, 24], [26, 44], [70, 44], [86, 60], [86, 100], [70, 116], [16, 116], [0, 100], [0, 16]], [[26, 68], [60, 68], [60, 92], [26, 92]]],
  [[[0, 0], [86, 0], [86, 26], [52, 116], [24, 116], [56, 26], [0, 26]]],
  [[[14, 0], [72, 0], [86, 14], [86, 46], [78, 58], [86, 70], [86, 102], [72, 116], [14, 116], [0, 102], [0, 70], [8, 58], [0, 46], [0, 14]],
    [[26, 22], [60, 22], [60, 46], [26, 46]], [[26, 70], [60, 70], [60, 94], [26, 94]]],
];
DIGITS.push([flip(DIGITS[6][0]), flip(DIGITS[6][1])]);
// The under-layer is the glyph grown by 4 (its holes shrunk by 4) and dropped 3 down-right, so a deep-gold rim shows.
const numeral = rings => cut(rings.map((r, i) => moved(inset(r, i ? 4 : -4), 2, 3)), C.deep, { seg: 12 }) + cut(rings, C.gold, { seg: 12 });
DIGITS.forEach((rings, n) => { I[`digit_${n}`] = () => svg(86, 116, numeral(rings), 22); });

const OUT = process.argv.slice(2);
if (!OUT.length) { console.error('usage: node harvest.mjs <dir> [<dir> …]'); process.exit(1); }
for (const dir of OUT) fs.mkdirSync(dir, { recursive: true });
for (const [name, draw] of Object.entries(I)) {
  rand = mulberry32(fnv(name));
  const text = draw();
  for (const dir of OUT) fs.writeFileSync(path.join(dir, `${name}.svg`), text);
  console.log(`${name}.svg`);
}
