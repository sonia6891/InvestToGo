# ETF 袋著走 — block-toy 3D style (flat page colour, matte blocks, flat shards)
# Run: blender -b --factory-startup --python build_blocks.py -- [13|pocket|both]
import bpy, bmesh, math, os, sys, time
from mathutils import Vector, Matrix

OUT = os.path.dirname(os.path.abspath(__file__))
ONLY = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "both"
SAMPLES = int(os.environ.get("ETF_SAMPLES", "96"))
PAGE = (0.0056, 0.0056, 0.0070)  # #111114 in linear

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def new_mat(name):
    m = bpy.data.materials.new(name)
    try: m.use_nodes = True
    except Exception: pass
    return m

def principled(name, color, metallic=0.0, rough=0.5, coat=0.0):
    m = new_mat(name)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    for k, v in {"Base Color": (*color, 1), "Metallic": metallic, "Roughness": rough, "Coat Weight": coat, "Specular IOR Level": 0.25 if rough > 0.5 else 0.5}.items():
        if k in b.inputs: b.inputs[k].default_value = v
    return m

def flat(name, color):
    m = new_mat(name); nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL": nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    e = nt.nodes.new("ShaderNodeEmission"); e.inputs["Color"].default_value = (*color, 1)
    nt.links.new(e.outputs[0], out.inputs[0]); return m

GOLD = principled("Gold", (1.0, 0.60, 0.07), metallic=0.25, rough=0.62)  # matte painted gold
BLACK = principled("MatteBlack", (0.04, 0.04, 0.045), rough=0.9)
WHITE = principled("White", (0.85, 0.83, 0.80), rough=0.5)

col13 = bpy.data.collections.new("Hero13"); scene.collection.children.link(col13)
colpk = bpy.data.collections.new("Pocket"); scene.collection.children.link(colpk)
colfx = bpy.data.collections.new("Shards"); scene.collection.children.link(colfx)

def finish(me, mat, col, name, bevel=0.07, segs=5):
    for p in me.polygons: p.use_smooth = True
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me); col.objects.link(o)
    bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = bevel; bv.segments = segs; bv.limit_method = "ANGLE"
    try: bv.harden_normals = True
    except Exception: pass
    return o

def box(name, x0, x1, y0, y1, depth, mat, col, gap=0.025):
    """Block in the XY plane (Y up), extruded along Z (toward camera = +Z)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = (x0 + gap) + (v.co.x + 0.5) * ((x1 - gap) - (x0 + gap))
        v.co.y = (y0 + gap) + (v.co.y + 0.5) * ((y1 - gap) - (y0 + gap))
        v.co.z = (v.co.z) * depth
    bm.to_mesh(me); bm.free()
    return finish(me, mat, col, name)

def arc(name, cx, cy, r_in, r_out, a0, a1, depth, mat, col, segs=48, gap=0.025):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    r_in += gap; r_out -= gap
    a0r, a1r = math.radians(a0), math.radians(a1)
    ring = []
    for i in range(segs + 1):
        a = a0r + (a1r - a0r) * i / segs
        ring.append((math.cos(a), math.sin(a)))
    front_o, front_i, back_o, back_i = [], [], [], []
    for c, s in ring:
        front_o.append(bm.verts.new((cx + r_out * c, cy + r_out * s, depth / 2)))
        front_i.append(bm.verts.new((cx + r_in * c, cy + r_in * s, depth / 2)))
        back_o.append(bm.verts.new((cx + r_out * c, cy + r_out * s, -depth / 2)))
        back_i.append(bm.verts.new((cx + r_in * c, cy + r_in * s, -depth / 2)))
    for i in range(segs):
        bm.faces.new((front_i[i], front_o[i], front_o[i + 1], front_i[i + 1]))
        bm.faces.new((back_i[i + 1], back_o[i + 1], back_o[i], back_i[i]))
        bm.faces.new((front_o[i], back_o[i], back_o[i + 1], front_o[i + 1]))
        bm.faces.new((front_i[i + 1], back_i[i + 1], back_i[i], front_i[i]))
    bm.faces.new((front_i[0], back_i[0], back_o[0], front_o[0]))
    bm.faces.new((front_o[-1], back_o[-1], back_i[-1], front_i[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return finish(me, mat, col, name)

def cyl(name, r, depth, mat, col, segs=96, bevel=0.04):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=depth)
    bm.to_mesh(me); bm.free()
    return finish(me, mat, col, name, bevel=bevel, segs=4)

def sphere(name, r, mat, col, loc):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me); col.objects.link(o); o.location = loc; return o

def group(name, col, children):
    g = bpy.data.objects.new(name, None); col.objects.link(g)
    for c in children: c.parent = g
    return g

# ---------- block numerals: stroke 0.5, height 3.0, depth 0.7 ----------
D = 0.7
def digit_1(ox, mats):
    a, b = mats
    return [box("1_bar", ox + 0.25, ox + 0.85, 0.0, 3.0, D, a, col13),
            box("1_cap", ox - 0.2, ox + 0.25, 2.4, 3.0, D, b, col13)]

def digit_3(ox, mats):
    a, b = mats
    return [box("3_top", ox, ox + 1.25, 2.5, 3.0, D, b, col13),
            arc("3_arcTop", ox + 1.25, 2.25, 0.25, 0.75, -90, 90, D, a, col13),
            box("3_mid", ox + 0.55, ox + 1.25, 1.25, 1.75, D, b, col13),
            arc("3_arcBot", ox + 1.25, 0.75, 0.25, 0.75, -90, 90, D, b, col13),
            box("3_bot", ox, ox + 1.25, 0.0, 0.5, D, a, col13)]

def slab(name, x1, y1, x2, y2, w, depth, mat, col, gap=0.025):
    """Straight bar from (x1,y1) to (x2,y2), rotation baked into the mesh so parent offsets still work."""
    L = math.hypot(x2 - x1, y2 - y1) - 2 * gap; ang = math.atan2(y2 - y1, x2 - x1)
    me = bpy.data.meshes.new(name); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    ca, sa = math.cos(ang), math.sin(ang); mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    for v in bm.verts:
        lx, ly = v.co.x * L, v.co.y * (w - 2 * gap)
        v.co.x, v.co.y, v.co.z = mx + lx * ca - ly * sa, my + lx * sa + ly * ca, v.co.z * depth
    bm.to_mesh(me); bm.free()
    return finish(me, mat, col, name)

def digit_2(ox, mats):
    a, b = mats
    ex, ey = ox + 1.25 + 0.5 * math.cos(math.radians(-50)), 2.25 + 0.5 * math.sin(math.radians(-50))
    return [box("2_top", ox, ox + 1.25, 2.5, 3.0, D, b, col13),
            arc("2_arc", ox + 1.25, 2.25, 0.25, 0.75, -50, 90, D, a, col13),
            slab("2_diag", ex + 0.05, ey + 0.05, ox + 0.3, 0.42, 0.52, D, b, col13),
            box("2_bot", ox, ox + 2.0, 0.0, 0.5, D, a, col13)]

NUM = os.environ.get("ETF_NUM", "13")
parts = digit_1(0.0, (GOLD, BLACK)) + (digit_2 if NUM == "12" else digit_3)(1.25, (GOLD, BLACK))
num = group("Numerals13", col13, parts)
# centre: digits span x -0.2..3.25, y 0..3
for p in parts: p.location = (-1.52, -1.5, 0)
num.rotation_euler = (math.radians(8), math.radians(-26), 0)
num.location = (0, -0.35, 0)

# floating coin stack above, like a little crown of reward
def coin(name, r, col, loc, rot, mat=GOLD):
    c = cyl(name, r, 0.16, mat, col, bevel=0.05)
    ring = cyl(name + "_in", r * 0.66, 0.22, mat, col, bevel=0.05)
    ring.parent = c
    c.location = loc; c.rotation_euler = tuple(math.radians(v) for v in rot)
    return c
moon = coin("BigCoin", 0.95, col13, (0.45, 3.05, -0.9), (90, 0, 0))
moon.rotation_euler = (math.radians(8), math.radians(-26), 0)
for i, (x, y, z, r) in enumerate([(-0.95, 2.2, -0.3, 0.42), (-0.3, 2.85, -0.45, 0.5), (0.5, 2.95, -0.5, 0.46), (1.15, 2.45, -0.35, 0.4), (0.15, 2.2, -0.6, 0.38)]):
    sphere("Cloud%d" % i, r, BLACK, col13, (x, y, z))

# ---------- pocket: toy-like block pocket ----------
def qbez(p0, c, p1, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in [i / n for i in range(n)]]

def pocket_outline(w, h):
    # jeans-pocket shape: flat top, straight sides, soft V bottom
    TL, TR = (-w, h), (w, h)
    pts = [TL, TR]
    pts += qbez(TR, (w * 1.02, 0.0), (w * 0.92, -h * 0.35), 10)[1:]
    pts += qbez((w * 0.92, -h * 0.35), (w * 0.75, -h * 0.95), (0, -h), 14)
    pts += qbez((0, -h), (-w * 0.75, -h * 0.95), (-w * 0.92, -h * 0.35), 14)
    pts += qbez((-w * 0.92, -h * 0.35), (-w * 1.02, 0.0), TL, 10)
    return pts

def shield(name, w, h, depth, mat, col, bevel=0.14):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    pts = pocket_outline(w, h)
    fv = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
    bv_ = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
    bm.faces.new(fv); bm.faces.new(list(reversed(bv_)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((fv[i], bv_[i], bv_[j], fv[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return finish(me, mat, col, name, bevel=bevel, segs=6)

pk_back = shield("PocketBack", 1.7, 1.42, 0.35, BLACK, colpk, bevel=0.12); pk_back.location = (0, 0.3, -0.5)
pk_front = shield("PocketFront", 1.7, 1.2, 0.6, BLACK, colpk, bevel=0.22); pk_front.location = (0, -0.35, 0.1)
band = box("PocketBand", -1.76, 1.76, 0.62, 1.12, 0.7, GOLD, colpk, gap=0.0); band.location = (0, -0.35, 0.1)
rivets = [sphere("Rivet%d" % i, 0.13, GOLD, colpk, (x, 0.08, 0.42)) for i, x in enumerate((-1.2, 1.2))]
vmark = []

big = coin("PocketCoin", 0.85, colpk, (0.25, 1.3, -0.2), (0, 0, -10))
fall1 = coin("FallA", 0.45, colpk, (-1.0, 3.0, 0.1), (25, 30, -20))
fall2 = coin("FallB", 0.34, colpk, (1.05, 3.5, 0.2), (-20, -35, 15), BLACK)
pocket = group("PocketGroup", colpk, [pk_back, pk_front, band, *rivets, *vmark, big, fall1, fall2])
pocket.rotation_euler = (math.radians(8), math.radians(-24), math.radians(5))
pocket.location = (0, -0.6, 0)

# ---------- money sign: chunky block "$" (black S, gold bar) ----------
coldl = bpy.data.collections.new("Dollar"); scene.collection.children.link(coldl)
DD = 0.72
def slab2d(name, pts, depth, bevel, mat, col):
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "2D"; cu.fill_mode = "BOTH"
    cu.extrude = depth / 2 - bevel; cu.bevel_depth = bevel; cu.bevel_resolution = 8
    cu.resolution_u = 2
    sp_ = cu.splines.new("POLY"); sp_.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts): sp_.points[i].co = (x, y, 0, 1)
    sp_.use_cyclic_u = True
    tmp = bpy.data.objects.new(name + "_tmp", cu); col.objects.link(tmp)
    dg_ = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg_)); me.name = name
    bpy.data.objects.remove(tmp); bpy.data.curves.remove(cu)
    for p_ in me.polygons: p_.use_smooth = True
    try: me.set_sharp_from_angle(angle=math.radians(60))
    except Exception: pass
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me); col.objects.link(o); return o

def stroke_outline(center, w):
    """Offset a centre line both ways into a closed outline with rounded caps."""
    L, R = [], []
    for i, (x, y) in enumerate(center):
        x0, y0 = center[max(i - 1, 0)]; x1, y1 = center[min(i + 1, len(center) - 1)]
        tx, ty = x1 - x0, y1 - y0; n = math.hypot(tx, ty) or 1
        nx, ny = -ty / n, tx / n
        L.append((x + nx * w, y + ny * w)); R.append((x - nx * w, y - ny * w))
    def cap(p, q, c, fwd):
        ang0 = math.atan2(p[1] - c[1], p[0] - c[0])
        return [(c[0] + w * math.cos(ang0 + (-1 if fwd else -1) * math.pi * k / 12), c[1] + w * math.sin(ang0 - math.pi * k / 12)) for k in range(1, 12)]
    end = cap(L[-1], R[-1], center[-1], True)
    start = cap(R[0], L[0], center[0], False)
    return L + end + list(reversed(R)) + start

# S centre line: upper arc 30°→270° around (0,0.5), lower arc 90°→-150° around (0,-0.5), radius 0.5
cl = [(0.5 * math.cos(math.radians(a_)), 0.5 + 0.5 * math.sin(math.radians(a_))) for a_ in range(28, 271, 3)]
cl += [(0.5 * math.cos(math.radians(a_)), -0.5 + 0.5 * math.sin(math.radians(a_))) for a_ in range(87, -153, -3)]
s_body = slab2d("S_body", stroke_outline(cl, 0.215), DD, 0.1, BLACK, coldl)
def pill(name, x0, x1, y0, y1, depth):
    r_ = (x1 - x0) / 2; cx_ = (x0 + x1) / 2
    pts = [(cx_ + r_ * math.cos(math.radians(a_)), y1 - r_ + r_ * math.sin(math.radians(a_))) for a_ in range(0, 181, 10)]
    pts += [(cx_ + r_ * math.cos(math.radians(a_)), y0 + r_ + r_ * math.sin(math.radians(a_))) for a_ in range(180, 361, 10)]
    return slab2d(name, pts, depth, 0.09, GOLD, coldl)
bar_t = pill("S_barT", -0.17, 0.17, 0.95, 1.8, DD * 0.8)
bar_b = pill("S_barB", -0.17, 0.17, -1.8, -0.95, DD * 0.8)
for o in (s_body, bar_t, bar_b): o.rotation_euler = (0, 0, 0)
s_top, s_bot = s_body, None
dollar = group("DollarGroup", coldl, [s_body, bar_t, bar_b])
dollar.rotation_euler = (math.radians(14), math.radians(-22), math.radians(-4))

# ---------- onboarding icons ----------
ICONS = {}
# bell: black dome + rim, gold clapper and knob
colbell = bpy.data.collections.new("Bell"); scene.collection.children.link(colbell); ICONS["bell"] = colbell
def spin_profile(name, prof, mat, col, steps=128, subsurf=2):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in prof]
    for i in range(len(vs) - 1): bm.edges.new((vs[i], vs[i + 1]))
    bmesh.ops.spin(bm, geom=bm.verts[:] + bm.edges[:], cent=(0, 0, 0), axis=(0, 1, 0), angle=math.radians(360), steps=steps)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    for p_ in me.polygons: p_.use_smooth = True
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me); col.objects.link(o)
    if subsurf:
        ss = o.modifiers.new("Smooth", "SUBSURF"); ss.levels = subsurf; ss.render_levels = subsurf
    return o

def bez(p0, c0, c1, p1, n):
    out = []
    for i in range(n):
        t = i / n
        out.append(tuple((1-t)**3*p0[k] + 3*(1-t)**2*t*c0[k] + 3*(1-t)*t*t*c1[k] + t**3*p1[k] for k in range(2)))
    return out
# bell silhouette: rounded crown, waisted body, flared lip — dense and smooth
prof = [(0.0, 1.22)]
prof += bez((0.0, 1.22), (0.55, 1.22), (0.78, 1.0), (0.80, 0.55), 24)[1:]
prof += bez((0.80, 0.55), (0.82, 0.05), (0.92, -0.25), (1.18, -0.42), 24)
prof += bez((1.18, -0.42), (1.26, -0.47), (1.22, -0.58), (1.08, -0.58), 10)
prof += [(1.08, -0.58), (0.0, -0.50)]
bell = spin_profile("BellBody", prof, BLACK, colbell)
knob = sphere("BellKnob", 0.2, GOLD, colbell, (0, 1.36, 0))
clap = sphere("BellClapper", 0.28, GOLD, colbell, (0, -0.74, 0.12))
# gold rim: a true round torus hugging the lip
circ = [(1.12 + 0.13 * math.cos(math.radians(a_)), -0.52 + 0.13 * math.sin(math.radians(a_))) for a_ in range(0, 361, 15)]
rim = spin_profile("BellRim", circ, GOLD, colbell, steps=128, subsurf=1)
bellg = group("BellGroup", colbell, [bell, knob, clap, rim])
bellg.rotation_euler = (math.radians(14), math.radians(-20), math.radians(-12))

# target: concentric rings, alternating gold / black, staggered depth, gold arrow
coltg = bpy.data.collections.new("Target"); scene.collection.children.link(coltg); ICONS["target"] = coltg
rings = []
for i, (r0, r1, m, z) in enumerate([(1.05, 1.45, BLACK, 0.0), (0.62, 1.05, GOLD, 0.08), (0.25, 0.62, BLACK, 0.16), (0.0, 0.25, GOLD, 0.24)]):
    if r0 == 0.0:
        o = cyl("TgCore", r1, 0.5, m, coltg, bevel=0.06); o.location = (0, 0, z)
    else:
        o = arc("TgRing%d" % i, 0, 0, r0, r1, 0, 360, 0.5, m, coltg, segs=96); o.location = (0, 0, z)
    rings.append(o)
shaft = box("TgShaft", -0.1, 0.1, 0.0, 2.3, 0.2, GOLD, coltg, gap=0.0)
shaft.rotation_euler = Vector((0.75, 0.62, 0.42)).to_track_quat("Y", "Z").to_euler(); shaft.location = (0, 0, 0.45)
fl = box("TgFletch", -0.32, 0.32, 1.75, 2.35, 0.08, GOLD, coltg, gap=0.0); fl.parent = shaft
fl2 = box("TgFletch2", -0.04, 0.04, 1.75, 2.35, 0.64, GOLD, coltg, gap=0.0); fl2.parent = shaft
tg = group("TargetGroup", coltg, rings + [shaft])
tg.location = (-0.35, -0.35, 0)
tg.rotation_euler = (math.radians(12), math.radians(-26), 0)

# stack: four coins, gold / black alternating, slightly offset — monthly buying
colst = bpy.data.collections.new("Stack"); scene.collection.children.link(colst); ICONS["stack"] = colst
stack = []
for i in range(4):
    c = coin("Stack%d" % i, 0.95, colst, (0.06 * (i % 2) - 0.03, -0.9 + i * 0.32, 0), (90, 0, 0), GOLD if i % 2 == 0 else BLACK)
    stack.append(c)
top = coin("StackTop", 0.7, colst, (0.25, 1.05, 0.1), (25, 0, -18))
stg = group("StackGroup", colst, stack + [top])
stg.rotation_euler = (math.radians(18), math.radians(-24), 0)

# ---------- feature-page icons ----------
def pill_box(name, x0, x1, y0, y1, depth, mat, col, bevel=0.08):
    r_ = min(x1 - x0, y1 - y0) / 2
    pts = []
    for cx_, cy_, a0 in ((x1 - r_, y1 - r_, 0), (x0 + r_, y1 - r_, 90), (x0 + r_, y0 + r_, 180), (x1 - r_, y0 + r_, 270)):
        pts += [(cx_ + r_ * math.cos(math.radians(a0 + k * 10)), cy_ + r_ * math.sin(math.radians(a0 + k * 10))) for k in range(10)]
    return slab2d(name, pts, depth, bevel, mat, col)
def round_rect(name, x0, x1, y0, y1, rad, depth, mat, col, bevel=0.08):
    pts = []
    for cx_, cy_, a0 in ((x1 - rad, y1 - rad, 0), (x0 + rad, y1 - rad, 90), (x0 + rad, y0 + rad, 180), (x1 - rad, y0 + rad, 270)):
        pts += [(cx_ + rad * math.cos(math.radians(a0 + k * 10)), cy_ + rad * math.sin(math.radians(a0 + k * 10))) for k in range(10)]
    return slab2d(name, pts, depth, bevel, mat, col)
def ring2d(name, r0, r1, depth, mat, col, bevel=0.08):
    me_o = slab2d(name, [(r1 * math.cos(math.radians(a_)), r1 * math.sin(math.radians(a_))) for a_ in range(0, 360, 4)], depth, bevel, mat, col)
    cut = slab2d(name + "_cut", [(r0 * math.cos(math.radians(a_)), r0 * math.sin(math.radians(a_))) for a_ in range(0, 360, 4)], depth * 3, 0.0, mat, col)
    bo = me_o.modifiers.new("Hole", "BOOLEAN"); bo.object = cut; bo.operation = "DIFFERENCE"
    cut.hide_render = True; cut.hide_viewport = True
    return me_o

# magnifier: black ring, white lens, gold handle
colmag = bpy.data.collections.new("Magnifier"); scene.collection.children.link(colmag); ICONS["magnifier"] = colmag
mring = ring2d("MagRing", 0.62, 0.95, 0.42, BLACK, colmag)
lens = slab2d("MagLens", [(0.64 * math.cos(math.radians(a_)), 0.64 * math.sin(math.radians(a_))) for a_ in range(0, 360, 4)], 0.16, 0.06, WHITE, colmag)
handle = pill_box("MagHandle", -0.2, 0.2, -1.95, -0.85, 0.44, GOLD, colmag)
handle.rotation_euler = (0, 0, math.radians(40))
magg = group("MagGroup", colmag, [mring, lens, handle])
magg.rotation_euler = (math.radians(12), math.radians(-24), math.radians(-6)); magg.location = (0.25, 0.35, 0)

# bars: three rising pill bars, black / gold / gold
colbar = bpy.data.collections.new("Bars"); scene.collection.children.link(colbar); ICONS["bars"] = colbar
b1 = pill_box("Bar1", -1.05, -0.5, -1.2, -0.1, 0.55, BLACK, colbar)
b2 = pill_box("Bar2", -0.28, 0.28, -1.2, 0.55, 0.55, GOLD, colbar)
b3 = pill_box("Bar3", 0.5, 1.05, -1.2, 1.25, 0.55, BLACK, colbar)
arrow = pill_box("BarArrow", -1.25, 1.25, -0.11, 0.11, 0.2, GOLD, colbar)
arrow.rotation_euler = (0, 0, math.radians(28)); arrow.location = (0, 0.55, 0.45)
barg = group("BarsGroup", colbar, [b1, b2, b3, arrow])
barg.rotation_euler = (math.radians(12), math.radians(-24), 0)

# calculator: black body, cream screen, gold keys
colcal = bpy.data.collections.new("Calc"); scene.collection.children.link(colcal); ICONS["calc"] = colcal
body = round_rect("CalcBody", -0.95, 0.95, -1.3, 1.3, 0.3, 0.55, BLACK, colcal)
scr = round_rect("CalcScreen", -0.68, 0.68, 0.45, 1.02, 0.12, 0.2, WHITE, colcal, bevel=0.05); scr.location = (0, 0, 0.25)
keys = []
for i in range(3):
    for j in range(3):
        k = round_rect("Key%d%d" % (i, j), -0.17, 0.17, -0.15, 0.15, 0.08, 0.22, GOLD if (i + j) % 2 == 0 else WHITE, colcal, bevel=0.05)
        k.location = (-0.48 + j * 0.48, 0.0 - i * 0.4, 0.27); keys.append(k)
calg = group("CalcGroup", colcal, [body, scr] + keys)
calg.rotation_euler = (math.radians(14), math.radians(-26), math.radians(-4))

# crown: gold band with three peaks topped by black balls
colcr = bpy.data.collections.new("Crown"); scene.collection.children.link(colcr); ICONS["crown"] = colcr
cr_pts = [(-1.15, -0.75), (1.15, -0.75), (1.2, 0.75), (0.6, 0.05), (0.0, 0.95), (-0.6, 0.05), (-1.2, 0.75)]
dense = []
for i in range(len(cr_pts)):
    a_, b_ = cr_pts[i], cr_pts[(i + 1) % len(cr_pts)]
    for k in range(8): dense.append((a_[0] + (b_[0] - a_[0]) * k / 8, a_[1] + (b_[1] - a_[1]) * k / 8))
crown = slab2d("Crown", dense, 0.55, 0.12, GOLD, colcr)
band2 = pill_box("CrownBand", -1.2, 1.2, -0.95, -0.55, 0.62, BLACK, colcr)
balls = [sphere("CrBall%d" % i, 0.2, BLACK, colcr, (x, y, 0)) for i, (x, y) in enumerate(((-1.2, 0.85), (0.0, 1.07), (1.2, 0.85)))]
crg = group("CrownGroup", colcr, [crown, band2] + balls)
crg.rotation_euler = (math.radians(14), math.radians(-24), math.radians(-6))

# ---------- flat shards behind (pure colour, no shading) ----------
def shards(spec, cx=0.0, cy=0.4, z=-6.0):
    for i, (ang, half, r0, r1, colr) in enumerate(spec):
        me = bpy.data.meshes.new("Shard%d" % i); bm = bmesh.new()
        a = math.radians(ang); h = math.radians(half)
        p_tip = (cx + r0 * math.cos(a), cy + r0 * math.sin(a), z)
        p1 = (cx + r1 * math.cos(a - h), cy + r1 * math.sin(a - h), z)
        p2 = (cx + r1 * math.cos(a + h), cy + r1 * math.sin(a + h), z)
        bm.faces.new([bm.verts.new(p) for p in (p_tip, p1, p2)])
        bm.to_mesh(me); bm.free(); me.materials.append(flat("ShardM%d" % i, colr))
        o = bpy.data.objects.new("Shard%d" % i, me); colfx.objects.link(o)
        for attr in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter", "visible_shadow"):
            setattr(o, attr, False)
W, G, P, B = (0.9, 0.88, 0.84), (0.95, 0.52, 0.06), (0.95, 0.30, 0.28), (0.12, 0.35, 0.95)
shards([(90, 5, 3.2, 9, W), (62, 2.2, 3.4, 9, G), (128, 6, 3.0, 9, W), (160, 3, 3.3, 9, P), (200, 7, 3.0, 9, W),
        (232, 3, 3.6, 9, G), (268, 4, 3.4, 9, W), (300, 6, 3.0, 9, W), (335, 2.5, 3.4, 9, B), (20, 7, 3.1, 9, W)])

# ---------- light, world, camera ----------
def area(name, loc, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA"); l.energy = energy; l.size = size; l.color = color
    o = bpy.data.objects.new(name, l); scene.collection.objects.link(o); o.location = loc
    o.rotation_euler = (Vector((0, 0.5, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
area("Key", (-4, 8, 6), 1300, 7)
def card(name, loc, w, h, strength):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5); bm.to_mesh(me); bm.free()
    me.materials.append(flat(name + "M", (strength, strength * 0.97, strength * 0.9)))
    o = bpy.data.objects.new(name, me); scene.collection.objects.link(o)
    o.location = loc; o.scale = (w, h, 1)
    o.rotation_euler = (Vector((0, 0.5, 0)) - Vector(loc)).to_track_quat("Z", "Y").to_euler()
    o.visible_camera = False; o.visible_shadow = False
# no reflection cards: matte look
area("Fill", (6, -1, 5), 260, 6, (0.9, 0.93, 1.0))
area("Rim", (3, 5, -5), 250, 4, (1.0, 0.95, 0.9))

world = bpy.data.worlds.new("W"); scene.world = world
try: world.use_nodes = True
except Exception: pass
wn = world.node_tree
for n in list(wn.nodes):
    if n.type != "OUTPUT_WORLD": wn.nodes.remove(n)
wout = next(n for n in wn.nodes if n.type == "OUTPUT_WORLD")
lp = wn.nodes.new("ShaderNodeLightPath")
bg_cam = wn.nodes.new("ShaderNodeBackground"); bg_cam.inputs["Color"].default_value = (*PAGE, 1)
bg_lit = wn.nodes.new("ShaderNodeBackground"); bg_lit.inputs["Color"].default_value = (0.35, 0.33, 0.31, 1)
mix = wn.nodes.new("ShaderNodeMixShader")
wn.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
wn.links.new(bg_lit.outputs[0], mix.inputs[1]); wn.links.new(bg_cam.outputs[0], mix.inputs[2])
wn.links.new(mix.outputs[0], wout.inputs[0])

cam_d = bpy.data.cameras.new("Cam"); cam_d.type = "ORTHO"; cam_d.ortho_scale = 7.8
cam = bpy.data.objects.new("Cam", cam_d); scene.collection.objects.link(cam); scene.camera = cam
cam.location = (0, 0.75, 20); cam.rotation_euler = (0, 0, 0)

r = scene.render
r.engine = "CYCLES"; r.resolution_x = 1080; r.resolution_y = 1350
scene.cycles.samples = SAMPLES; scene.cycles.use_denoising = True
scene.view_settings.view_transform = "Standard"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for t in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = t; prefs.get_devices()
            if any(d.type != "CPU" for d in prefs.devices):
                for d in prefs.devices: d.use = True
                scene.cycles.device = "GPU"; break
        except Exception: continue
except Exception as e:
    print("gpu", e)

def shoot(tag, show, path):
    for c in (col13, colpk, coldl, *ICONS.values()): c.hide_render = c is not show
    r.filepath = path; t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print("RENDERED", tag, path, "%.1fs" % (time.time() - t0))

CUT = os.environ.get("ETF_CUTOUT") == "1"
if CUT:
    r.film_transparent = True; colfx.hide_render = True
    r.resolution_x = 1080; r.resolution_y = 1080
    cam.location = (0, 1.05, 20); cam_d.ortho_scale = 6.6
SUF = "_cut" if CUT else ""
ICON = os.environ.get("ETF_ICON") == "1"
if ICON:
    for nm in ("FallA", "FallB"):
        for o in [bpy.data.objects[nm]] + list(bpy.data.objects[nm].children): o.hide_render = True
    cam.location = (0, 0.15, 20); cam_d.ortho_scale = 4.4
    SUF = "_icon"
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "etf_blocks.blend"))
if ONLY in ("13", "both"): shoot("13", col13, os.path.join(OUT, "blocks_%s%s.png" % (NUM, SUF)))
if ONLY in ("pocket", "both"): shoot("pocket", colpk, os.path.join(OUT, "blocks_pocket%s.png" % SUF))
if ONLY == "dollar":
    cam.location = (0, 0, 20); cam_d.ortho_scale = 4.4
    shoot("dollar", coldl, os.path.join(OUT, "blocks_dollar%s.png" % SUF))
if ONLY == "icons":
    cam.location = (0, 0.1, 20); cam_d.ortho_scale = 3.9
    r.resolution_x = r.resolution_y = 720
    for name, col in ICONS.items():
        shoot(name, col, os.path.join(OUT, "icon_%s.png" % name))
if ONLY == "skins":
    # same "$", different worlds: a skin swaps material and form, not just colour
    def gummy(name, color):
        m = principled(name, color, rough=0.18, coat=1.0)
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for k, v in {"Subsurface Weight": 1.0, "Subsurface Scale": 0.25, "Coat Roughness": 0.05}.items():
            if k in b.inputs: b.inputs[k].default_value = v
        return m
    def wood(name, light, dark, scale=3.0):
        m = principled(name, light, rough=0.55); nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tc = nt.nodes.new("ShaderNodeTexCoord")
        wv = nt.nodes.new("ShaderNodeTexWave"); wv.wave_type = "RINGS"
        wv.inputs["Scale"].default_value = scale; wv.inputs["Distortion"].default_value = 3.5; wv.inputs["Detail"].default_value = 3.0
        cr = nt.nodes.new("ShaderNodeValToRGB")
        cr.color_ramp.elements[0].color = (*dark, 1); cr.color_ramp.elements[1].color = (*light, 1)
        cr.color_ramp.elements[0].position = 0.25; cr.color_ramp.elements[1].position = 0.75
        nt.links.new(tc.outputs["Object"], wv.inputs["Vector"]); nt.links.new(wv.outputs["Fac"], cr.inputs[0])
        nt.links.new(cr.outputs["Color"], b.inputs["Base Color"])
        return m
    parts = [s_body, bar_t, bar_b]
    def set_mats(body, bars):
        for o, m in zip(parts, (body, bars, bars)):
            o.data.materials.clear(); o.data.materials.append(m)
    cam.location = (0, 0, 20); cam_d.ortho_scale = 4.4
    r.resolution_x = r.resolution_y = 900
    SK = {
        "gummy": lambda: set_mats(gummy("GumPink", (1.0, 0.36, 0.55)), gummy("GumMint", (0.30, 0.88, 0.70))),
        "wood": lambda: set_mats(wood("Walnut", (0.58, 0.34, 0.15), (0.40, 0.21, 0.08), 1.3), principled("RedPaint", (0.85, 0.12, 0.08), rough=0.45)),
        "voxel": lambda: set_mats(principled("PixYellow", (1.0, 0.75, 0.05), rough=0.7), principled("PixPink", (1.0, 0.18, 0.45), rough=0.7)),
    }
    for name, apply in SK.items():
        apply()
        if name == "voxel":
            for o in parts:
                rm = o.modifiers.new("Vox", "REMESH"); rm.mode = "BLOCKS"; rm.octree_depth = 5; rm.scale = 0.95
                rm.use_remove_disconnected = False
                bv = o.modifiers.new("VoxBev", "BEVEL"); bv.width = 0.012; bv.segments = 2
        shoot(name, coldl, os.path.join(OUT, "skin_%s.png" % name))
if ONLY == "one":
    # new-user state: a lone "1" (first month), same scene as the 13
    for o in col13.objects:
        if o.name.startswith(("2_", "3_")): o.hide_render = True
    for p in parts:
        if p.name.startswith("1_"): p.location = (-0.33, -1.5, 0)
    # a lone 1 needs weight: chunky black foot, bigger cap
    foot = box("1_foot", -0.20, 1.30, 0.0, 0.5, D * 1.12, BLACK, col13); foot.parent = num; foot.location = (-0.33, -1.5, 0)
    bpy.data.objects["1_cap"].scale = (1.6, 1.0, 1.0)
    shoot("one", col13, os.path.join(OUT, "blocks_1%s.png" % SUF))
if ONLY == "skinall":
    # every asset in one skin (ETF_SKIN=gummy|wood|voxel): swap the three base materials, voxelise for pixel
    SKIN = os.environ.get("ETF_SKIN", "gummy")
    def gummy_m(name, color):
        m = principled(name, color, rough=0.18, coat=1.0)
        b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for k, v in {"Subsurface Weight": 1.0, "Subsurface Scale": 0.25, "Coat Roughness": 0.05}.items():
            if k in b.inputs: b.inputs[k].default_value = v
        return m
    def wood_m(name, light, dark, scale=1.3):
        m = principled(name, light, rough=0.55); nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tc = nt.nodes.new("ShaderNodeTexCoord"); wv = nt.nodes.new("ShaderNodeTexWave"); wv.wave_type = "RINGS"
        wv.inputs["Scale"].default_value = scale; wv.inputs["Distortion"].default_value = 3.5; wv.inputs["Detail"].default_value = 3.0
        cr = nt.nodes.new("ShaderNodeValToRGB")
        cr.color_ramp.elements[0].color = (*dark, 1); cr.color_ramp.elements[1].color = (*light, 1)
        cr.color_ramp.elements[0].position = 0.25; cr.color_ramp.elements[1].position = 0.75
        nt.links.new(tc.outputs["Object"], wv.inputs["Vector"]); nt.links.new(wv.outputs["Fac"], cr.inputs[0])
        nt.links.new(cr.outputs["Color"], b.inputs["Base Color"]); return m
    MAP = {
        "gummy": {"MatteBlack": gummy_m("G_Pink", (1.0, 0.36, 0.55)), "Gold": gummy_m("G_Mint", (0.30, 0.88, 0.70)), "White": gummy_m("G_Cream", (1.0, 0.93, 0.80))},
        "wood": {"MatteBlack": wood_m("W_Walnut", (0.58, 0.34, 0.15), (0.40, 0.21, 0.08)), "Gold": principled("W_Red", (0.85, 0.12, 0.08), rough=0.45), "White": wood_m("W_Maple", (0.92, 0.76, 0.52), (0.80, 0.62, 0.38), 1.6)},
        "sketch": {"MatteBlack": flat("S_Paper", (0.955, 0.94, 0.90)), "Gold": flat("S_Marker", (0.93, 0.72, 0.22)), "White": flat("S_Paper2", (0.955, 0.94, 0.90))},
        "voxel": {"MatteBlack": principled("V_Yellow", (1.0, 0.75, 0.05), rough=0.7), "Gold": principled("V_Pink", (1.0, 0.18, 0.45), rough=0.7), "White": principled("V_Cyan", (0.24, 0.88, 1.0), rough=0.7)},
    }[SKIN]
    for me in bpy.data.meshes:
        for i, m in enumerate(me.materials):
            if m and m.name in MAP: me.materials[i] = MAP[m.name]
    if SKIN == "voxel":
        bpy.context.view_layer.update()
        for o in bpy.data.objects:
            if o.type != "MESH" or o.users_collection[0] is colfx: continue
            d = max(o.dimensions) or 1.0
            rm = o.modifiers.new("Vox", "REMESH"); rm.mode = "BLOCKS"; rm.scale = 0.95; rm.use_remove_disconnected = False
            rm.octree_depth = max(3, min(7, round(math.log2(d / 0.09))))
            bv = o.modifiers.new("VoxBev", "BEVEL"); bv.width = 0.01; bv.segments = 2
    if SKIN == "sketch":
        # hand-drawn: paper-white fills, one marker colour, wobbly ink outlines (Freestyle)
        r.use_freestyle = True; r.line_thickness_mode = "ABSOLUTE"; r.line_thickness = 1.0
        vl = scene.view_layers[0]; vl.use_freestyle = True
        fs = vl.freestyle_settings; fs.crease_angle = math.radians(125)
        ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("Ink")
        ls.select_silhouette = True; ls.select_border = True; ls.select_crease = False; ls.select_external_contour = True
        st = ls.linestyle or bpy.data.linestyles.new("Ink"); ls.linestyle = st; st.color = (0.08, 0.08, 0.08); st.thickness = 7.0; st.thickness_position = "CENTER"; st.caps = "ROUND"
        st.use_length_min = True; st.length_min = 6.0
        sp_ = st.geometry_modifiers.new("Samp", "SAMPLING"); sp_.sampling = 3.0
        nz = st.geometry_modifiers.new("Wobble", "PERLIN_NOISE_1D"); nz.frequency = 3; nz.amplitude = 1.2
        pass  # no overshoot: it breaks on closed strokes
    base = os.path.join(OUT, "skins", SKIN); os.makedirs(base, exist_ok=True)
    r.film_transparent = True; colfx.hide_render = True
    if os.environ.get("ETF_NUMONLY"):
        cam.location = (0, 1.05, 20); cam_d.ortho_scale = 6.6; r.resolution_x = r.resolution_y = 1080
        shoot("13", col13, os.path.join(base, "blocks_%s.png" % NUM)); raise SystemExit
    # icons
    cam.location = (0, 0.1, 20); cam_d.ortho_scale = 3.9; r.resolution_x = r.resolution_y = 720
    for name, col in ICONS.items(): shoot(name, col, os.path.join(base, "icon_%s.png" % name))
    # dollar
    cam.location = (0, 0, 20); cam_d.ortho_scale = 4.4; r.resolution_x = r.resolution_y = 900
    shoot("dollar", coldl, os.path.join(base, "dollar.png"))
    # pocket icon (no falling coins)
    for nm in ("FallA", "FallB"):
        for o in [bpy.data.objects[nm]] + list(bpy.data.objects[nm].children): o.hide_render = True
    cam.location = (0, -0.35, 20); cam_d.ortho_scale = 4.7; r.resolution_x = r.resolution_y = 720
    shoot("pocket", colpk, os.path.join(base, "pocket_icon.png"))
    # 13 and a lone 1
    cam.location = (0, 1.05, 20); cam_d.ortho_scale = 6.6; r.resolution_x = r.resolution_y = 1080
    shoot("13", col13, os.path.join(base, "blocks_%s.png" % NUM))
    if os.environ.get("ETF_NUMONLY"): raise SystemExit
    for o in col13.objects:
        if o.name.startswith(("2_", "3_")): o.hide_render = True
    for p in parts:
        if p.name.startswith("1_"): p.location = (-0.33, -1.5, 0)
    foot = box("1_foot", -0.20, 1.30, 0.0, 0.5, D * 1.12, MAP["MatteBlack"], col13); foot.parent = num; foot.location = (-0.33, -1.5, 0)
    if SKIN == "voxel":
        rm = foot.modifiers.new("Vox", "REMESH"); rm.mode = "BLOCKS"; rm.octree_depth = 5; rm.scale = 0.95
    bpy.data.objects["1_cap"].scale = (1.6, 1.0, 1.0)
    shoot("one", col13, os.path.join(base, "blocks_1.png"))
