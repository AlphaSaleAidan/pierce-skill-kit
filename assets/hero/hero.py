# Pierce Skill Kit README hero. Blender 4.0, headless:
#   blender -b -P hero.py -- <dark|light> <samples> <out.png>
import bpy, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VARIANT = argv[0] if len(argv) > 0 else "dark"
SAMPLES = int(argv[1]) if len(argv) > 1 else 32
OUT = argv[2] if len(argv) > 2 else f"/tmp/hero-{VARIANT}.png"
DARK = VARIANT == "dark"

def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)

RED, TEAL = lin("d70000"), lin("0087af")

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene

def mat(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    if emit:  # pure emitter: no diffuse/specular for the lights to wash out
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        b.inputs["Specular IOR Level"].default_value = 0.0
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = strength
    return m

def box(name, loc, size, m, bevel=0.0, segs=4):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        bv = o.modifiers.new("bevel", "BEVEL")
        bv.width, bv.segments, bv.limit_method = bevel, segs, "NONE"
        bpy.ops.object.shade_smooth()
    o.data.materials.append(m)
    return o

def rod(name, a, b, r, m):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=16, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    o.data.materials.append(m)
    o.visible_shadow = False
    return o

# --- materials ---
if DARK:
    floor_c, world_c = lin("0d1117"), lin("0a0d12")
    body = mat("graphite", lin("2a2f36"), rough=0.55, metal=0.1, coat=0.08)
    lead_body = mat("lead", lin("1c2026"), rough=0.62, metal=0.1, coat=0.0)
    red_s, teal_s, beam_s, pulse_s = 3.5, 2.5, 0.9, 12.0
else:
    floor_c, world_c = lin("e9ecef"), lin("f6f8fa")
    body = mat("graphite", lin("2a2f36"), rough=0.55, metal=0.1, coat=0.08)
    lead_body = mat("lead", lin("2a2f36"), rough=0.6, metal=0.1, coat=0.0)
    red_s, teal_s, beam_s, pulse_s = 3.0, 1.5, 1.0, 5.0
floor = mat("floor", floor_c, rough=0.75)
red = mat("red", RED, rough=0.4, emit=RED, strength=red_s)
teal = mat("teal", TEAL, rough=0.4, emit=TEAL, strength=teal_s)
beam = mat("beam", TEAL, rough=0.5, emit=TEAL, strength=beam_s)
pulse = mat("pulse", TEAL, rough=0.5, emit=TEAL, strength=pulse_s)

# --- scene ---
bpy.ops.mesh.primitive_plane_add(size=600)
bpy.context.object.data.materials.append(floor)

CX = 2.0  # subject centre x; camera looks left of it so the left ~40% stays empty
LEAD = Vector((CX, 0.6, 2.05))
LW, LD, LH = 2.0, 1.25, 0.26
box("lead", LEAD, (LW, LD, LH), lead_body, 0.07)
box("lead_edge", LEAD - Vector((0, 0, LH * 0.18)), (LW + 0.006, LD + 0.006, 0.012), red, 0.07, 3)  # thin red seam

TW, TD, TH = 0.82, 0.54, 0.13
R_X, R_Y = 2.2, 1.6
tabs = []
for i, ang in enumerate([200, 235, 270, 305, 340]):
    a = math.radians(ang)
    p = Vector((CX + R_X * math.cos(a), 0.6 + R_Y * math.sin(a), 0.38 + 0.05 * (i % 2)))
    t = box(f"tab{i}", p, (TW, TD, TH), body, 0.04)
    t.rotation_euler.z = a + math.pi / 2
    box(f"tab{i}_line", p + Vector((0, 0, TH / 2 + 0.002)), (TW * 0.62, 0.018, 0.006), teal, 0.002, 1).rotation_euler.z = a + math.pi / 2
    tabs.append(p + Vector((0, 0, TH / 2)))

under = LEAD - Vector((0, 0, LH / 2))
for i, top in enumerate(tabs):
    end = under + (top - under) * Vector((0.15, 0.15, 0))  # converge under the lead
    rod(f"beam{i}", top, end, 0.0045 if DARK else 0.0075, beam)
# the one report in flight
a, b = tabs[3], under + (tabs[3] - under) * Vector((0.15, 0.15, 0))
rod("pulse", a + (b - a) * 0.48, a + (b - a) * 0.66, 0.013 if DARK else 0.017, pulse)

# --- lights ---
def area(name, loc, target, size, power, color=(1, 1, 1)):
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.size, l.data.energy, l.data.color = size, power, color
    l.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
area("key", (-2.5, -3.5, 7.5), (CX, 0.4, 0.8), 6, 900 if DARK else 1600, (1.0, 0.97, 0.94))
area("rim", (CX + 2.5, 7.5, 7.0), (CX, 0.4, 1.2), 4, 500 if DARK else 600, (0.9, 0.95, 1.0))

w = bpy.data.worlds.new("w")
scn.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = world_c
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.15 if DARK else 0.6

# --- camera ---
bpy.ops.object.camera_add(location=(0.4, -12.5, 3.7))
cam = bpy.context.object
scn.camera = cam
cam.data.lens = 56
cam.rotation_euler = (Vector((0.55, 0.6, 1.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = (LEAD - cam.location).length - 0.6
cam.data.dof.aperture_fstop = 2.2

# --- render ---
r = scn.render
r.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = SAMPLES
scn.cycles.use_denoising = False  # ponytail: Debian blender has no OIDN; samples + PIL downscale instead
scn.cycles.max_bounces = 6
r.resolution_x, r.resolution_y, r.resolution_percentage = 1600, 640, 100
r.threads_mode, r.threads = "FIXED", 12
scn.view_settings.view_transform = "AgX"
scn.view_settings.look = "AgX - Medium High Contrast"
r.image_settings.file_format = "PNG"
r.filepath = OUT
bpy.ops.render.render(write_still=True)
