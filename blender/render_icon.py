"""
Render the app icon (1024x1024) from the scout robot model.

    blender --background --factory-startup --python blender/render_icon.py
"""
import bpy, math, os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", "game"))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=os.path.join(GAME, "assets", "models", "robot_scout.glb"))
# frame the robot
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
mins = Vector((min(v[i] for o in objs for v in [o.matrix_world @ Vector(c) for c in o.bound_box]) for i in range(3)))
maxs = Vector((max(v[i] for o in objs for v in [o.matrix_world @ Vector(c) for c in o.bound_box]) for i in range(3)))
centre = (mins + maxs) / 2
# backdrop disc
cam_loc = Vector((centre.x + 1.4, centre.y + 6.0, centre.z + 1.0))
view = (centre - cam_loc).normalized()
bpy.ops.mesh.primitive_cylinder_add(radius=1.3, depth=0.05, location=centre + view * 1.8)
disc = bpy.context.active_object
disc.rotation_euler = view.to_track_quat("Z", "Y").to_euler()
m = bpy.data.materials.new("Disc")
m.use_nodes = True
bsdf = m.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.02, 0.05, 0.12, 1)
bsdf.inputs["Emission Color"].default_value = (0.05, 0.35, 0.45, 1)
bsdf.inputs["Emission Strength"].default_value = 0.6
disc.data.materials.append(m)
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(maxs.x - mins.x, maxs.z - mins.z) * 1.3
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = cam_loc
direction = centre - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = cam
for loc, energy in (((4, 5, 6), 900), ((-5, 3, 2), 300), ((0, -5, 4), 500)):
    l = bpy.data.lights.new("L", "POINT")
    l.energy = energy
    lo = bpy.data.objects.new("L", l)
    lo.location = loc
    bpy.context.collection.objects.link(lo)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x = 1024
sc.render.resolution_y = 1024
sc.render.film_transparent = True
sc.world = bpy.data.worlds.new("W")
sc.render.filepath = os.path.join(GAME, "icon.png")
bpy.ops.render.render(write_still=True)
print("[icon] wrote", sc.render.filepath)
