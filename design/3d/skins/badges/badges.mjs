// One icon per skin for the skin picker, each drawn in that skin's own style.
import rough from 'roughjs';
import fs from 'node:fs';
import path from 'node:path';

const gen = rough.generator();
const wrap = body => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="200" height="200">${body}</svg>`;

// 像素 · pixel star made of squares, hard shadow
function pixel() {
  const rows = ['....#....', '...###...', '#########', '.#######.', '..#####..', '.###.###.', '.##...##.'];
  const u = 9, ox = 10, oy = 16; let sh = '', fg = '';
  rows.forEach((r, y) => [...r].forEach((c, x) => {
    if (c !== '#') return;
    sh += `<rect x="${ox + x * u + 4}" y="${oy + y * u + 4}" width="${u}" height="${u}" fill="#0E1030"/>`;
    fg += `<rect x="${ox + x * u}" y="${oy + y * u}" width="${u}" height="${u}" fill="${y < 2 ? '#FFFFFF' : y < 4 ? '#FFD23F' : '#FF3D8B'}"/>`;
  }));
  return wrap(sh + fg);
}

// 黑金 · matte gold hexagon with a soft bevel, the quick-pick button shape
function blackgold() {
  const hex = r => Array.from({ length: 6 }, (_, i) => { const a = Math.PI / 6 + i * Math.PI / 3; return `${50 + Math.cos(a) * r},${52 + Math.sin(a) * r}`; }).join(' ');
  return wrap(`<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F7C94E"/><stop offset="1" stop-color="#D99A1E"/></linearGradient></defs>
    <polygon points="${hex(40)}" fill="#8A5F10" transform="translate(0 5)"/>
    <polygon points="${hex(40)}" fill="url(#g)"/>
    <polygon points="${hex(26)}" fill="#1A1A1D"/>
    <polygon points="${hex(26)}" fill="none" stroke="#F4F1E8" stroke-width="3"/>`);
}

// 縫線 · four-hole sewing button with a cross-stitch, on a paper cut-out
function stitch() {
  const out = [];
  out.push(`<circle cx="52" cy="54" r="38" fill="rgba(80,52,24,.24)"/>`);
  for (const p of gen.toPaths(gen.circle(50, 50, 76, { fill: '#C9573F', fillStyle: 'solid', stroke: 'none', roughness: 0.5, seed: 3 })))
    out.push(`<path d="${p.d}" fill="${p.fill === 'none' ? 'none' : '#C9573F'}"/>`);
  out.push(`<circle cx="50" cy="50" r="31" fill="none" stroke="#F7F0E1" stroke-width="2.2" stroke-dasharray="5 4"/>`);
  for (const [x, y] of [[41, 41], [59, 41], [41, 59], [59, 59]]) out.push(`<circle cx="${x}" cy="${y}" r="5" fill="#7E2F20"/>`);
  out.push(`<path d="M41 41 L59 59 M59 41 L41 59" stroke="#2F4A6D" stroke-width="3.4" stroke-linecap="round"/>`);
  return wrap(out.join(''));
}

// 手繪 · pencil doodle, ink lines + marker hatch
function sketch() {
  const o = (x = {}) => ({ stroke: '#1F1F1F', strokeWidth: 2.4, roughness: 1.2, bowing: 1.2, seed: 21, ...x });
  const shapes = [
    gen.polygon([[24, 70], [66, 28], [78, 40], [36, 82]], o({ fill: '#F2D16B', fillStyle: 'hachure', hachureGap: 4, fillWeight: 1.5 })),
    gen.polygon([[24, 70], [36, 82], [16, 90]], o({ fill: '#FAF8F3', fillStyle: 'solid' })),
    gen.line(66, 28, 78, 40, o({ strokeWidth: 3 })),
    gen.polygon([[66, 28], [74, 20], [86, 32], [78, 40]], o()),
    gen.line(18, 88, 22, 84, o({ strokeWidth: 4 })),
  ];
  return wrap(shapes.flatMap(s => gen.toPaths(s)).map(p => `<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${p.fill && p.fill !== 'none' ? p.fill : 'none'}" stroke-linecap="round" stroke-linejoin="round"/>`).join(''));
}

const set = { pixel: pixel(), blackgold: blackgold(), stitch: stitch(), sketch: sketch() };
for (const dir of process.argv.slice(2)) {
  fs.mkdirSync(dir, { recursive: true });
  for (const [n, s] of Object.entries(set)) fs.writeFileSync(path.join(dir, `${n}.svg`), s);
}
console.log('ok', Object.keys(set).join(' '));
