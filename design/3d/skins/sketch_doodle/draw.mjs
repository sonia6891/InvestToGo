// Hand-drawn doodle set for the 手繪 skin. New subjects, not the 3D objects traced.
import rough from 'roughjs';
import fs from 'node:fs';
import path from 'node:path';

const INK = '#1F1F1F', MARK = '#F2D16B', PAPER = '#FAF8F3';
const OUT = process.argv.slice(2);
let seed = 7;
const gen = () => rough.generator();
const base = (o = {}) => ({ stroke: INK, strokeWidth: 2.6, roughness: 1.3, bowing: 1.4, seed: seed++, ...o });
const hatch = (o = {}) => base({ fill: MARK, fillStyle: 'hachure', hachureGap: 5.5, fillWeight: 1.8, hachureAngle: -41, ...o });
const paper = (o = {}) => base({ fill: PAPER, fillStyle: 'solid', ...o });
const solidMark = (o = {}) => base({ fill: MARK, fillStyle: 'solid', ...o });

function svg(w, h, shapes) {
  const g = gen();
  const parts = [];
  for (const s of shapes) {
    for (const p of g.toPaths(s)) {
      const fill = p.fill && p.fill !== 'none' ? p.fill : 'none';
      parts.push(`<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${fill}" stroke-linecap="round" stroke-linejoin="round"/>`);
    }
  }
  const pad = w === 200 ? 26 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-pad} ${-pad} ${w + pad * 2} ${h + pad * 2}" width="${w * 2}" height="${h * 2}">${parts.join('')}</svg>`;
}
const G = gen();
const L = (x1, y1, x2, y2, o) => G.line(x1, y1, x2, y2, base(o));

const icons = {};

// 13 → tally marks with a highlighter swipe
icons.blocks_13 = () => {
  const s = [G.rectangle(14, 92, 236, 40, base({ stroke: 'none', fill: MARK, fillStyle: 'solid', roughness: 2.2 }))];
  const T = { strokeWidth: 5, roughness: 1.6 };
  for (const gx of [22, 104]) {
    for (let i = 0; i < 4; i++) s.push(L(gx + 14 + i * 14, 58 + (i % 2) * 4, gx + 12 + i * 15, 160 - (i % 3) * 3, T));
    s.push(L(gx, 140, gx + 72, 76, T));
  }
  for (let i = 0; i < 3; i++) s.push(L(196 + i * 16, 60 + i * 3, 194 + i * 17, 158, T));
  return svg(260, 210, s);
};
// 12 → two full gates and two strokes
icons.blocks_12 = () => {
  const s = [G.rectangle(14, 92, 220, 40, base({ stroke: 'none', fill: MARK, fillStyle: 'solid', roughness: 2.2 }))];
  const T = { strokeWidth: 5, roughness: 1.6 };
  for (const gx of [24, 108]) {
    for (let i = 0; i < 4; i++) s.push(L(gx + 14 + i * 14, 58 + (i % 2) * 4, gx + 12 + i * 15, 160 - (i % 3) * 3, T));
    s.push(L(gx, 140, gx + 72, 76, T));
  }
  for (let i = 0; i < 2; i++) s.push(L(202 + i * 17, 60 + i * 3, 200 + i * 18, 158, T));
  return svg(250, 210, s);
};
// first month → one single stroke and a sparkle
icons.blocks_1 = () => svg(260, 210, [
  G.rectangle(80, 92, 100, 40, base({ stroke: 'none', fill: MARK, fillStyle: 'solid', roughness: 2.2 })),
  L(128, 52, 124, 162, { strokeWidth: 5.5, roughness: 1.6 }),
  L(170, 52, 170, 76), L(158, 64, 182, 64), L(196, 92, 206, 82), L(150, 34, 154, 44),
]);
// find ETF → binoculars
icons.icon_magnifier = () => svg(200, 200, [
  G.curve([[40, 150], [20, 100], [70, 30], [130, 30], [180, 100], [160, 150]], base({ strokeWidth: 1.6 })),
  G.rectangle(44, 46, 38, 26, paper()), G.rectangle(118, 46, 38, 26, paper()),
  G.rectangle(34, 68, 58, 74, paper()), G.rectangle(108, 68, 58, 74, paper()),
  G.rectangle(88, 86, 24, 28, paper()),
  G.circle(63, 142, 60, hatch()), G.circle(137, 142, 60, hatch({ hachureAngle: -48 })),
  G.circle(55, 134, 12, base({ strokeWidth: 1.6 })),
]);
// dividends → sprout whose leaves are coins
icons.icon_stack = () => svg(200, 200, [
  G.curve([[100, 124], [96, 90], [104, 60], [100, 36]], base()),
  G.curve([[99, 98], [86, 90], [70, 84]], base({ strokeWidth: 2 })),
  G.curve([[101, 70], [116, 62], [132, 56]], base({ strokeWidth: 2 })),
  G.circle(58, 80, 36, hatch()), G.circle(146, 52, 36, hatch({ hachureAngle: -60 })), G.circle(100, 30, 22, hatch()),
  L(58, 72, 58, 88, { strokeWidth: 2 }), L(146, 44, 146, 60, { strokeWidth: 2 }),
  G.polygon([[64, 136], [136, 136], [126, 186], [74, 186]], paper()),
  G.rectangle(54, 120, 92, 18, paper()),
]);
// pocket → jeans back pocket with a coin peeking out
icons.pocket_icon = () => svg(200, 200, [
  G.circle(108, 48, 54, hatch()), L(108, 36, 108, 58, { strokeWidth: 2 }),
  G.path('M40 60 L160 60 L160 140 L100 178 L40 140 Z', paper()),
  G.path('M50 72 L150 72 L150 134 L100 166 L50 134 Z', base({ strokeWidth: 1.4, strokeLineDash: [6, 6] })),
  L(62, 98, 100, 118, { strokeWidth: 1.6 }), L(100, 118, 138, 98, { strokeWidth: 1.6 }),
]);
// DCA calculator → calendar page with a circled day
icons.icon_calc = () => {
  const s = [G.rectangle(36, 46, 128, 122, paper()), G.rectangle(36, 46, 128, 28, hatch()),
    L(70, 34, 70, 58), L(130, 34, 130, 58)];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 4; c++) s.push(G.circle(58 + c * 28, 96 + r * 24, 4, base({ strokeWidth: 2.2, roughness: 0.6 })));
  s.push(G.ellipse(114, 120, 38, 30, base({ roughness: 2.6, strokeWidth: 2.4 })));
  s.push(G.ellipse(115, 121, 34, 28, base({ roughness: 2.8, strokeWidth: 1.4 })));
  return svg(200, 200, s);
};
// fee comparison → balance scale
icons.icon_bars = () => svg(200, 200, [
  L(100, 40, 100, 168), G.polygon([[78, 172], [122, 172], [100, 152]], paper()),
  L(34, 58, 166, 72), G.circle(100, 62, 12, solidMark()),
  L(40, 60, 24, 118, { strokeWidth: 1.6 }), L(40, 60, 64, 118, { strokeWidth: 1.6 }),
  L(160, 72, 144, 104, { strokeWidth: 1.6 }), L(160, 72, 182, 104, { strokeWidth: 1.6 }),
  G.arc(44, 118, 52, 30, 0, Math.PI, true, paper()),
  G.arc(163, 104, 52, 30, 0, Math.PI, true, paper()),
  G.ellipse(44, 112, 22, 8, hatch()), G.ellipse(44, 104, 22, 8, hatch()),
]);
// dividend reminder → alarm clock
icons.icon_bell = () => svg(200, 200, [
  G.circle(58, 52, 34, hatch()), G.circle(142, 52, 34, hatch({ hachureAngle: -60 })),
  L(70, 170, 60, 184), L(130, 170, 140, 184),
  G.circle(100, 112, 112, paper()),
  L(100, 112, 100, 76), L(100, 112, 126, 124),
  L(100, 62, 100, 70, { strokeWidth: 2 }), L(150, 112, 142, 112, { strokeWidth: 2 }),
  L(100, 162, 100, 154, { strokeWidth: 2 }), L(50, 112, 58, 112, { strokeWidth: 2 }),
  L(156, 70, 170, 62, { strokeWidth: 1.8 }), L(162, 84, 178, 82, { strokeWidth: 1.8 }),
]);
// goals / achievements → little flag on a hill
icons.icon_target = () => svg(200, 200, [
  G.path('M16 170 Q100 104 184 170', base()),
  L(100, 134, 100, 36),
  G.polygon([[102, 40], [164, 56], [102, 76]], hatch()),
  L(46, 176, 56, 168, { strokeWidth: 1.6 }), L(140, 172, 150, 164, { strokeWidth: 1.6 }),
]);
// membership → ticket stub with a star
icons.icon_crown = () => svg(200, 200, [
  G.path('M28 66 L172 54 L176 82 Q164 92 177 104 L180 132 L36 144 L33 116 Q46 104 31 94 Z', paper()),
  G.line(132, 60, 136, 136, base({ strokeWidth: 1.6, strokeLineDash: [5, 7] })),
  G.polygon([[80, 72], [88, 92], [110, 92], [92, 104], [100, 126], [80, 112], [61, 126], [68, 104], [50, 92], [72, 92]], hatch()),
]);
// first dividend / splash → envelope with a coin sliding out
icons.dollar = () => svg(200, 200, [
  G.circle(104, 66, 64, hatch()), L(104, 50, 104, 82, { strokeWidth: 2 }),
  G.rectangle(36, 86, 128, 82, paper()),
  L(36, 86, 100, 132), L(100, 132, 164, 86),
  L(46, 186, 70, 180, { strokeWidth: 1.6 }), L(130, 182, 158, 186, { strokeWidth: 1.6 }),
]);

for (const dir of OUT) fs.mkdirSync(dir, { recursive: true });
for (const [name, fn] of Object.entries(icons)) {
  const s = fn();
  for (const dir of OUT) fs.writeFileSync(path.join(dir, `${name}.svg`), s);
}
// contact sheet
const sheet = Object.keys(icons).map(n => `<figure style="margin:0;text-align:center;font:13px sans-serif;color:#6B6760"><img src="${n}.svg" style="width:200px;height:200px"><figcaption>${n}</figcaption></figure>`).join('');
fs.writeFileSync(path.join(OUT[0], 'sheet.html'), `<!doctype html><body style="margin:0;background:${PAPER};display:grid;grid-template-columns:repeat(4,220px);gap:20px;padding:30px">${sheet}</body>`);
console.log('ok', Object.keys(icons).length);
