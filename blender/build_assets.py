"""
Star Circuit asset builder.

Generates every 3D model the game uses (robots, resource nodes, flora, fauna,
props) procedurally and exports each one as a .glb into game/assets/models.

Run headless:
    blender --background --factory-startup --python blender/build_assets.py

Conventions
- Blender +Z is up, models face Blender +Y (which becomes Godot -Z, i.e. forward).
- Origin sits at the model's feet / base.
- Parts that Godot animates procedurally get stable names:
  Head, ArmL, ArmR, LegL, LegR, Thruster, Eye. Their object origin is the joint.
- Materials named "Foliage" / "Accent" are re-tinted per planet in Godot.
"""

import bpy
import math
import os
import random
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "game", "assets", "models"))
os.makedirs(OUT, exist_ok=True)

_materials = {}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    _materials.clear()


def mat(name, color, metallic=0.0, roughness=0.5, emission=None, strength=0.0):
    """Cached Principled BSDF material."""
    key = (name, tuple(color), metallic, roughness, tuple(emission or ()), strength)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    _materials[key] = m
    return m


def hexc(h):
    """sRGB hex -> linear rgb tuple."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def part(name, prim, size, material, loc=(0, 0, 0), offset=(0, 0, 0), rot=(0, 0, 0),
         parent=None, bevel=0.0, segments=3, smooth=True, **kw):
    """
    Create a primitive, bake size/offset into the mesh so the object origin is a
    clean pivot at `loc` (relative to parent).
    prim: cube | sphere | cyl | cone | ico | torus
    """
    if prim == "cube":
        bpy.ops.mesh.primitive_cube_add(size=1)
    elif prim == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, segments=kw.get("seg", 24), ring_count=kw.get("rings", 12))
    elif prim == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, vertices=kw.get("seg", 20))
    elif prim == "cone":
        bpy.ops.mesh.primitive_cone_add(radius1=0.5, radius2=kw.get("r2", 0.0), depth=1, vertices=kw.get("seg", 16))
    elif prim == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.5, subdivisions=kw.get("sub", 1))
    elif prim == "torus":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.5, minor_radius=kw.get("minor", 0.12),
                                         major_segments=24, minor_segments=10)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    r = Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[2], 4, "Z")
    s = Matrix.Diagonal((*size, 1.0))
    obj.data.transform(Matrix.Translation(offset) @ r @ s)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    obj.location = loc
    if bevel > 0 and prim == "cube":
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    if smooth and prim in ("sphere", "cyl", "torus", "cone"):
        for p in obj.data.polygons:
            p.use_smooth = True
        if prim in ("cyl", "cone"):
            try:
                bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
            except Exception:
                pass
    elif smooth and prim == "cube" and bevel > 0:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
        except Exception:
            pass
    return obj


def empty(name, loc=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    if parent is not None:
        obj.parent = parent
    return obj


def jitter_mesh(obj, amount, seed):
    rnd = random.Random(seed)
    for v in obj.data.vertices:
        v.co += Vector((rnd.uniform(-amount, amount), rnd.uniform(-amount, amount), rnd.uniform(-amount, amount)))


def export(filename):
    path = os.path.join(OUT, filename + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"[star-circuit] exported {path}")


# --------------------------------------------------------------------------
# robots
# --------------------------------------------------------------------------

def robot_common_eye(head, eye_color, y, z=0.0, w=0.34, h=0.12):
    glow = mat("Eye", (1, 1, 1), emission=eye_color, strength=6.0)
    return part("Eye", "cube", (w, 0.06, h), glow, loc=(0, y, z), parent=head, bevel=0.03)


def thruster(parent, loc, metal, glow_color):
    t = part("Thruster", "cube", (0.5, 0.26, 0.5), metal, loc=loc, parent=parent, bevel=0.06)
    glow = mat("ThrusterGlow", (1, 1, 1), emission=glow_color, strength=4.0)
    for i, x in enumerate((-0.14, 0.14)):
        n = part(f"Nozzle{i}", "cyl", (0.16, 0.16, 0.2), metal, loc=(x, 0, -0.3), parent=t)
        part(f"NozzleGlow{i}", "cyl", (0.1, 0.1, 0.04), glow, loc=(0, 0, -0.11), parent=n)
    return t


def build_scout():
    """Vesper - sleek hovering scout, long antenna, teal."""
    reset_scene()
    shell = mat("Shell", hexc("#e8f4f2"), 0.1, 0.35)
    accent = mat("Accent", hexc("#18c2b0"), 0.3, 0.3)
    dark = mat("Metal", hexc("#2a3140"), 0.8, 0.35)
    root = empty("Robot")
    torso = part("Torso", "sphere", (0.8, 0.7, 0.9), shell, loc=(0, 0, 1.05), parent=root)
    part("Belt", "torus", (0.86, 0.76, 0.9), accent, loc=(0, 0, -0.05), parent=torso, minor=0.08)
    head = part("Head", "sphere", (0.62, 0.56, 0.5), shell, loc=(0, 0, 0.42), offset=(0, 0, 0.22), parent=torso)
    part("Visor", "sphere", (0.5, 0.2, 0.26), dark, loc=(0, 0.2, 0.24), parent=head)
    robot_common_eye(head, hexc("#5ff7ff"), 0.3, 0.24, 0.36, 0.08)
    ant = part("Antenna", "cyl", (0.04, 0.04, 0.55), dark, loc=(0.16, -0.05, 0.42), offset=(0, 0, 0.27), parent=head)
    part("AntennaTip", "sphere", (0.12, 0.12, 0.12), mat("Tip", (1, 1, 1), emission=hexc("#5ff7ff"), strength=5), loc=(0, 0, 0.56), parent=ant)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "sphere", (0.18, 0.18, 0.62), accent, loc=(0.46 * x, 0, 0.1), offset=(0, 0, -0.26), parent=torso)
        part(f"Hand{side}", "sphere", (0.2, 0.2, 0.2), dark, loc=(0, 0, -0.58), parent=arm)
    # hover base instead of legs
    base = part("LegL", "cone", (0.62, 0.62, 0.5), dark, loc=(0, 0, -0.48), offset=(0, 0, -0.1), parent=torso, r2=0.35)
    part("HoverGlow", "cyl", (0.36, 0.36, 0.05), mat("Hover", (1, 1, 1), emission=hexc("#5ff7ff"), strength=5), loc=(0, 0, -0.37), parent=base)
    thruster(torso, (0, -0.42, 0.05), dark, hexc("#5ff7ff"))
    export("robot_scout")


def build_miner():
    """Grit - chunky orange miner with drill arm, treads-ish legs."""
    reset_scene()
    shell = mat("Shell", hexc("#f29a2e"), 0.2, 0.45)
    accent = mat("Accent", hexc("#3b3f4a"), 0.7, 0.4)
    stripe = mat("Stripe", hexc("#ffd23f"), 0.1, 0.5)
    root = empty("Robot")
    torso = part("Torso", "cube", (1.15, 0.85, 0.95), shell, loc=(0, 0, 1.0), bevel=0.18)
    torso.parent = root
    part("Stripe", "cube", (1.18, 0.88, 0.14), stripe, loc=(0, 0, -0.28), parent=torso, bevel=0.05)
    head = part("Head", "cube", (0.7, 0.6, 0.42), shell, loc=(0, 0.05, 0.47), offset=(0, 0, 0.2), parent=torso, bevel=0.12)
    part("Brow", "cube", (0.74, 0.16, 0.1), accent, loc=(0, 0.3, 0.34), parent=head, bevel=0.03)
    robot_common_eye(head, hexc("#ffcf4a"), 0.31, 0.2, 0.46, 0.13)
    part("Lamp", "cyl", (0.14, 0.14, 0.12), mat("Lamp", (1, 1, 1), emission=hexc("#fff3b0"), strength=6), loc=(0, 0.1, 0.44), parent=head)
    # left: claw arm
    arml = part("ArmL", "cube", (0.3, 0.3, 0.7), accent, loc=(-0.72, 0, 0.18), offset=(0, 0, -0.3), parent=torso, bevel=0.08)
    part("ClawL", "cube", (0.36, 0.4, 0.26), shell, loc=(0, 0.02, -0.7), parent=arml, bevel=0.06)
    # right: drill arm
    armr = part("ArmR", "cube", (0.32, 0.32, 0.6), accent, loc=(0.72, 0, 0.18), offset=(0, 0, -0.26), parent=torso, bevel=0.08)
    part("Drill", "cone", (0.34, 0.34, 0.55), mat("Drill", hexc("#c9ced6"), 0.9, 0.25), loc=(0, 0.08, -0.7), rot=(math.pi, 0, 0), parent=armr, seg=10)
    for side, x in (("L", -1), ("R", 1)):
        leg = part(f"Leg{side}", "cube", (0.36, 0.5, 0.5), accent, loc=(0.32 * x, 0, -0.45), offset=(0, 0, -0.2), parent=torso, bevel=0.08)
        part(f"Tread{side}", "cube", (0.42, 0.72, 0.2), mat("Tread", hexc("#1e2128"), 0.2, 0.8), loc=(0, 0.06, -0.47), parent=leg, bevel=0.08)
    thruster(torso, (0, -0.55, 0.12), accent, hexc("#ffb347"))
    export("robot_miner")


def build_engineer():
    """Cog - purple engineer, round body, big goggle head, wrench arm."""
    reset_scene()
    shell = mat("Shell", hexc("#8f6cf0"), 0.25, 0.4)
    accent = mat("Accent", hexc("#f4f1ff"), 0.1, 0.4)
    dark = mat("Metal", hexc("#2b2540"), 0.8, 0.3)
    root = empty("Robot")
    torso = part("Torso", "sphere", (0.95, 0.85, 0.85), shell, loc=(0, 0, 0.98), parent=root)
    part("Panel", "cube", (0.44, 0.1, 0.34), accent, loc=(0, 0.4, 0.02), parent=torso, bevel=0.05)
    for i, (x, c) in enumerate(((-0.12, "#ff5d8f"), (0.0, "#ffd23f"), (0.12, "#4cf3a0"))):
        part(f"Light{i}", "sphere", (0.08, 0.08, 0.08), mat(f"Light{i}", (1, 1, 1), emission=hexc(c), strength=5), loc=(x, 0.46, 0.06), parent=torso)
    head = part("Head", "sphere", (0.68, 0.62, 0.58), accent, loc=(0, 0, 0.4), offset=(0, 0, 0.26), parent=torso)
    for i, x in enumerate((-0.15, 0.15)):
        g = part(f"Goggle{i}", "cyl", (0.26, 0.26, 0.14), dark, loc=(x, 0.27, 0.3), rot=(math.pi / 2, 0, 0), parent=head)
        part(f"Lens{i}", "cyl", (0.18, 0.18, 0.04), mat("Eye", (1, 1, 1), emission=hexc("#ff9bf0"), strength=5), loc=(0, 0.07, 0), rot=(math.pi / 2, 0, 0), parent=g)
    part("Eye", "cube", (0.02, 0.02, 0.02), dark, loc=(0, 0.3, 0.3), parent=head)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cyl", (0.14, 0.14, 0.62), dark, loc=(0.5 * x, 0, 0.1), offset=(0, 0, -0.28), parent=torso)
        if side == "R":
            w = part("Wrench", "cube", (0.1, 0.1, 0.44), mat("Chrome", hexc("#dfe3ea"), 1.0, 0.2), loc=(0, 0.1, -0.66), parent=arm, bevel=0.03)
            part("WrenchHead", "torus", (0.28, 0.28, 0.4), mat("Chrome", hexc("#dfe3ea"), 1.0, 0.2), loc=(0, 0, -0.26), rot=(math.pi / 2, 0, 0), parent=w, minor=0.18)
        else:
            part("HandL", "sphere", (0.22, 0.22, 0.22), accent, loc=(0, 0, -0.62), parent=arm)
        leg = part(f"Leg{side}", "cyl", (0.16, 0.16, 0.5), dark, loc=(0.24 * x, 0, -0.35), offset=(0, 0, -0.22), parent=torso)
        part(f"Foot{side}", "sphere", (0.3, 0.42, 0.18), shell, loc=(0, 0.06, -0.5), parent=leg)
    thruster(torso, (0, -0.48, 0.1), dark, hexc("#ff9bf0"))
    export("robot_engineer")


def build_siphon():
    """Halo - tall gold/white energy robot with a floating halo ring."""
    reset_scene()
    shell = mat("Shell", hexc("#fbf6e9"), 0.2, 0.3)
    accent = mat("Accent", hexc("#e8b93a"), 0.9, 0.25)
    dark = mat("Metal", hexc("#34303a"), 0.7, 0.35)
    energy = mat("Energy", (1, 1, 1), emission=hexc("#ffe27a"), strength=6)
    root = empty("Robot")
    torso = part("Torso", "cone", (0.9, 0.75, 1.0), shell, loc=(0, 0, 1.1), rot=(math.pi, 0, 0), parent=root, r2=0.45, seg=24)
    part("Core", "sphere", (0.32, 0.32, 0.32), energy, loc=(0, 0.3, 0.12), parent=torso)
    part("Collar", "torus", (0.8, 0.7, 0.8), accent, loc=(0, 0, 0.45), parent=torso, minor=0.1)
    head = part("Head", "ico", (0.56, 0.56, 0.62), shell, loc=(0, 0, 0.55), offset=(0, 0, 0.3), parent=torso, sub=2)
    robot_common_eye(head, hexc("#ffe27a"), 0.25, 0.32, 0.3, 0.1)
    part("Halo", "torus", (0.8, 0.8, 0.8), energy, loc=(0, 0, 0.78), parent=head, minor=0.06)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cone", (0.2, 0.2, 0.7), accent, loc=(0.52 * x, 0, 0.3), offset=(0, 0, -0.3), rot=(math.pi, 0, 0), parent=torso, r2=0.08)
        part(f"Orb{side}", "sphere", (0.2, 0.2, 0.2), energy, loc=(0, 0, -0.72), parent=arm)
        leg = part(f"Leg{side}", "cone", (0.26, 0.26, 0.6), dark, loc=(0.2 * x, 0, -0.45), offset=(0, 0, -0.2), rot=(math.pi, 0, 0), parent=torso, r2=0.1)
    thruster(torso, (0, -0.4, 0.2), dark, hexc("#ffe27a"))
    export("robot_siphon")


def build_archivist():
    """NPC quest giver - old stately robot on a pedestal."""
    reset_scene()
    shell = mat("Shell", hexc("#5a7dbd"), 0.4, 0.4)
    accent = mat("Accent", hexc("#d8e4ff"), 0.2, 0.4)
    dark = mat("Metal", hexc("#20283a"), 0.7, 0.4)
    root = empty("Robot")
    base = part("Pedestal", "cyl", (1.4, 1.4, 0.3), dark, loc=(0, 0, 0.15), parent=root, seg=8)
    torso = part("Torso", "cyl", (0.9, 0.9, 1.3), shell, loc=(0, 0, 1.0), parent=root, seg=8)
    part("Scroll", "cube", (0.6, 0.08, 0.7), accent, loc=(0, 0.45, 0.0), parent=torso, bevel=0.03)
    head = part("Head", "sphere", (0.8, 0.7, 0.6), accent, loc=(0, 0, 0.66), offset=(0, 0, 0.25), parent=torso)
    robot_common_eye(head, hexc("#9bd1ff"), 0.33, 0.28, 0.44, 0.1)
    part("Beard", "cone", (0.5, 0.2, 0.4), mat("Beard", hexc("#eef3ff"), 0.1, 0.6), loc=(0, 0.25, 0.02), rot=(math.pi, 0, 0), parent=head)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cyl", (0.16, 0.16, 0.8), dark, loc=(0.5 * x, 0, 0.45), offset=(0, 0, -0.36), parent=torso)
    staff = part("Staff", "cyl", (0.07, 0.07, 2.2), mat("Wood", hexc("#8f7b5a"), 0.2, 0.7), loc=(0.62, 0.3, 1.2), parent=root)
    part("Gem", "ico", (0.3, 0.3, 0.3), mat("Gem", (1, 1, 1), emission=hexc("#9bd1ff"), strength=6), loc=(0, 0, 1.15), parent=staff, sub=1)
    export("npc_archivist")


# --------------------------------------------------------------------------
# resources
# --------------------------------------------------------------------------

def build_rock(name, body_hex, vein_hex, seed, glow=False):
    reset_scene()
    rnd = random.Random(seed)
    root = empty("Node")
    body = mat("Rock", hexc(body_hex), 0.1, 0.85)
    vein = mat("Vein", hexc(vein_hex), 0.8, 0.3, emission=hexc(vein_hex) if glow else None, strength=2.0 if glow else 0.0)
    for i in range(3):
        s = rnd.uniform(0.7, 1.2)
        r = part(f"Rock{i}", "ico", (1.3 * s, 1.1 * s, 0.9 * s), body, loc=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0.3 * s), parent=root, sub=1)
        jitter_mesh(r, 0.12, seed + i)
    for i in range(6):
        a = rnd.uniform(0, math.tau)
        part(f"Vein{i}", "ico", (0.32, 0.28, 0.26), vein, loc=(math.cos(a) * 0.62, math.sin(a) * 0.62, rnd.uniform(0.35, 0.75)), parent=root, sub=0)
    export(name)


def build_crystal():
    reset_scene()
    rnd = random.Random(7)
    root = empty("Node")
    base = mat("Rock", hexc("#3b3550"), 0.1, 0.8)
    crystal = mat("Accent", hexc("#b98cff"), 0.1, 0.1, emission=hexc("#9b6bff"), strength=1.8)
    r = part("Base", "ico", (1.4, 1.4, 0.5), base, loc=(0, 0, 0.1), parent=root, sub=1)
    jitter_mesh(r, 0.1, 3)
    for i in range(7):
        h = rnd.uniform(0.9, 2.2)
        tilt = (rnd.uniform(-0.45, 0.45), rnd.uniform(-0.45, 0.45), rnd.uniform(0, math.tau))
        part(f"Shard{i}", "cone", (0.34, 0.34, h), crystal, loc=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), 0.2),
             offset=(0, 0, h / 2), rot=tilt, parent=root, seg=6, r2=0.05, smooth=False)
    export("res_crystal")


def build_fiber_plant():
    reset_scene()
    rnd = random.Random(11)
    root = empty("Node")
    leaf = mat("Foliage", hexc("#6ee06a"), 0.0, 0.6)
    stem = mat("Stem", hexc("#3f7d3a"), 0.0, 0.7)
    bulb = mat("Accent", hexc("#fff08a"), 0.0, 0.4, emission=hexc("#ffe066"), strength=1.2)
    for i in range(9):
        a = i / 9 * math.tau
        h = rnd.uniform(0.9, 1.6)
        part(f"Blade{i}", "cone", (0.22, 0.08, h), leaf, loc=(math.cos(a) * 0.2, math.sin(a) * 0.2, 0),
             offset=(0, 0, h / 2), rot=(math.sin(a) * 0.5, -math.cos(a) * 0.5, 0), parent=root, seg=4)
    s = part("Stalk", "cyl", (0.08, 0.08, 1.4), stem, loc=(0, 0, 0), offset=(0, 0, 0.7), parent=root)
    part("Bulb", "sphere", (0.36, 0.36, 0.44), bulb, loc=(0, 0, 1.45), parent=root)
    export("res_fiber")


def build_spore_pod():
    reset_scene()
    root = empty("Node")
    cap = mat("Foliage", hexc("#ff6fa8"), 0.0, 0.5)
    stem = mat("Stem", hexc("#f3e6d8"), 0.0, 0.7)
    dots = mat("Accent", hexc("#ffffff"), 0.0, 0.3, emission=hexc("#ffd1f0"), strength=1.5)
    for i, (x, y, h, s) in enumerate(((0, 0, 1.0, 1.0), (0.55, 0.2, 0.6, 0.6), (-0.4, 0.45, 0.45, 0.5))):
        part(f"Stem{i}", "cyl", (0.22 * s, 0.22 * s, h), stem, loc=(x, y, 0), offset=(0, 0, h / 2), parent=root)
        c = part(f"Cap{i}", "sphere", (1.1 * s, 1.1 * s, 0.7 * s), cap, loc=(x, y, h), parent=root)
        for j in range(5):
            a = j / 5 * math.tau
            part(f"Dot{i}_{j}", "sphere", (0.14 * s, 0.14 * s, 0.1 * s), dots, loc=(math.cos(a) * 0.32 * s, math.sin(a) * 0.32 * s, 0.22 * s), parent=c)
    export("res_spore")


def build_energy_well():
    reset_scene()
    root = empty("Node")
    rock = mat("Rock", hexc("#2e2a36"), 0.2, 0.8)
    glow = mat("Accent", (1, 1, 1), emission=hexc("#ffcf3f"), strength=5)
    ring = part("Ring", "torus", (1.6, 1.6, 1.4), rock, loc=(0, 0, 0.15), parent=root, minor=0.22)
    for i in range(5):
        a = i / 5 * math.tau
        part(f"Pylon{i}", "cone", (0.3, 0.3, 1.0), rock, loc=(math.cos(a) * 0.75, math.sin(a) * 0.75, 0), offset=(0, 0, 0.5), parent=root, seg=5, r2=0.06, smooth=False)
    part("Orb", "sphere", (0.7, 0.7, 0.7), glow, loc=(0, 0, 1.2), parent=root)
    export("res_energy")


def build_void_shard():
    reset_scene()
    rnd = random.Random(99)
    root = empty("Node")
    obs = mat("Rock", hexc("#18141f"), 0.3, 0.3)
    glow = mat("Accent", (1, 1, 1), emission=hexc("#ff3d6e"), strength=3.5)
    for i in range(4):
        h = rnd.uniform(1.2, 2.4)
        part(f"Spire{i}", "cone", (0.6, 0.6, h), obs, loc=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0), offset=(0, 0, h / 2),
             rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0), parent=root, seg=5, smooth=False)
    for i in range(5):
        part(f"Core{i}", "ico", (0.3, 0.3, 0.3), glow, loc=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), rnd.uniform(0.3, 1.2)), parent=root, sub=0)
    export("res_void")


# --------------------------------------------------------------------------
# flora / fauna / props
# --------------------------------------------------------------------------

def build_tree_lollipop():
    reset_scene()
    root = empty("Node")
    trunk = mat("Trunk", hexc("#7a5a44"), 0.0, 0.8)
    leaf = mat("Foliage", hexc("#58c878"), 0.0, 0.6)
    t = part("Trunk", "cyl", (0.4, 0.4, 3.2), trunk, offset=(0, 0, 1.6), parent=root, seg=8)
    part("Crown", "sphere", (2.6, 2.6, 2.4), leaf, loc=(0, 0, 3.8), parent=root, seg=16, rings=10)
    part("Crown2", "sphere", (1.6, 1.6, 1.5), leaf, loc=(0.9, 0.4, 3.1), parent=root, seg=16, rings=10)
    export("flora_tree_round")


def build_tree_spiral():
    reset_scene()
    root = empty("Node")
    trunk = mat("Trunk", hexc("#5a4a6a"), 0.0, 0.8)
    leaf = mat("Foliage", hexc("#58c8c0"), 0.0, 0.6)
    z = 0.0
    for i in range(6):
        s = 1.0 - i * 0.12
        part(f"Seg{i}", "cyl", (0.55 * s, 0.55 * s, 0.9), trunk, loc=(math.sin(i * 0.6) * 0.3, 0, z), offset=(0, 0, 0.45), parent=root, seg=8)
        z += 0.85
    for i in range(3):
        part(f"Disc{i}", "cyl", (3.2 - i * 0.8, 3.2 - i * 0.8, 0.35), leaf, loc=(math.sin(5 * 0.6) * 0.3, 0, z - 0.2 + i * 0.7), parent=root, seg=12)
    export("flora_tree_disc")


def build_mushroom_tree():
    reset_scene()
    root = empty("Node")
    stem = mat("Trunk", hexc("#efe2cf"), 0.0, 0.7)
    cap = mat("Foliage", hexc("#e0529b"), 0.0, 0.5)
    glow = mat("Accent", (1, 1, 1), emission=hexc("#aef7ff"), strength=2)
    part("Stem", "cyl", (0.7, 0.7, 4.0), stem, offset=(0, 0, 2.0), parent=root, seg=12)
    c = part("Cap", "sphere", (3.6, 3.6, 1.8), cap, loc=(0, 0, 4.0), parent=root)
    for j in range(8):
        a = j / 8 * math.tau
        part(f"Spot{j}", "sphere", (0.4, 0.4, 0.2), glow, loc=(math.cos(a) * 1.1, math.sin(a) * 1.1, 0.62), parent=c)
    export("flora_mushroom")


def build_cactus():
    reset_scene()
    root = empty("Node")
    body = mat("Foliage", hexc("#8bbf5a"), 0.0, 0.6)
    flower = mat("Accent", hexc("#ff7a59"), 0.0, 0.5)
    part("Main", "sphere", (0.9, 0.9, 3.0), body, loc=(0, 0, 1.5), parent=root)
    for side in (-1, 1):
        a = part(f"Arm{side}", "sphere", (0.5, 0.5, 1.3), body, loc=(0.7 * side, 0, 1.7), parent=root)
        part(f"Elbow{side}", "sphere", (0.5, 0.5, 0.8), body, loc=(0.3 * side, 0, -0.4), rot=(0, 1.0 * side, 0), parent=a)
    part("Flower", "sphere", (0.5, 0.5, 0.3), flower, loc=(0, 0, 3.0), parent=root)
    export("flora_cactus")


def build_ice_spike():
    reset_scene()
    rnd = random.Random(5)
    root = empty("Node")
    ice = mat("Foliage", hexc("#bfe9ff"), 0.0, 0.08)
    for i in range(5):
        h = rnd.uniform(1.5, 4.0)
        part(f"Spike{i}", "cone", (0.9, 0.9, h), ice, loc=(rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), 0), offset=(0, 0, h / 2),
             rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0), parent=root, seg=6, smooth=False)
    export("flora_ice")


def build_boulder():
    reset_scene()
    root = empty("Node")
    rock = mat("Rock", hexc("#8a8078"), 0.0, 0.9)
    r = part("Boulder", "ico", (2.4, 2.0, 1.6), rock, loc=(0, 0, 0.5), parent=root, sub=2)
    jitter_mesh(r, 0.18, 21)
    export("prop_boulder")


def build_critter():
    """Fauna - a round hopping creature, recoloured per planet in Godot."""
    reset_scene()
    root = empty("Critter")
    skin = mat("Foliage", hexc("#ffb347"), 0.0, 0.6)
    belly = mat("Belly", hexc("#fff1d6"), 0.0, 0.6)
    dark = mat("Dark", hexc("#1d1b22"), 0.0, 0.3)
    body = part("Body", "sphere", (1.1, 1.3, 0.95), skin, loc=(0, 0, 0.75), parent=root)
    part("BellyPatch", "sphere", (0.8, 0.5, 0.7), belly, loc=(0, 0.35, -0.08), parent=body)
    for side in (-1, 1):
        e = part(f"EyeWhite{side}", "sphere", (0.32, 0.26, 0.36), belly, loc=(0.22 * side, 0.5, 0.25), parent=body)
        part(f"Pupil{side}", "sphere", (0.16, 0.12, 0.2), dark, loc=(0, 0.1, 0), parent=e)
        part(f"Ear{side}", "cone", (0.26, 0.2, 0.6), skin, loc=(0.3 * side, -0.05, 0.4), offset=(0, 0, 0.25), rot=(0, 0.35 * side, 0), parent=body)
    for i, (x, y) in enumerate(((-0.3, 0.3), (0.3, 0.3), (-0.3, -0.35), (0.3, -0.35))):
        leg = part(f"Leg{i}", "cyl", (0.18, 0.18, 0.4), skin, loc=(x, y, -0.35), offset=(0, 0, -0.1), parent=body)
    part("Tail", "sphere", (0.3, 0.3, 0.3), belly, loc=(0, -0.62, 0.05), parent=body)
    export("fauna_critter")


def build_outpost():
    """Crafting terminal + landing pad for the home outpost."""
    reset_scene()
    root = empty("Outpost")
    metal = mat("Metal", hexc("#c7ccd6"), 0.8, 0.3)
    dark = mat("Dark", hexc("#2a2f3a"), 0.6, 0.4)
    glow = mat("Screen", (1, 1, 1), emission=hexc("#39e5ff"), strength=4)
    pad = part("Pad", "cyl", (7, 7, 0.3), dark, loc=(0, 0, 0.15), parent=root, seg=8)
    part("PadRing", "torus", (6.2, 6.2, 1), glow, loc=(0, 0, 0.17), parent=pad, minor=0.02)
    term = part("Terminal", "cube", (1.1, 0.7, 1.6), metal, loc=(3.2, 0, 0.3), offset=(0, 0, 0.8), parent=root, bevel=0.12)
    part("TermScreen", "cube", (0.8, 0.06, 0.55), glow, loc=(0, 0.36, 1.15), rot=(-0.3, 0, 0), parent=term, bevel=0.02)
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        part(f"Light{i}", "cyl", (0.2, 0.2, 1.2), metal, loc=(math.cos(a) * 3.3, math.sin(a) * 3.3, 0.3), offset=(0, 0, 0.6), parent=root)
        part(f"Bulb{i}", "sphere", (0.3, 0.3, 0.3), glow, loc=(math.cos(a) * 3.3, math.sin(a) * 3.3, 1.55), parent=root)
    export("prop_outpost")


def build_terminal_only():
    reset_scene()
    root = empty("Terminal")
    metal = mat("Metal", hexc("#c7ccd6"), 0.8, 0.3)
    glow = mat("Screen", (1, 1, 1), emission=hexc("#39e5ff"), strength=4)
    term = part("Terminal", "cube", (1.1, 0.7, 1.6), metal, loc=(0, 0, 0), offset=(0, 0, 0.8), parent=root, bevel=0.12)
    part("TermScreen", "cube", (0.8, 0.06, 0.55), glow, loc=(0, 0.36, 1.15), rot=(-0.3, 0, 0), parent=term, bevel=0.02)
    export("prop_terminal")


# --------------------------------------------------------------------------
# enemies (rogue drones) + combat props
# --------------------------------------------------------------------------

def build_scrapper():
    """Fast melee drone: hovering buzzsaw ball with two blade arms."""
    reset_scene()
    shell = mat("Shell", hexc("#3a3f4b"), 0.8, 0.35)
    rust = mat("Accent", hexc("#b8412e"), 0.4, 0.5)
    blade = mat("Blade", hexc("#d9dde4"), 1.0, 0.2)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff2a2a"), strength=8)
    root = empty("Drone")
    body = part("Torso", "sphere", (1.0, 1.0, 0.9), shell, loc=(0, 0, 1.3), parent=root)
    part("Band", "torus", (1.06, 1.06, 1.0), rust, loc=(0, 0, 0), parent=body, minor=0.1)
    part("Eye", "sphere", (0.36, 0.2, 0.36), eye, loc=(0, 0.42, 0.08), parent=body)
    for i, a in enumerate((0.6, -0.6)):
        part(f"Spike{i}", "cone", (0.14, 0.14, 0.5), rust, loc=(math.sin(a) * 0.3, -0.1, 0.42), offset=(0, 0, 0.2), rot=(0, a, 0), parent=body, seg=6)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cube", (0.16, 0.16, 0.6), shell, loc=(0.52 * x, 0.05, 0.0), offset=(0, 0, -0.26), rot=(0, 0.5 * x, 0), parent=body, bevel=0.04)
        part(f"Saw{side}", "cyl", (0.62, 0.62, 0.05), blade, loc=(0, 0.1, -0.62), rot=(0, math.pi / 2, 0), parent=arm, seg=12, smooth=False)
    part("Jet", "cone", (0.5, 0.5, 0.45), shell, loc=(0, 0, -0.52), rot=(math.pi, 0, 0), parent=body, r2=0.2)
    part("JetGlow", "cyl", (0.26, 0.26, 0.04), mat("JetGlow", (1, 1, 1), emission=hexc("#ff6a2a"), strength=6), loc=(0, 0, -0.76), parent=body)
    export("enemy_scrapper")


def build_sentinel():
    """Ranged drone: floating octahedral core in a ring with a plasma cannon."""
    reset_scene()
    shell = mat("Shell", hexc("#2b2f3a"), 0.8, 0.3)
    accent = mat("Accent", hexc("#c23b6a"), 0.5, 0.4)
    core = mat("Eye", (1, 1, 1), emission=hexc("#ff3d9a"), strength=7)
    root = empty("Drone")
    body = part("Torso", "ico", (1.1, 1.1, 1.3), shell, loc=(0, 0, 1.7), parent=root, sub=0)
    part("Eye", "sphere", (0.45, 0.45, 0.45), core, loc=(0, 0.28, 0), parent=body)
    ring = part("Ring", "torus", (1.9, 1.9, 1.9), accent, loc=(0, 0, 0), rot=(0.3, 0, 0), parent=body, minor=0.07)
    cannon = part("Cannon", "cyl", (0.26, 0.26, 1.0), shell, loc=(0, 0.35, -0.3), offset=(0, 0, 0.45), rot=(-math.pi / 2, 0, 0), parent=body)
    part("Muzzle", "cyl", (0.34, 0.34, 0.12), core, loc=(0, 0.95, 0), rot=(-math.pi / 2, 0, 0), parent=cannon)
    for i in range(3):
        a = i / 3 * math.tau
        part(f"Fin{i}", "cone", (0.22, 0.08, 0.7), accent, loc=(math.cos(a) * 0.55, math.sin(a) * 0.55 - 0.1, -0.5), rot=(0, 0, a), parent=body, seg=4)
    export("enemy_sentinel")


def build_brute():
    """Elite: hulking corrupted loader with huge fists."""
    reset_scene()
    shell = mat("Shell", hexc("#4a4452"), 0.7, 0.4)
    plate = mat("Accent", hexc("#9e2b25"), 0.5, 0.45)
    dark = mat("Metal", hexc("#1f1c24"), 0.8, 0.3)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff2a2a"), strength=9)
    root = empty("Robot")
    torso = part("Torso", "cube", (1.9, 1.3, 1.5), shell, loc=(0, 0, 1.9), bevel=0.25)
    torso.parent = root
    part("Chest", "cube", (1.5, 0.2, 0.9), plate, loc=(0, 0.62, 0.1), parent=torso, bevel=0.08)
    head = part("Head", "cube", (0.8, 0.7, 0.5), dark, loc=(0, 0.35, 0.72), offset=(0, 0, 0.22), parent=torso, bevel=0.12)
    part("Eye", "cube", (0.55, 0.08, 0.12), eye, loc=(0, 0.36, 0.24), parent=head, bevel=0.03)
    for i, x in enumerate((-0.25, 0.25)):
        part(f"Horn{i}", "cone", (0.18, 0.18, 0.5), plate, loc=(x, 0, 0.45), offset=(0, 0, 0.2), rot=(0, x * 1.2, 0), parent=head, seg=6)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cube", (0.5, 0.5, 1.2), dark, loc=(1.2 * x, 0, 0.35), offset=(0, 0, -0.5), parent=torso, bevel=0.1)
        part(f"Fist{side}", "cube", (0.85, 0.85, 0.8), plate, loc=(0, 0.05, -1.25), parent=arm, bevel=0.15)
        leg = part(f"Leg{side}", "cube", (0.55, 0.6, 1.0), dark, loc=(0.5 * x, 0, -0.7), offset=(0, 0, -0.4), parent=torso, bevel=0.1)
        part(f"Foot{side}", "cube", (0.7, 0.9, 0.3), shell, loc=(0, 0.1, -0.95), parent=leg, bevel=0.08)
    for i in range(3):
        part(f"Vent{i}", "cyl", (0.2, 0.2, 0.6), dark, loc=(-0.4 + i * 0.4, -0.6, 0.7), offset=(0, 0, 0.25), parent=torso)
    export("enemy_brute")


def build_turret():
    """Engineer's deployable turret."""
    reset_scene()
    metal = mat("Metal", hexc("#c7ccd6"), 0.8, 0.3)
    purple = mat("Accent", hexc("#8f6cf0"), 0.4, 0.4)
    glow = mat("Eye", (1, 1, 1), emission=hexc("#ff9bf0"), strength=6)
    root = empty("Turret")
    for i in range(3):
        a = i / 3 * math.tau
        part(f"Leg{i}", "cyl", (0.1, 0.1, 0.9), metal, loc=(math.cos(a) * 0.35, math.sin(a) * 0.35, 0.35), rot=(math.sin(a) * 0.6, -math.cos(a) * 0.6, 0))
    head = part("Head", "sphere", (0.7, 0.7, 0.6), purple, loc=(0, 0, 0.85), parent=root)
    part("Barrel", "cyl", (0.14, 0.14, 0.8), metal, loc=(0, 0.3, 0.05), offset=(0, 0, 0.3), rot=(-math.pi / 2, 0, 0), parent=head)
    part("Eye", "sphere", (0.2, 0.12, 0.2), glow, loc=(0, 0.3, 0.18), parent=head)
    for o in bpy.data.objects:
        if o.parent is None and o.name.startswith("Leg"):
            o.parent = root
    export("prop_turret")


# --------------------------------------------------------------------------
# points of interest
# --------------------------------------------------------------------------

def build_monolith():
    """Ancient obelisk with glowing glyph bands and a hovering ring."""
    reset_scene()
    stone = mat("Stone", hexc("#2a2733"), 0.3, 0.35)
    glyph = mat("Glyph", (1, 1, 1), emission=hexc("#6ff3ff"), strength=5)
    root = empty("Monolith")
    part("Base", "cyl", (4.2, 4.2, 0.6), stone, loc=(0, 0, 0.3), parent=root, seg=6, smooth=False)
    part("Step", "cyl", (3.2, 3.2, 0.5), stone, loc=(0, 0, 0.8), parent=root, seg=6, smooth=False)
    body = part("Body", "cone", (1.8, 1.4, 9.0), stone, loc=(0, 0, 1.0), offset=(0, 0, 4.5), parent=root, seg=4, r2=0.35, smooth=False)
    for i, z in enumerate((2.2, 3.6, 5.0, 6.4)):
        w = 1.55 - z * 0.12
        part(f"Glyph{i}", "cube", (w, w * 0.8, 0.12), glyph, loc=(0, 0, z), rot=(0, 0, math.pi / 4), parent=body)
    part("Halo", "torus", (3.2, 3.2, 3.2), glyph, loc=(0, 0, 10.8), parent=root, minor=0.05)
    part("Tip", "ico", (0.7, 0.7, 0.7), glyph, loc=(0, 0, 10.8), parent=root, sub=1)
    export("poi_monolith")


def build_ruin():
    """Broken arch and pillars around a dais."""
    reset_scene()
    rnd = random.Random(31)
    stone = mat("Stone", hexc("#b8ab94"), 0.0, 0.85)
    moss = mat("Foliage", hexc("#6f9b52"), 0.0, 0.9)
    glow = mat("Glyph", (1, 1, 1), emission=hexc("#ffcf6b"), strength=3)
    root = empty("Ruin")
    part("Dais", "cyl", (9, 9, 0.5), stone, loc=(0, 0, 0.2), parent=root, seg=10, smooth=False)
    for side in (-1, 1):
        part(f"ArchLeg{side}", "cube", (1.1, 1.1, 5.2), stone, loc=(2.6 * side, 0, 2.6), parent=root, bevel=0.08)
    part("ArchTop", "cube", (6.6, 1.2, 1.0), stone, loc=(0.4, 0, 5.6), rot=(0, 0.08, 0), parent=root, bevel=0.08)
    part("Moss", "cube", (2.0, 1.25, 0.25), moss, loc=(-1.4, 0, 6.1), parent=root, bevel=0.1)
    for i in range(6):
        a = i / 6 * math.tau + 0.4
        h = rnd.uniform(1.2, 4.2)
        if i == 2:
            part(f"Fallen{i}", "cyl", (0.8, 0.8, 4.0), stone, loc=(math.cos(a) * 6.2, math.sin(a) * 6.2, 0.5), rot=(math.pi / 2, 0, a), parent=root, seg=8)
        else:
            part(f"Pillar{i}", "cyl", (0.8, 0.8, h), stone, loc=(math.cos(a) * 6.2, math.sin(a) * 6.2, 0), offset=(0, 0, h / 2), parent=root, seg=8)
    part("Core", "ico", (0.9, 0.9, 1.2), glow, loc=(0, 0, 1.6), parent=root, sub=0)
    export("poi_ruin")


def build_crash():
    """A crashed escape pod half-buried in the ground, debris scattered."""
    reset_scene()
    rnd = random.Random(41)
    hull = mat("Hull", hexc("#d8dde6"), 0.6, 0.35)
    burn = mat("Burn", hexc("#2b2622"), 0.2, 0.9)
    stripe = mat("Accent", hexc("#ff7a3d"), 0.3, 0.5)
    glow = mat("Glyph", (1, 1, 1), emission=hexc("#ff5a3d"), strength=4)
    root = empty("Crash")
    pod = part("Pod", "sphere", (3.2, 3.2, 5.5), hull, loc=(0, 0, 0.9), rot=(1.1, 0.2, 0), parent=root)
    part("Scorch", "sphere", (3.3, 3.3, 2.2), burn, loc=(0, 0, -1.8), parent=pod)
    part("Band", "torus", (3.3, 3.3, 3.3), stripe, loc=(0, 0, 0.6), parent=pod, minor=0.08)
    part("Window", "sphere", (1.2, 0.5, 1.0), glow, loc=(0, 1.45, 1.2), parent=pod)
    for i in range(3):
        a = i / 3 * math.tau
        part(f"Fin{i}", "cube", (0.2, 1.4, 2.2), hull, loc=(math.cos(a) * 1.3, math.sin(a) * 1.3, -1.6), rot=(0, 0.4, a), parent=pod, bevel=0.05)
    part("Crater", "cyl", (9, 9, 0.3), burn, loc=(0, 0, 0.05), parent=root, seg=12)
    for i in range(8):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(4, 9)
        part(f"Debris{i}", "cube", (rnd.uniform(0.4, 1.4), rnd.uniform(0.3, 1.0), 0.12), hull if i % 2 else burn,
             loc=(math.cos(a) * d, math.sin(a) * d, 0.2), rot=(rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), a), parent=root, bevel=0.03)
    export("poi_crash")


def build_cache():
    """Loot container: a small data cache with a glowing seam."""
    reset_scene()
    metal = mat("Metal", hexc("#59606e"), 0.8, 0.3)
    trim = mat("Accent", hexc("#ffd23f"), 0.6, 0.35)
    glow = mat("Glyph", (1, 1, 1), emission=hexc("#ffe27a"), strength=5)
    root = empty("Cache")
    body = part("Body", "cube", (1.6, 1.0, 0.8), metal, loc=(0, 0, 0.4), parent=root, bevel=0.1)
    part("Seam", "cube", (1.64, 1.04, 0.07), glow, loc=(0, 0, 0.12), parent=body)
    lid = part("Lid", "cube", (1.66, 1.06, 0.3), trim, loc=(0, -0.5, 0.52), offset=(0, 0.5, 0), parent=body, bevel=0.08)
    part("Emblem", "cyl", (0.3, 0.3, 0.05), glow, loc=(0, 0.53, 0.0), rot=(math.pi / 2, 0, 0), parent=lid)
    export("poi_cache")


def build_geode():
    """A split open crystal geode that marks a resource hotspot."""
    reset_scene()
    rnd = random.Random(51)
    rock = mat("Rock", hexc("#4a4452"), 0.1, 0.8)
    crystal = mat("Accent", hexc("#7ff0ff"), 0.1, 0.1, emission=hexc("#39e5ff"), strength=1.4)
    root = empty("Geode")
    for side in (-1, 1):
        half = part(f"Half{side}", "sphere", (4.0, 2.4, 3.2), rock, loc=(1.8 * side, 0, 1.0), rot=(0, 0.5 * side, 0), parent=root, seg=10, rings=6, smooth=False)
        jitter_mesh(half, 0.2, 60 + side)
    for i in range(14):
        h = rnd.uniform(1.2, 3.6)
        part(f"Spike{i}", "cone", (0.5, 0.5, h), crystal, loc=(rnd.uniform(-1.3, 1.3), rnd.uniform(-1.0, 1.0), 0.4), offset=(0, 0, h / 2),
             rot=(rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), 0), parent=root, seg=6, r2=0.05, smooth=False)
    export("poi_geode")


# --------------------------------------------------------------------------
# towns
# --------------------------------------------------------------------------

def build_hab():
    """Dome habitat with a door, porthole windows and a roof beacon."""
    reset_scene()
    wall = mat("Shell", hexc("#e9edf2"), 0.2, 0.4)
    trim = mat("Accent", hexc("#39b6c9"), 0.4, 0.35)
    base = mat("Metal", hexc("#4a515e"), 0.7, 0.4)
    glow = mat("Window", (1, 1, 1), emission=hexc("#ffd98a"), strength=3)
    root = empty("Hab")
    part("Base", "cyl", (8.6, 8.6, 0.8), base, loc=(0, 0, 0.4), parent=root, seg=16)
    dome = part("Dome", "sphere", (8.0, 8.0, 7.0), wall, loc=(0, 0, 0.8), parent=root, seg=24, rings=12)
    part("Band", "torus", (8.1, 8.1, 8.1), trim, loc=(0, 0, 0.9), parent=root, minor=0.03)
    door = part("DoorFrame", "cube", (2.2, 1.6, 3.0), base, loc=(0, 3.4, 1.9), parent=root, bevel=0.2)
    part("Door", "cube", (1.5, 0.2, 2.4), glow, loc=(0, 0.75, 0), parent=door, bevel=0.05)
    for i in range(5):
        a = i / 5 * math.tau + 0.9
        part(f"Port{i}", "cyl", (0.9, 0.9, 0.2), glow, loc=(math.cos(a) * 3.5, math.sin(a) * 3.5, 3.0),
             rot=(math.pi / 2, 0, a + math.pi / 2), parent=root)
    part("Mast", "cyl", (0.2, 0.2, 2.0), base, loc=(0, 0, 4.2), offset=(0, 0, 1.0), parent=root)
    part("Beacon", "sphere", (0.5, 0.5, 0.5), mat("Beacon", (1, 1, 1), emission=hexc("#ff5d5d"), strength=6), loc=(0, 0, 6.3), parent=root)
    export("town_hab")


def build_workshop():
    """Boxy workshop with vents, a big shutter and crates."""
    reset_scene()
    rnd = random.Random(61)
    wall = mat("Shell", hexc("#c9b79c"), 0.1, 0.7)
    roof = mat("Accent", hexc("#b8412e"), 0.3, 0.5)
    metal = mat("Metal", hexc("#3b3f4a"), 0.7, 0.4)
    glow = mat("Window", (1, 1, 1), emission=hexc("#9be8ff"), strength=3)
    crate = mat("Crate", hexc("#8f6a44"), 0.0, 0.8)
    root = empty("Workshop")
    part("Body", "cube", (8, 6, 4.4), wall, loc=(0, 0, 2.2), parent=root, bevel=0.25)
    part("Roof", "cube", (8.6, 6.6, 0.6), roof, loc=(0, 0, 4.6), rot=(0.08, 0, 0), parent=root, bevel=0.1)
    part("Shutter", "cube", (3.6, 0.2, 3.0), metal, loc=(-1.2, 3.02, 1.6), parent=root, bevel=0.05)
    part("Window", "cube", (1.6, 0.2, 1.0), glow, loc=(2.4, 3.02, 2.6), parent=root, bevel=0.05)
    for i in range(3):
        part(f"Vent{i}", "cyl", (0.6, 0.6, 1.8), metal, loc=(-2.5 + i * 2.0, -1.5, 4.6), offset=(0, 0, 0.9), parent=root)
    for i in range(4):
        sz = rnd.uniform(0.8, 1.3)
        part(f"Crate{i}", "cube", (sz, sz, sz), crate, loc=(3.2 + (i % 2) * 1.3, 4.2 + (i // 2) * 1.1, sz / 2 + (1.0 if i == 3 else 0)),
             rot=(0, 0, rnd.uniform(-0.3, 0.3)), parent=root, bevel=0.05)
    export("town_workshop")


def build_tower():
    """Comm tower with a dish and a blinking light."""
    reset_scene()
    metal = mat("Metal", hexc("#9aa3b2"), 0.8, 0.3)
    dark = mat("Dark", hexc("#2b2f3a"), 0.7, 0.4)
    glow = mat("Beacon", (1, 1, 1), emission=hexc("#5ff7ff"), strength=6)
    root = empty("Tower")
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        part(f"Leg{i}", "cyl", (0.35, 0.35, 14.0), metal, loc=(math.cos(a) * 1.4, math.sin(a) * 1.4, 7.0),
             rot=(-math.sin(a) * 0.09, math.cos(a) * 0.09, 0), parent=root)
    for z in (3, 6.5, 10):
        part(f"Ring{z}", "torus", (2.6 - z * 0.08, 2.6 - z * 0.08, 2.6), dark, loc=(0, 0, z), parent=root, minor=0.06)
    part("Cab", "cube", (2.6, 2.6, 1.6), dark, loc=(0, 0, 14.2), parent=root, bevel=0.15)
    dish = part("Dish", "sphere", (3.2, 3.2, 1.0), metal, loc=(0.8, 0.8, 15.6), rot=(0.9, 0, 0.8), parent=root)
    part("Light", "sphere", (0.6, 0.6, 0.6), glow, loc=(0, 0, 16.6), parent=root)
    export("town_tower")


def build_stall():
    """Market stall with a striped awning, counter and goods."""
    reset_scene()
    wood = mat("Wood", hexc("#8f6a44"), 0.0, 0.8)
    awning = mat("Accent", hexc("#ffb347"), 0.0, 0.6)
    cloth = mat("Cloth", hexc("#f7f1e3"), 0.0, 0.7)
    goods = [mat("GoodsA", hexc("#3d8bff"), 0.4, 0.4), mat("GoodsB", hexc("#b98cff"), 0.1, 0.2, emission=hexc("#9b6bff"), strength=1.2),
             mat("GoodsC", hexc("#ffcf3f"), 0.0, 0.3, emission=hexc("#ffcf3f"), strength=1.5)]
    root = empty("Stall")
    part("Counter", "cube", (4.2, 1.4, 1.2), wood, loc=(0, 0.8, 0.6), parent=root, bevel=0.08)
    for x in (-2.0, 2.0):
        for y in (-0.9, 0.9):
            part(f"Post{x}{y}", "cyl", (0.16, 0.16, 3.2), wood, loc=(x, y, 1.6), parent=root)
    for i in range(4):
        part(f"Awn{i}", "cube", (1.1, 2.6, 0.12), awning if i % 2 == 0 else cloth, loc=(-1.65 + i * 1.1, 0, 3.25), rot=(0.18, 0, 0), parent=root)
    for i in range(6):
        part(f"Good{i}", "ico", (0.45, 0.45, 0.45), goods[i % 3], loc=(-1.6 + i * 0.65, 0.8, 1.45), parent=root, sub=1)
    export("town_stall")


def build_board():
    """Bounty board: a signpost frame with pinned notices."""
    reset_scene()
    wood = mat("Wood", hexc("#6f5234"), 0.0, 0.8)
    paper = mat("Paper", hexc("#f3ead2"), 0.0, 0.9)
    seal = mat("Accent", hexc("#e0453a"), 0.2, 0.4)
    glow = mat("Glow", (1, 1, 1), emission=hexc("#ffd23f"), strength=3)
    root = empty("Board")
    for x in (-1.6, 1.6):
        part(f"Post{x}", "cube", (0.3, 0.3, 3.4), wood, loc=(x, 0, 1.7), parent=root, bevel=0.04)
    part("Panel", "cube", (3.6, 0.2, 2.0), wood, loc=(0, 0, 2.2), parent=root, bevel=0.05)
    part("Roof", "cube", (4.0, 0.9, 0.2), wood, loc=(0, 0, 3.45), rot=(0.25, 0, 0), parent=root, bevel=0.04)
    for i, (x, z) in enumerate(((-1.0, 2.5), (0.1, 2.3), (1.1, 2.55), (-0.6, 1.7), (0.8, 1.75))):
        part(f"Note{i}", "cube", (0.8, 0.04, 0.9), paper, loc=(x, 0.12, z), rot=(0, (i - 2) * 0.05, 0), parent=root)
        part(f"Seal{i}", "cyl", (0.14, 0.14, 0.05), seal, loc=(x, 0.16, z + 0.3), rot=(math.pi / 2, 0, 0), parent=root)
    part("Lamp", "sphere", (0.3, 0.3, 0.3), glow, loc=(0, 0.3, 3.2), parent=root)
    export("town_board")


def build_townsfolk():
    """Generic townsfolk robot; Accent is re-tinted per NPC in Godot."""
    reset_scene()
    shell = mat("Shell", hexc("#e6e2d8"), 0.2, 0.45)
    accent = mat("Accent", hexc("#5a9bd8"), 0.3, 0.4)
    dark = mat("Metal", hexc("#2e3340"), 0.7, 0.4)
    root = empty("Robot")
    torso = part("Torso", "cyl", (0.8, 0.7, 0.9), accent, loc=(0, 0, 1.0), parent=root, seg=12)
    part("Apron", "cube", (0.6, 0.1, 0.6), shell, loc=(0, 0.35, -0.05), parent=torso, bevel=0.03)
    head = part("Head", "cube", (0.62, 0.55, 0.48), shell, loc=(0, 0, 0.45), offset=(0, 0, 0.24), parent=torso, bevel=0.14)
    robot_common_eye(head, hexc("#aef7ff"), 0.28, 0.26, 0.4, 0.1)
    part("Cap", "cyl", (0.66, 0.6, 0.12), accent, loc=(0, 0, 0.52), parent=head)
    for side, x in (("L", -1), ("R", 1)):
        arm = part(f"Arm{side}", "cyl", (0.14, 0.14, 0.6), dark, loc=(0.46 * x, 0, 0.3), offset=(0, 0, -0.27), parent=torso)
        part(f"Hand{side}", "sphere", (0.2, 0.2, 0.2), shell, loc=(0, 0, -0.6), parent=arm)
        leg = part(f"Leg{side}", "cyl", (0.16, 0.16, 0.55), dark, loc=(0.2 * x, 0, -0.42), offset=(0, 0, -0.24), parent=torso)
        part(f"Foot{side}", "cube", (0.26, 0.4, 0.14), shell, loc=(0, 0.05, -0.52), parent=leg, bevel=0.04)
    export("npc_townsfolk")


def build_lamp():
    reset_scene()
    metal = mat("Metal", hexc("#3b3f4a"), 0.7, 0.4)
    glow = mat("Glow", (1, 1, 1), emission=hexc("#ffd98a"), strength=5)
    root = empty("Lamp")
    part("Pole", "cyl", (0.2, 0.2, 3.4), metal, loc=(0, 0, 1.7), parent=root)
    part("Arm", "cube", (0.9, 0.12, 0.12), metal, loc=(0.35, 0, 3.3), parent=root)
    part("Bulb", "sphere", (0.45, 0.45, 0.35), glow, loc=(0.75, 0, 3.1), parent=root)
    export("town_lamp")


# --------------------------------------------------------------------------
# space: asteroids, comet nucleus, ore shard
# --------------------------------------------------------------------------

def _lumpy_rock(name, seed, material, radius=1.0, sub=3, rough=0.22, craters=5):
    rnd = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, subdivisions=sub)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.data.materials.append(material)
    # squash into a potato and add low-frequency lumps
    sx, sy, sz = rnd.uniform(0.75, 1.25), rnd.uniform(0.7, 1.1), rnd.uniform(0.6, 1.0)
    lumps = [(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized(), rnd.uniform(-0.25, 0.3)) for _ in range(7)]
    crater_list = [(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized(), rnd.uniform(0.25, 0.5)) for _ in range(craters)]
    for v in obj.data.vertices:
        d = v.co.normalized()
        r = 1.0
        for ld, amt in lumps:
            r += amt * max(0.0, d.dot(ld)) ** 3
        for cd, cr in crater_list:
            ang = math.acos(max(-1.0, min(1.0, d.dot(cd))))
            if ang < cr:
                x = ang / cr
                r -= 0.12 * (1 - x * x)
            elif ang < cr * 1.3:
                r += 0.04
        r += rnd.uniform(-rough, rough) * 0.3
        v.co = Vector((d.x * sx, d.y * sy, d.z * sz)) * r * radius
    return obj


def build_asteroids():
    for i in range(3):
        reset_scene()
        rnd = random.Random(700 + i)
        rock = mat("Rock", hexc("#7d7065"), 0.1, 0.9)
        vein = mat("Vein", hexc("#c9b8a6"), 0.6, 0.35, emission=hexc("#c9b8a6"), strength=0.8)
        root = empty("Asteroid")
        body = _lumpy_rock("Body", 900 + i, rock)
        body.parent = root
        for k in range(rnd.randint(6, 10)):
            d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized()
            part(f"Vein{k}", "ico", (0.28, 0.22, 0.2), vein, loc=tuple(d * 0.85), rot=(rnd.uniform(0, 3), rnd.uniform(0, 3), 0), parent=root, sub=0)
        export(f"asteroid_{i + 1}")


def build_comet():
    reset_scene()
    ice = mat("Rock", hexc("#dff4ff"), 0.0, 0.25)
    dirt = mat("Dirt", hexc("#4b5563"), 0.0, 0.9)
    glow = mat("Vein", (1, 1, 1), emission=hexc("#9be8ff"), strength=3)
    root = empty("Comet")
    body = _lumpy_rock("Body", 77, ice, sub=3, craters=3)
    body.parent = root
    dark = _lumpy_rock("Crust", 78, dirt, radius=0.92, sub=2, craters=2)
    dark.parent = root
    dark.location = (0.25, -0.1, -0.2)
    for k in range(8):
        a = k / 8 * math.tau
        part(f"Jet{k}", "ico", (0.22, 0.22, 0.22), glow, loc=(math.cos(a) * 0.9, math.sin(a) * 0.9, 0.3), parent=root, sub=1)
    export("comet_nucleus")


def build_shard():
    reset_scene()
    glow = mat("Vein", hexc("#ffffff"), 0.2, 0.2, emission=hexc("#ffffff"), strength=2)
    root = empty("Shard")
    part("Crystal", "ico", (0.5, 0.5, 1.0), glow, parent=root, sub=0, smooth=False)
    export("ore_shard")


# --------------------------------------------------------------------------
# space pirates (nose points Blender +Y = Godot -Z)
# --------------------------------------------------------------------------

def _engine_glow(parent, loc, color, r=0.35):
    glow = mat("EngineGlow", (1, 1, 1), emission=color, strength=6)
    part("Engine", "cyl", (r * 2, r * 2, 0.2), glow, loc=loc, rot=(math.pi / 2, 0, 0), parent=parent)


def build_raider():
    reset_scene()
    hull = mat("Shell", hexc("#2b2f3a"), 0.8, 0.35)
    red = mat("Accent", hexc("#d0342c"), 0.4, 0.4)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff2a2a"), strength=8)
    root = empty("Raider")
    body = part("Body", "cone", (1.4, 4.2, 1.0), hull, loc=(0, 0, 0), rot=(-math.pi / 2, 0, 0), parent=root, seg=6, r2=0.25, smooth=False)
    part("Cockpit", "sphere", (0.8, 1.2, 0.6), eye, loc=(0, 0.6, 0.35), parent=root)
    for side in (-1, 1):
        w = part(f"Wing{side}", "cube", (2.6, 1.6, 0.12), red, loc=(1.5 * side, -0.9, 0), rot=(0, 0.15 * side, -0.35 * side), parent=root, bevel=0.05)
        part(f"Gun{side}", "cyl", (0.14, 0.14, 1.6), hull, loc=(2.2 * side, 0.1, -0.1), rot=(math.pi / 2, 0, 0), parent=root)
        part(f"Fin{side}", "cube", (0.1, 1.0, 0.9), red, loc=(0.45 * side, -1.7, 0.5), rot=(0, 0.3 * side, 0), parent=root, bevel=0.03)
        _engine_glow(root, (0.45 * side, -2.15, 0), hexc("#ff6a2a"), 0.28)
    export("pirate_raider")


def build_gunship():
    reset_scene()
    hull = mat("Shell", hexc("#3a3440"), 0.7, 0.4)
    plate = mat("Accent", hexc("#9e2b25"), 0.5, 0.45)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff3d6e"), strength=7)
    root = empty("Gunship")
    part("Hull", "cube", (3.6, 6.0, 2.2), hull, parent=root, bevel=0.35)
    part("Armor", "cube", (3.9, 3.0, 0.5), plate, loc=(0, 0.6, 1.1), parent=root, bevel=0.12)
    part("Bridge", "cube", (1.4, 1.4, 0.9), eye, loc=(0, 2.4, 1.2), parent=root, bevel=0.15)
    for side in (-1, 1):
        pod = part(f"Pod{side}", "cyl", (1.4, 1.4, 4.2), hull, loc=(2.4 * side, -0.6, 0), rot=(math.pi / 2, 0, 0), parent=root)
        tur = part(f"Turret{side}", "sphere", (1.1, 1.1, 0.8), plate, loc=(1.2 * side, 1.4, 1.3), parent=root)
        part(f"Barrel{side}", "cyl", (0.22, 0.22, 1.6), hull, loc=(0, 0.9, 0.1), rot=(math.pi / 2, 0, 0), parent=tur)
        _engine_glow(root, (2.4 * side, -2.8, 0), hexc("#ff3d6e"), 0.55)
    export("pirate_gunship")


def build_swarmer():
    reset_scene()
    hull = mat("Shell", hexc("#26222c"), 0.8, 0.3)
    red = mat("Accent", hexc("#e0453a"), 0.3, 0.4)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff7a2a"), strength=8)
    root = empty("Swarmer")
    part("Core", "ico", (1.1, 1.1, 1.1), hull, parent=root, sub=1, smooth=False)
    part("Eye", "sphere", (0.5, 0.3, 0.5), eye, loc=(0, 0.5, 0), parent=root)
    for i in range(6):
        d = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0.7, -0.7, 0.5), (-0.7, -0.7, -0.5)][i]
        part(f"Spike{i}", "cone", (0.3, 0.3, 0.9), red, loc=(d[0] * 0.55, d[1] * 0.55, d[2] * 0.55),
             rot=(math.atan2(math.hypot(d[0], d[1]), d[2]), 0, math.atan2(-d[0], d[1])), offset=(0, 0, 0.4), parent=root, seg=5)
    export("pirate_swarmer")


def build_marauder():
    reset_scene()
    hull = mat("Shell", hexc("#2a2530"), 0.8, 0.35)
    gold = mat("Accent", hexc("#e8b93a"), 0.9, 0.25)
    eye = mat("Eye", (1, 1, 1), emission=hexc("#ff2a55"), strength=9)
    shield = mat("Shield", (1, 1, 1), emission=hexc("#ff5d9a"), strength=2)
    root = empty("Marauder")
    part("Hull", "cone", (4.4, 9.0, 2.4), hull, rot=(-math.pi / 2, 0, 0), parent=root, seg=8, r2=0.8, smooth=False)
    part("Spine", "cube", (0.8, 7.0, 1.2), gold, loc=(0, -0.4, 1.0), parent=root, bevel=0.15)
    part("Eye", "sphere", (1.6, 1.4, 0.9), eye, loc=(0, 2.4, 0.8), parent=root)
    part("Ring", "torus", (7.0, 7.0, 7.0), shield, loc=(0, -1.0, 0), rot=(math.pi / 2, 0, 0), parent=root, minor=0.05)
    for side in (-1, 1):
        part(f"Wing{side}", "cube", (4.0, 3.0, 0.3), hull, loc=(3.0 * side, -2.0, 0), rot=(0, 0, -0.25 * side), parent=root, bevel=0.1)
        part(f"Blade{side}", "cone", (0.6, 0.6, 3.0), gold, loc=(5.0 * side, -0.6, 0), rot=(-math.pi / 2, 0, 0), parent=root, seg=4)
        _engine_glow(root, (1.4 * side, -4.6, 0), hexc("#ff2a55"), 0.7)
    export("pirate_marauder")


# --------------------------------------------------------------------------
# orbital trade station (ring rotates in Godot: node "Ring")
# --------------------------------------------------------------------------

def build_station():
    reset_scene()
    hull = mat("Shell", hexc("#d9dee6"), 0.6, 0.35)
    dark = mat("Metal", hexc("#3a404c"), 0.8, 0.35)
    trim = mat("Accent", hexc("#ffb347"), 0.4, 0.4)
    glow = mat("Window", (1, 1, 1), emission=hexc("#ffe2a8"), strength=4)
    beacon = mat("Beacon", (1, 1, 1), emission=hexc("#5ff7ff"), strength=8)
    root = empty("Station")
    hub = part("Hub", "cyl", (8, 8, 16), hull, parent=root, seg=16)
    part("HubBand", "torus", (8.4, 8.4, 8.4), trim, loc=(0, 0, 3), parent=hub, minor=0.05)
    part("HubBand2", "torus", (8.4, 8.4, 8.4), trim, loc=(0, 0, -3), parent=hub, minor=0.05)
    part("CapTop", "sphere", (8, 8, 5), dark, loc=(0, 0, 8), parent=hub)
    part("CapBot", "sphere", (8, 8, 5), dark, loc=(0, 0, -8), parent=hub)
    part("Antenna", "cyl", (0.4, 0.4, 10), dark, loc=(0, 0, 13), offset=(0, 0, 5), parent=hub)
    part("AntennaLight", "sphere", (1.2, 1.2, 1.2), beacon, loc=(0, 0, 23.5), parent=hub)
    ring = empty("Ring", parent=root)
    part("RingHull", "torus", (44, 44, 44), hull, parent=ring, minor=0.09)
    part("RingWindows", "torus", (44.3, 44.3, 44.3), glow, parent=ring, minor=0.025)
    for i in range(6):
        a = i / 6 * math.tau
        part(f"Spoke{i}", "cyl", (1.2, 1.2, 18), dark, loc=(math.cos(a) * 12.5, math.sin(a) * 12.5, 0),
             rot=(0, math.pi / 2, a), parent=ring)
        part(f"Pod{i}", "cube", (5, 3, 3), hull, loc=(math.cos(a + 0.5) * 22, math.sin(a + 0.5) * 22, 0), rot=(0, 0, a + 0.5), parent=ring, bevel=0.4)
    for side in (-1, 1):
        arm = part(f"Dock{side}", "cube", (3, 3, 12), dark, loc=(0, 0, side * 14), offset=(0, 0, side * 5), parent=root, bevel=0.3)
        part(f"DockLight{side}", "torus", (4, 4, 4), beacon, loc=(0, 0, side * 11), parent=arm, minor=0.08)
    export("orbital_station")


# --------------------------------------------------------------------------
# cosmetic parts. Materials: Shell / Accent / Metal / Eye get recoloured by
# the player's paint job; anything else keeps its own colour.
# Heads + toppers: origin at the base. Packs: origin at the mount point,
# body extends backward (Blender -Y) with nozzles pointing down.
# --------------------------------------------------------------------------

def _cos_mats():
    return (mat("Shell", hexc("#e6e8ec"), 0.2, 0.4), mat("Accent", hexc("#18c2b0"), 0.3, 0.35),
            mat("Metal", hexc("#2a3140"), 0.8, 0.35), mat("Eye", (1, 1, 1), emission=hexc("#5ff7ff"), strength=6))


def build_heads():
    # dome with a wraparound visor
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    h = part("Dome", "sphere", (0.66, 0.62, 0.56), shell, loc=(0, 0, 0.28), parent=root)
    part("Visor", "torus", (0.62, 0.58, 0.5), eye, loc=(0, 0, 0.02), rot=(0.25, 0, 0), parent=h, minor=0.06)
    part("Collar", "cyl", (0.5, 0.5, 0.1), metal, loc=(0, 0, 0.03), parent=root)
    export("head_dome")
    # boxy head with a scanner strip
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    b = part("Box", "cube", (0.66, 0.58, 0.5), shell, loc=(0, 0, 0.28), parent=root, bevel=0.12)
    part("Strip", "cube", (0.5, 0.06, 0.12), eye, loc=(0, 0.3, 0.04), parent=b, bevel=0.03)
    for sd in (-1, 1):
        part(f"Ear{sd}", "cyl", (0.2, 0.2, 0.12), accent, loc=(0.36 * sd, 0, 0.02), rot=(0, math.pi / 2, 0), parent=b)
    export("head_box")
    # crested knight helm
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    hm = part("Helm", "sphere", (0.62, 0.66, 0.6), shell, loc=(0, 0, 0.3), parent=root)
    part("Slit", "cube", (0.44, 0.08, 0.07), eye, loc=(0, 0.31, 0.02), parent=hm, bevel=0.02)
    part("Crest", "cone", (0.12, 0.7, 0.5), accent, loc=(0, -0.05, 0.28), offset=(0, 0, 0.2), parent=hm, seg=4, r2=0.02, smooth=False)
    export("head_crest")
    # cyclops mono-eye
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    m = part("Ball", "sphere", (0.64, 0.64, 0.64), shell, loc=(0, 0, 0.32), parent=root)
    ring = part("EyeRing", "cyl", (0.4, 0.4, 0.1), metal, loc=(0, 0.28, 0.02), rot=(math.pi / 2, 0, 0), parent=m)
    part("Eye", "sphere", (0.3, 0.12, 0.3), eye, loc=(0, 0.05, 0), rot=(-math.pi / 2, 0, 0), parent=ring)
    part("Band", "torus", (0.66, 0.66, 0.66), accent, loc=(0, 0, -0.08), parent=m, minor=0.05)
    export("head_mono")


def build_toppers():
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    part("Rod", "cyl", (0.05, 0.05, 0.6), metal, offset=(0, 0, 0.3), parent=root)
    part("Ball", "sphere", (0.16, 0.16, 0.16), eye, loc=(0, 0, 0.62), parent=root)
    export("top_antenna")
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    for sd in (-1, 1):
        part(f"Horn{sd}", "cone", (0.14, 0.14, 0.5), accent, loc=(0.2 * sd, 0, 0), offset=(0, 0, 0.22), rot=(0, 0.45 * sd, 0), parent=root, seg=10)
    export("top_horns")
    reset_scene()
    black = mat("Hat", hexc("#1c1c22"), 0.1, 0.6)
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    part("Brim", "cyl", (0.62, 0.62, 0.05), black, loc=(0, 0, 0.02), parent=root)
    part("Crown", "cyl", (0.4, 0.4, 0.45), black, offset=(0, 0, 0.24), parent=root)
    part("Band", "cyl", (0.41, 0.41, 0.08), accent, loc=(0, 0, 0.09), parent=root)
    export("top_tophat")
    reset_scene()
    gold = mat("Gold", hexc("#f2c14e"), 1.0, 0.2)
    gem = mat("Gem", (1, 1, 1), emission=hexc("#ff3d6e"), strength=3)
    root = empty("Part")
    part("Band", "cyl", (0.5, 0.5, 0.14), gold, offset=(0, 0, 0.07), parent=root, seg=10)
    for i in range(5):
        a = i / 5 * math.tau
        part(f"Spike{i}", "cone", (0.12, 0.12, 0.22), gold, loc=(math.cos(a) * 0.22, math.sin(a) * 0.22, 0.13), offset=(0, 0, 0.1), parent=root, seg=4)
    part("Gem", "ico", (0.12, 0.12, 0.12), gem, loc=(0, 0.25, 0.08), parent=root, sub=0)
    export("top_crown")
    reset_scene()
    stem = mat("Stem", hexc("#4f9d3a"), 0.0, 0.7)
    petal = mat("Petal", hexc("#ff7eb6"), 0.0, 0.5)
    centre = mat("Centre", hexc("#ffd23f"), 0.0, 0.4)
    root = empty("Part")
    part("Stem", "cyl", (0.04, 0.04, 0.4), stem, offset=(0, 0, 0.2), rot=(0.25, 0, 0), parent=root)
    fl = empty("Flower", loc=(0, 0.1, 0.4), parent=root)
    part("Centre", "sphere", (0.14, 0.14, 0.08), centre, parent=fl)
    for i in range(6):
        a = i / 6 * math.tau
        part(f"Petal{i}", "sphere", (0.14, 0.08, 0.04), petal, loc=(math.cos(a) * 0.12, math.sin(a) * 0.12, 0), rot=(0, 0, a), parent=fl)
    export("top_flower")
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    part("Post", "cyl", (0.06, 0.06, 0.25), metal, offset=(0, 0, 0.12), parent=root)
    d = part("Dish", "sphere", (0.42, 0.42, 0.14), shell, loc=(0, 0, 0.28), rot=(0.6, 0, 0.4), parent=root)
    part("Feed", "cyl", (0.03, 0.03, 0.2), metal, loc=(0, 0, 0.1), parent=d)
    part("Tip", "sphere", (0.07, 0.07, 0.07), eye, loc=(0, 0, 0.2), parent=d)
    export("top_dish")


def build_packs():
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    for sd in (-1, 1):
        body = part(f"Rocket{sd}", "cyl", (0.26, 0.26, 0.9), shell, loc=(0.2 * sd, -0.05, 0.05), parent=root)
        part(f"Nose{sd}", "cone", (0.26, 0.26, 0.3), accent, loc=(0, 0, 0.6), parent=body)
        part(f"Nozzle{sd}", "cone", (0.3, 0.3, 0.22), metal, loc=(0, 0, -0.52), rot=(math.pi, 0, 0), parent=body, r2=0.16)
        part(f"Fin{sd}", "cube", (0.04, 0.3, 0.3), accent, loc=(0.14 * sd, 0, -0.3), parent=body)
    export("pack_rockets")
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    part("Pod", "cube", (0.36, 0.3, 0.5), metal, loc=(0, -0.05, 0.0), parent=root, bevel=0.08)
    for sd in (-1, 1):
        part(f"Wing{sd}", "cube", (1.1, 0.35, 0.05), accent, loc=(0.6 * sd, -0.12, 0.2), rot=(0, 0.35 * sd, -0.4 * sd), parent=root, bevel=0.02)
        part(f"WingTip{sd}", "sphere", (0.1, 0.1, 0.1), eye, loc=(1.12 * sd, -0.12, 0.42), parent=root)
    part("Nozzle", "cone", (0.26, 0.26, 0.2), shell, loc=(0, -0.05, -0.32), rot=(math.pi, 0, 0), parent=root, r2=0.14)
    export("pack_wings")
    reset_scene()
    shell, accent, metal, eye = _cos_mats()
    root = empty("Part")
    part("Hub", "sphere", (0.36, 0.3, 0.36), metal, loc=(0, -0.08, 0), parent=root)
    part("Ring", "torus", (0.95, 0.95, 0.95), accent, loc=(0, -0.12, 0), rot=(math.pi / 2, 0, 0), parent=root, minor=0.07)
    part("RingGlow", "torus", (0.95, 0.95, 0.95), eye, loc=(0, -0.13, 0), rot=(math.pi / 2, 0, 0), parent=root, minor=0.02)
    for i in range(3):
        a = i / 3 * math.tau + math.pi / 2
        part(f"Strut{i}", "cyl", (0.05, 0.05, 0.4), shell, loc=(math.cos(a) * 0.22, -0.1, math.sin(a) * 0.22), rot=(0, -a + math.pi / 2, 0), parent=root)
    export("pack_ring")


# --------------------------------------------------------------------------
# the Deep: cave mouth, fossil, relic pedestal
# --------------------------------------------------------------------------

def build_cave_mouth():
    reset_scene()
    rnd = random.Random(81)
    rock = mat("Rock", hexc("#6b625a"), 0.05, 0.9)
    dark = mat("Hole", hexc("#050407"), 0.0, 1.0)
    glow = mat("Glyph", (1, 1, 1), emission=hexc("#ffb347"), strength=3)
    moss = mat("Foliage", hexc("#5f8f45"), 0.0, 0.9)
    root = empty("Cave")
    # ring of jumbled boulders forming a mouth that opens downward
    for i in range(11):
        a = i / 11 * math.tau
        r = part(f"Rock{i}", "ico", (rnd.uniform(2.2, 3.4), rnd.uniform(2.0, 3.0), rnd.uniform(1.6, 3.2)), rock,
                 loc=(math.cos(a) * 4.2, math.sin(a) * 4.2, rnd.uniform(0.4, 1.4)), parent=root, sub=1)
        jitter_mesh(r, 0.2, 100 + i)
    arch = part("Arch", "torus", (7.5, 7.5, 9.0), rock, loc=(0, 1.2, 2.6), rot=(math.pi / 2 + 0.35, 0, 0), parent=root, minor=0.16)
    part("Hole", "cyl", (7.2, 7.2, 0.4), dark, loc=(0, 0, 0.12), parent=root, seg=20)
    part("Shaft", "cyl", (6.6, 6.6, 3.0), dark, loc=(0, 0, -1.4), parent=root, seg=20)
    for i in range(5):
        a = rnd.uniform(0, math.tau)
        part(f"Moss{i}", "sphere", (1.4, 1.0, 0.5), moss, loc=(math.cos(a) * 4.6, math.sin(a) * 4.6, 2.3), parent=root)
    for i in range(4):
        a = i / 4 * math.tau + 0.4
        part(f"Lamp{i}", "cyl", (0.12, 0.12, 1.6), mat("Pole", hexc("#3b3f4a"), 0.7, 0.4), loc=(math.cos(a) * 6.8, math.sin(a) * 6.8, 0), offset=(0, 0, 0.8), parent=root)
        part(f"Bulb{i}", "sphere", (0.35, 0.35, 0.35), glow, loc=(math.cos(a) * 6.8, math.sin(a) * 6.8, 1.75), parent=root)
    export("poi_cave")


def build_fossil():
    reset_scene()
    bone = mat("Bone", hexc("#e8dcc4"), 0.0, 0.7)
    stone = mat("Rock", hexc("#8a7a66"), 0.0, 0.9)
    root = empty("Fossil")
    slab = part("Slab", "cube", (2.6, 1.6, 0.4), stone, loc=(0, 0, 0.2), rot=(0.3, 0, 0), parent=root, bevel=0.15)
    part("Skull", "sphere", (0.5, 0.4, 0.2), bone, loc=(-0.9, 0, 0.25), parent=slab)
    for i in range(7):
        part(f"Vert{i}", "sphere", (0.18, 0.14, 0.12), bone, loc=(-0.5 + i * 0.22, 0.05 * math.sin(i), 0.25), parent=slab)
    for i in range(4):
        part(f"Rib{i}", "torus", (0.45, 0.45, 0.45), bone, loc=(-0.2 + i * 0.25, 0, 0.26), rot=(0, 0, math.pi / 2), parent=slab, minor=0.05)
    export("cave_fossil")


def build_pedestal():
    reset_scene()
    stone = mat("Stone", hexc("#3a3444"), 0.2, 0.5)
    gold = mat("Gold", hexc("#f2c14e"), 1.0, 0.25)
    glow = mat("Glyph", (1, 1, 1), emission=hexc("#ffd98a"), strength=5)
    root = empty("Pedestal")
    part("Base", "cyl", (1.6, 1.6, 0.3), stone, loc=(0, 0, 0.15), parent=root, seg=8, smooth=False)
    part("Column", "cyl", (0.9, 0.9, 1.0), stone, loc=(0, 0, 0.8), parent=root, seg=8, smooth=False)
    part("Top", "cyl", (1.3, 1.3, 0.2), gold, loc=(0, 0, 1.4), parent=root, seg=8)
    part("Relic", "ico", (0.55, 0.55, 0.75), glow, loc=(0, 0, 1.95), parent=root, sub=0)
    part("Halo", "torus", (1.1, 1.1, 1.1), gold, loc=(0, 0, 1.95), rot=(math.pi / 2, 0, 0), parent=root, minor=0.04)
    export("cave_pedestal")


if __name__ == "__main__":
    build_scout()
    build_miner()
    build_engineer()
    build_siphon()
    build_archivist()
    build_rock("res_ferrite", "#7d7065", "#c9b8a6", 1)
    build_rock("res_cobalt", "#566172", "#3d8bff", 2, glow=True)
    build_crystal()
    build_fiber_plant()
    build_spore_pod()
    build_energy_well()
    build_void_shard()
    build_tree_lollipop()
    build_tree_spiral()
    build_mushroom_tree()
    build_cactus()
    build_ice_spike()
    build_boulder()
    build_critter()
    build_outpost()
    build_terminal_only()
    build_scrapper()
    build_sentinel()
    build_brute()
    build_turret()
    build_monolith()
    build_ruin()
    build_crash()
    build_cache()
    build_geode()
    build_hab()
    build_workshop()
    build_tower()
    build_stall()
    build_board()
    build_townsfolk()
    build_lamp()
    build_asteroids()
    build_comet()
    build_shard()
    build_raider()
    build_gunship()
    build_swarmer()
    build_marauder()
    build_station()
    build_heads()
    build_toppers()
    build_packs()
    build_cave_mouth()
    build_fossil()
    build_pedestal()
    print("[star-circuit] done")
