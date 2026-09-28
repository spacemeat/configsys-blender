# Blender built from source (configsys-blender): editor first on PATH; `blender-python` = bpy's interpreter.
use path
var loc = (cs-loc blender)
if (not-eq $loc '') {
  var bin = $loc/build_linux/bin
  if (and (path:is-regular $bin/blender) (not (has-value $paths $bin))) { set paths = [$bin $@paths] }
  if (path:is-regular $loc/bpy-venv/bin/python) {
    edit:add-var blender-python~ {|@a| (external $loc/bpy-venv/bin/python) $@a }
  }
}
