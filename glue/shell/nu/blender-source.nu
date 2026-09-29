# Blender built from source (configsys-blender), every version side by side:
#   blender-<ver> / blender-python-<ver> for each BUILT version; blender / blender-python -> the NEWEST
#   built one (its build dir first on PATH). CONFIGSYS_BLENDER=4.3 makes plain `blender` an older one.
let bl_built = ([5.2 4.3] | each {|v| let l = (cs-loc $"blender-($v)"); { v: $"($v)", loc: $l } }
    | where {|r| ($r.loc != "") and ($"($r.loc)/build_linux/bin/blender" | path exists) })
let bl_def = ($bl_built | where {|r| ($env.CONFIGSYS_BLENDER? | is-empty) or ($env.CONFIGSYS_BLENDER == $r.v) } | get --optional 0.loc | default "")
if ($bl_def != "") { cs-prepend $"($bl_def)/build_linux/bin" }
$env.__cs_blender = ($bl_built | reduce -f {} {|r, acc| $acc | insert $r.v $r.loc })
$env.__cs_blender_def = $bl_def
def --wrapped blender-python [...rest] { if ($env.__cs_blender_def? | is-not-empty) { ^$"($env.__cs_blender_def)/bpy-venv/bin/python" ...$rest } else { print -e "blender-python: no from-source Blender build" } }
def --wrapped "blender-5.2" [...rest] { let l = ($env.__cs_blender | get --optional "5.2"); if ($l != null) { ^$"($l)/build_linux/bin/blender" ...$rest } else { print -e "blender-5.2: not built" } }
def --wrapped "blender-4.3" [...rest] { let l = ($env.__cs_blender | get --optional "4.3"); if ($l != null) { ^$"($l)/build_linux/bin/blender" ...$rest } else { print -e "blender-4.3: not built" } }
def --wrapped "blender-python-5.2" [...rest] { let l = ($env.__cs_blender | get --optional "5.2"); if ($l != null) { ^$"($l)/bpy-venv/bin/python" ...$rest } else { print -e "blender-python-5.2: not built" } }
def --wrapped "blender-python-4.3" [...rest] { let l = ($env.__cs_blender | get --optional "4.3"); if ($l != null) { ^$"($l)/bpy-venv/bin/python" ...$rest } else { print -e "blender-python-4.3: not built" } }
