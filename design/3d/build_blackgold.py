import bpy, bmesh, math, os, sys, time
from mathutils import Vector

OUT = r"D:\Projects\ETFToGo\design\3d"
os.makedirs(OUT, exist_ok=True)
ONLY = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "both"
SAMPLES = int(os.environ.get("ETF_SAMPLES", "128"))

# ---------- reset ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------- helpers ----------
def mat_principled(name, color, metallic=0.0, rough=0.5, coat=0.0, coat_rough=0.05, sheen=0.0, sheen_tint=(1, 1, 1)):
    m = bpy.data.materials.new(name)
    try: m.use_nodes = True
    except Exception: pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    vals = {"Base Color": (*color, 1), "Metallic": metallic, "Roughness": rough,
            "Coat Weight": coat, "Coat Roughness": coat_rough, "Sheen Weight": sheen, "Sheen Tint": (*sheen_tint, 1)}
    for k, v in vals.items():
        if k in b.inputs: b.inputs[k].default_value = v
    return m, b

def mat_emission(name, color, strength):
    m = bpy.data.materials.new(name)
    try: m.use_nodes = True
    except Exception: pass
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL": nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*color, 1); e.inputs["Strength"].default_value = strength
    nt.links.new(e.outputs[0], out.inputs[0])
    return m

def link(obj, col):
    col.objects.link(obj); return obj

def smooth_mesh(me, angle=40):
    for p in me.polygons: p.use_smooth = True
    try: me.set_sharp_from_angle(angle=math.radians(angle))
    except Exception: pass

def cylinder(name, r, d, mat, col, segs=128, bevel=0.0):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=d)
    bm.to_mesh(me); bm.free(); smooth_mesh(me, 30)
    o = link(bpy.data.objects.new(name, me), col); me.materials.append(mat)
    if bevel:
        bv = o.modifiers.new("Bevel", "BEVEL"); bv.width = bevel; bv.segments = 4; bv.limit_method = "ANGLE"
        try: bv.harden_normals = True
        except Exception: pass
    return o

def text_mesh(name, body, font, size, extrude, bevel, mat, col, align_y="BOTTOM"):
    cu = bpy.data.curves.new(name + "_c", "FONT"); cu.body = body; cu.font = font; cu.size = size
    cu.extrude = extrude; cu.bevel_depth = bevel; cu.bevel_resolution = 5
    cu.align_x = "CENTER"; cu.align_y = align_y
    tmp = bpy.data.objects.new(name + "_tmp", cu); col.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg)); me.name = name
    bpy.data.objects.remove(tmp); bpy.data.curves.remove(cu)
    smooth_mesh(me, 35); me.materials.append(mat)
    return link(bpy.data.objects.new(name, me), col)

def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

def area(name, loc, target, energy, size, color):
    l = bpy.data.lights.new(name, "AREA"); l.energy = energy; l.size = size; l.color = color
    o = link(bpy.data.objects.new(name, l), base); o.location = loc; look_at(o, target); return o

# ---------- collections ----------
base = bpy.data.collections.new("Stage"); scene.collection.children.link(base)
c13 = bpy.data.collections.new("Hero13"); scene.collection.children.link(c13)
cpk = bpy.data.collections.new("Pocket"); scene.collection.children.link(cpk)

# ---------- materials ----------
GOLD, _ = mat_principled("Gold", (1.0, 0.60, 0.16), metallic=1.0, rough=0.16)
GOLD_DK, _ = mat_principled("GoldDark", (0.72, 0.40, 0.08), metallic=1.0, rough=0.32)
BLACK_GLOSS, _ = mat_principled("BlackGloss", (0.010, 0.010, 0.012), rough=0.28, coat=1.0, coat_rough=0.04)
BLACK_MATTE, _ = mat_principled("BlackPedestal", (0.018, 0.018, 0.021), rough=0.5, coat=0.6, coat_rough=0.12)
FLOOR, _ = mat_principled("Floor", (0.006, 0.006, 0.007), rough=0.42)
FABRIC, fb = mat_principled("PocketFabric", (0.010, 0.010, 0.012), rough=0.7, sheen=0.35, sheen_tint=(1.0, 0.8, 0.5))
FABRIC_BACK, _ = mat_principled("PocketBack", (0.005, 0.005, 0.006), rough=0.85, sheen=0.2)
# twill bump on the pocket fabric
nt = FABRIC.node_tree
wave = nt.nodes.new("ShaderNodeTexWave"); wave.inputs["Scale"].default_value = 95
wave.bands_direction = "DIAGONAL"
bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.25
nt.links.new(wave.outputs["Fac"], bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"], fb.inputs["Normal"])
RAY_GOLD = mat_emission("RayGold", (1.0, 0.62, 0.16), 0.55)
RAY_WHITE = mat_emission("RayWhite", (1.0, 0.95, 0.85), 0.12)

font = bpy.data.fonts.load(r"C:\Windows\Fonts\impact.ttf")

# ---------- world & stage ----------
world = bpy.data.worlds.new("W"); scene.world = world
try: world.use_nodes = True
except Exception: pass
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.004, 0.004, 0.005, 1); bg.inputs["Strength"].default_value = 1.0

fme = bpy.data.meshes.new("Floor"); bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30); bm.to_mesh(fme); bm.free()
floor = link(bpy.data.objects.new("Floor", fme), base); fme.materials.append(FLOOR)

# backdrop with radial gold glow
bme = bpy.data.meshes.new("Backdrop"); bm = bmesh.new()
bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30); bm.to_mesh(bme); bm.free()
backdrop = link(bpy.data.objects.new("Backdrop", bme), base)
backdrop.location = (0, 9, 6); backdrop.rotation_euler = (math.radians(90), 0, 0)
BD = bpy.data.materials.new("BackdropGlow")
try: BD.use_nodes = True
except Exception: pass
n = BD.node_tree; out = next(x for x in n.nodes if x.type == "OUTPUT_MATERIAL")
for x in list(n.nodes):
    if x.type != "OUTPUT_MATERIAL": n.nodes.remove(x)
out = next(x for x in n.nodes if x.type == "OUTPUT_MATERIAL")
tc = n.nodes.new("ShaderNodeTexCoord"); mp = n.nodes.new("ShaderNodeMapping")
mp.inputs["Location"].default_value = (0, 0.25, 0); mp.inputs["Scale"].default_value = (1 / 6.5, 1 / 6.5, 1 / 6.5)
gr = n.nodes.new("ShaderNodeTexGradient"); gr.gradient_type = "SPHERICAL"
ramp = n.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1); ramp.color_ramp.elements[1].color = (0.30, 0.16, 0.025, 1)
em = n.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = 0.6
n.links.new(tc.outputs["Object"], mp.inputs["Vector"]); n.links.new(mp.outputs[0], gr.inputs["Vector"])
n.links.new(gr.outputs["Fac"], ramp.inputs["Fac"]); n.links.new(ramp.outputs["Color"], em.inputs["Color"])
n.links.new(em.outputs[0], out.inputs[0])
bme.materials.append(BD)

def rays(name, center, angles, mat, half_deg=1.4, radius=16):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    c = bm.verts.new(center)
    for a in angles:
        a1, a2 = math.radians(a - half_deg), math.radians(a + half_deg)
        v1 = bm.verts.new((center[0] + radius * math.cos(a1), center[1], center[2] + radius * math.sin(a1)))
        v2 = bm.verts.new((center[0] + radius * math.cos(a2), center[1], center[2] + radius * math.sin(a2)))
        bm.faces.new((c, v1, v2))
    bm.to_mesh(me); bm.free(); me.materials.append(mat)
    o = link(bpy.data.objects.new(name, me), base)
    o.visible_shadow = False
    return o

rays("RaysGold", (0, 8.9, 2.9), [10, 64, 118, 172, 226, 280, 334], RAY_GOLD, half_deg=0.8)
# rays("RaysWhite", (0, 8.85, 3.4), [37, 91, 145, 199, 253, 307], RAY_WHITE, half_deg=0.5)

# lights
area("Key", (-4.5, -5.5, 7.5), (0, 0, 1.6), 1800, 4.0, (1.0, 0.93, 0.82))
area("Rim", (4.5, 4.0, 5.5), (0, 0, 1.6), 1600, 3.0, (1.0, 0.78, 0.45))
area("RimL", (-5.0, 3.5, 3.5), (0, 0, 1.6), 900, 2.5, (1.0, 0.85, 0.6))
area("Fill", (5.5, -6.5, 2.0), (0, 0, 1.4), 260, 5.0, (0.85, 0.88, 1.0))
def card(name, loc, target, w, h, strength, color=(1.0, 0.92, 0.78)):
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1); bm.to_mesh(me); bm.free()
    me.materials.append(mat_emission(name + "M", color, strength))
    o = link(bpy.data.objects.new(name, me), base); o.scale = (w / 2, h / 2, 1)
    o.location = loc; look_at(o, target); o.rotation_euler.rotate_axis("X", math.radians(180))
    o.visible_camera = False; o.visible_shadow = False
    return o
card("FrontCard", (0.0, -9.5, 0.5), (0, 0, 2.8), 14, 2.6, 3.0)
card("FrontCardHi", (-1.0, -13, 6.0), (0, 0, 2), 12, 5, 1.6)
card("SideCardL", (-9, -5, 4), (0, 0, 2), 5, 8, 1.6, (1.0, 0.85, 0.6))
card("TopCard", (0, -2, 11), (0, 0, 2), 10, 4, 1.4)
sp = bpy.data.lights.new("TopSpot", "SPOT"); sp.energy = 2600; sp.spot_size = math.radians(42); sp.spot_blend = 0.6
sp.color = (1.0, 0.88, 0.65); sp.shadow_soft_size = 0.6
spo = link(bpy.data.objects.new("TopSpot", sp), base); spo.location = (0, -1.2, 10); look_at(spo, (0, 0, 0.5))

# ---------- coin factory ----------
def coin(name, col, r=0.42, d=0.11, loc=(0, 0, 0), rot=(0, 0, 0)):
    o = cylinder(name, r, d, GOLD, col, bevel=0.025)
    inner = cylinder(name + "_ring", r * 0.74, d + 0.02, GOLD_DK, col, bevel=0.012)
    inner.parent = o
    for side in (1, -1):
        s = text_mesh(name + "_sym%d" % side, "$", font, r * 1.15, 0.018, 0.006, GOLD, col, align_y="CENTER")
        s.parent = o; s.location = (0, 0, side * (d / 2 + 0.02))
        if side < 0: s.rotation_euler = (math.radians(180), 0, 0)
    o.location = loc; o.rotation_euler = tuple(math.radians(a) for a in rot)
    return o

# ---------- Hero 13 ----------
ped = cylinder("Pedestal", 2.6, 0.55, BLACK_GLOSS, c13, bevel=0.06); ped.location = (0, 0, 0.275)
band = cylinder("PedestalBand", 2.63, 0.07, GOLD, c13, bevel=0.02); band.location = (0, 0, 0.5)
ped2 = cylinder("PedestalBase", 2.9, 0.12, BLACK_GLOSS, c13, bevel=0.04); ped2.location = (0, 0, 0.06)

grp = link(bpy.data.objects.new("Numerals", None), c13)
one = text_mesh("Digit1", "1", font, 3.9, 0.55, 0.07, GOLD, c13)
three = text_mesh("Digit3", "3", font, 3.9, 0.55, 0.07, BLACK_GLOSS, c13)
for o in (one, three):
    o.rotation_euler = (math.radians(90), 0, 0)
dg = bpy.context.evaluated_depsgraph_get()
def width(o):
    xs = [v.co.x for v in o.data.vertices]; return min(xs), max(xs)
a0, a1 = width(one); b0, b1 = width(three)
gap = 0.55
total = (a1 - a0) + gap + (b1 - b0)
def low(o):
    return min(v.co.y for v in o.data.vertices)  # local Y becomes world Z after the 90deg X rotation
one.location = (-total / 2 - a0, 0, 0.55 - low(one))
three.location = (-total / 2 + (a1 - a0) + gap - b0, 0, 0.55 - low(three))
one.parent = grp; three.parent = grp
grp.rotation_euler = (0, 0, math.radians(-10))

coin("Coin13a", c13, loc=(-3.1, -1.4, 0.06), rot=(0, 0, 0))
coin("Coin13b", c13, loc=(2.9, -1.9, 0.40), rot=(64, 10, 30))
coin("Coin13c", c13, r=0.36, loc=(-2.7, -0.8, 4.6), rot=(70, -20, -40))
coin("Coin13d", c13, r=0.30, loc=(2.6, 0.2, 5.0), rot=(50, 30, 60))

# ---------- Pocket ----------
def qbez(p0, c, p1, n):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]) for t in [i / n for i in range(n)]]

def outline(top_lift=0.0, s=1.0):
    TL, TR = (-1.3, 1.3 + top_lift), (1.3, 1.3 + top_lift)
    pts = []
    pts += qbez(TL, (0, 1.16 + top_lift), TR, 24)          # top edge, slight dip
    pts += qbez(TR, (1.24, 0.4), (1.14, -0.5), 16)          # right side
    pts += qbez((1.14, -0.5), (1.06, -1.25), (0, -1.55), 18)  # bottom right
    pts += qbez((0, -1.55), (-1.06, -1.25), (-1.14, -0.5), 18)
    pts += qbez((-1.14, -0.5), (-1.24, 0.4), TL, 16)
    return [(x * s, y * s) for x, y in pts]

def slab(name, pts, extrude, bevel, mat, col):
    cu = bpy.data.curves.new(name, "CURVE"); cu.dimensions = "2D"; cu.fill_mode = "BOTH"
    cu.extrude = extrude; cu.bevel_depth = bevel; cu.bevel_resolution = 6
    sp_ = cu.splines.new("POLY"); sp_.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts): sp_.points[i].co = (x, y, 0, 1)
    sp_.use_cyclic_u = True
    tmp = bpy.data.objects.new(name + "_tmp", cu); col.objects.link(tmp)
    dg_ = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg_)); me.name = name
    bpy.data.objects.remove(tmp); bpy.data.curves.remove(cu)
    smooth_mesh(me, 50); me.materials.append(mat)
    o = link(bpy.data.objects.new(name, me), col)
    o.rotation_euler = (math.radians(90), 0, 0)
    return o

PZ = 1.78  # pocket origin height
EXT, BEV = 0.04, 0.30
front = slab("PocketFront", outline(), EXT, BEV, FABRIC, cpk); front.location = (0, -0.32, PZ)
FRONT_Y = -0.32 - (EXT + BEV)
back = slab("PocketBack", outline(top_lift=0.45, s=1.03), 0.04, 0.18, FABRIC_BACK, cpk); back.location = (0, 0.36, PZ)

# gold rim along the front top edge
top_pts = qbez((-1.3, 1.3), (0, 1.16), (1.3, 1.3), 40) + [(1.3, 1.3)]
rc = bpy.data.curves.new("Rim", "CURVE"); rc.dimensions = "3D"; rc.bevel_depth = 0.13; rc.bevel_resolution = 6
rs = rc.splines.new("POLY"); rs.points.add(len(top_pts) - 1)
for i, (x, y) in enumerate(top_pts): rs.points[i].co = (x * 1.12, -0.32, PZ + y + 0.27, 1)
rim = link(bpy.data.objects.new("PocketRim", rc), cpk); rc.materials.append(GOLD)

# gold stitching (dashes on an inset outline)
inset = [(x * 0.80, (y + 0.12) * 0.78 - 0.18) for x, y in outline()]
dash_r, dash_len, step = 0.035, 0.12, 0.20
path, acc = [], 0.0
ring = inset + [inset[0]]
seglens = [math.dist(ring[i], ring[i + 1]) for i in range(len(ring) - 1)]
L = sum(seglens); t = 0.0; k = 0
smesh = bpy.data.meshes.new("Stitch"); sbm = bmesh.new()
def point_at(dist):
    for i, sl in enumerate(seglens):
        if dist <= sl:
            a, b = ring[i], ring[i + 1]; f = dist / sl if sl else 0
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f), (b[0] - a[0], b[1] - a[1])
        dist -= sl
    return ring[-1], (1, 0)
d_ = 0.0
front_y = FRONT_Y + 0.012  # sits on the flat front face
while d_ < L - dash_len:
    (px, py), (tx, ty) = point_at(d_ + dash_len / 2)
    ang = math.atan2(ty, tx)
    from mathutils import Matrix
    m = Matrix.Translation((px, front_y, PZ + py)) @ Matrix.Rotation(-ang, 4, "Y") @ Matrix.Rotation(math.radians(90), 4, "Y")
    bmesh.ops.create_cone(sbm, cap_ends=True, segments=10, radius1=dash_r, radius2=dash_r, depth=dash_len, matrix=m)
    d_ += step
sbm.to_mesh(smesh); sbm.free(); smooth_mesh(smesh, 80); smesh.materials.append(GOLD)
stitch = link(bpy.data.objects.new("PocketStitch", smesh), cpk)

pk = link(bpy.data.objects.new("PocketGroup", None), cpk)
for o in (front, back, rim, stitch):
    o.parent = pk
coin("PocketCoin", cpk, r=0.78, d=0.16, loc=(0.12, 0.0, PZ + 1.32), rot=(90, 0, -12))
coin("FallCoinA", cpk, r=0.42, loc=(-0.95, -0.4, PZ + 2.75), rot=(60, 25, -30))
coin("FallCoinB", cpk, r=0.32, loc=(1.05, -0.2, PZ + 3.35), rot=(35, -40, 50))
coin("FloorCoin", cpk, r=0.42, loc=(1.9, -1.2, 0.055), rot=(0, 0, 0))
pc = bpy.data.objects["PocketCoin"]; pc.parent = pk
pk.rotation_euler = (0, 0, math.radians(-16))

# ---------- render settings ----------
r = scene.render
r.engine = "CYCLES"; r.resolution_x = 1080; r.resolution_y = 1350; r.resolution_percentage = 100
r.film_transparent = False
scene.cycles.samples = SAMPLES; scene.cycles.use_denoising = True
try:
    scene.view_settings.view_transform = "AgX"; scene.view_settings.look = "AgX - Punchy"
except Exception as e:
    print("look:", e)
dev = "CPU"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for t in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = t; prefs.get_devices()
            gpus = [d for d in prefs.devices if d.type != "CPU"]
            if gpus:
                for d in prefs.devices: d.use = True
                scene.cycles.device = "GPU"; dev = t; break
        except Exception:
            continue
except Exception as e:
    print("gpu:", e)
print("DEVICE", dev)

cam_d = bpy.data.cameras.new("Cam"); cam = link(bpy.data.objects.new("Cam", cam_d), base); scene.camera = cam

def shoot(tag, show, cam_loc, target, lens, path):
    for c in (c13, cpk): c.hide_render = c is not show
    cam.location = cam_loc; look_at(cam, target); cam_d.lens = lens
    r.filepath = path
    t0 = time.time(); bpy.ops.render.render(write_still=True)
    print("RENDERED", tag, path, "%.1fs" % (time.time() - t0))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "etf_blackgold.blend"))
if ONLY in ("both", "13"):
    shoot("13", c13, (2.4, -12.5, 3.4), (0, 0, 2.35), 50, os.path.join(OUT, "render_13.png"))
if ONLY in ("both", "pocket"):
    shoot("pocket", cpk, (2.0, -10.5, 3.2), (0, 0, 2.2), 56, os.path.join(OUT, "render_pocket.png"))
