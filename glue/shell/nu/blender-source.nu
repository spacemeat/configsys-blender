# Blender built from source (configsys-blender): editor first on PATH; `blender-python` = bpy's interpreter.
let bl_loc = (cs-loc blender)
if (($bl_loc != "") and ($"($bl_loc)/build_linux/bin/blender" | path exists)) { cs-prepend $"($bl_loc)/build_linux/bin" }
$env.__cs_blender_py = (if (($bl_loc != "") and ($"($bl_loc)/bpy-venv/bin/python" | path exists)) { $"($bl_loc)/bpy-venv/bin/python" } else { "" })
def --wrapped blender-python [...rest] { if ($env.__cs_blender_py? | is-not-empty) { ^$env.__cs_blender_py ...$rest } else { print -e "blender-python: no from-source bpy build" } }
