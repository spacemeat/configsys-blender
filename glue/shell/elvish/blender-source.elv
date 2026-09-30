# Blender built from source (configsys-blender), every version side by side:
#   blender / blender-python      the version BLENDER_VERSION names, read AT LAUNCH; unset = the NEWEST
#                                 built one. Prints a one-line note (stderr) of which version + what's built.
#   blender-<ver> / blender-python-<ver>   that version directly. The newest build is also first on PATH.
use path
use str
var cs-blenders = []                              # [[ver loc] …], newest first, built only
for v [5.2 4.3] {
  var loc = (cs-loc blender-$v)
  if (and (not-eq $loc '') (path:is-regular $loc/build_linux/bin/blender)) {
    set cs-blenders = [$@cs-blenders [$v $loc]]
    var bin = $loc/build_linux/bin/blender
    edit:add-var 'blender-'$v'~' {|@a| (external $bin) $@a }
    if (path:is-regular $loc/bpy-venv/bin/python) {
      var py = $loc/bpy-venv/bin/python
      edit:add-var 'blender-python-'$v'~' {|@a| (external $py) $@a }
    }
  }
}
if (> (count $cs-blenders) 0) {
  var newest-bin = $cs-blenders[0][1]/build_linux/bin
  if (not (has-value $paths $newest-bin)) { set paths = [$newest-bin $@paths] }
  var blenders = $cs-blenders
  fn cs-blender-run {|rel name @a|
    var built = (str:join ' ' [(each {|e| put $e[0] } $blenders)])
    var pick = $blenders[0]
    if (and (has-env BLENDER_VERSION) (not-eq $E:BLENDER_VERSION '')) {
      var found = [(each {|e| if (eq $e[0] $E:BLENDER_VERSION) { put $e } } $blenders)]
      if (== (count $found) 0) { echo $name': BLENDER_VERSION='$E:BLENDER_VERSION" isn't built — built: "$built >&2; return }
      set pick = $found[0]
    }
    echo $name': launching '$pick[0]' — built: '$built' (BLENDER_VERSION=<ver> picks another)' >&2
    (external $pick[1]/$rel) $@a
  }
  edit:add-var blender~ {|@a| cs-blender-run build_linux/bin/blender blender $@a }
  edit:add-var blender-python~ {|@a| cs-blender-run bpy-venv/bin/python blender-python $@a }
}
