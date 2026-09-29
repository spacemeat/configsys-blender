# Blender built from source (configsys-blender), every version side by side:
#   blender-<ver> / blender-python-<ver> for each BUILT version; blender / blender-python -> the NEWEST
#   built one (its build dir first on PATH). CONFIGSYS_BLENDER=4.3 makes plain `blender` an older one.
use path
var bl-def = ''
for v [5.2 4.3] {
  var loc = (cs-loc blender-$v)
  if (and (not-eq $loc '') (path:is-regular $loc/build_linux/bin/blender)) {
    var bin = $loc/build_linux/bin/blender
    edit:add-var 'blender-'$v'~' {|@a| (external $bin) $@a }
    if (and (eq $bl-def '') (or (not (has-env CONFIGSYS_BLENDER)) (eq $E:CONFIGSYS_BLENDER $v))) {
      set bl-def = $loc
    }
  }
  if (and (not-eq $loc '') (path:is-regular $loc/bpy-venv/bin/python)) {
    var py = $loc/bpy-venv/bin/python
    edit:add-var 'blender-python-'$v'~' {|@a| (external $py) $@a }
  }
}
if (not-eq $bl-def '') {
  var bin = $bl-def/build_linux/bin
  if (not (has-value $paths $bin)) { set paths = [$bin $@paths] }
  if (path:is-regular $bl-def/bpy-venv/bin/python) {
    var py = $bl-def/bpy-venv/bin/python
    edit:add-var blender-python~ {|@a| (external $py) $@a }
  }
}
