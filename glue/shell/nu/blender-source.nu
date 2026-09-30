# Blender built from source (configsys-blender), every version side by side:
#   blender / blender-python      the version BLENDER_VERSION names, read AT LAUNCH; unset = the NEWEST
#                                 built one. Prints a one-line note (stderr) of which version + what's built.
#   blender-<ver> / blender-python-<ver>   that version directly. The newest build is also first on PATH.
$env.__cs_blenders = ([5.2 4.3] | each {|v| { v: $"($v)", loc: (cs-loc $"blender-($v)") } }
    | where {|r| ($r.loc != "") and ($"($r.loc)/build_linux/bin/blender" | path exists) })
if ($env.__cs_blenders | is-not-empty) { cs-prepend $"($env.__cs_blenders.0.loc)/build_linux/bin" }
def --wrapped cs-blender-run [rel: string, name: string, ...rest] {
  let built = ($env.__cs_blenders | get v | str join " ")
  if ($env.__cs_blenders | is-empty) { print -e $"($name): no from-source Blender build"; return }
  let want = ($env.BLENDER_VERSION? | default "")
  let pick = (if ($want == "") { $env.__cs_blenders.0 } else { $env.__cs_blenders | where v == $want | get --optional 0 })
  if ($pick == null) { print -e $"($name): BLENDER_VERSION=($want) isn't built — built: ($built)"; return }
  print -e $"($name): launching ($pick.v) — built: ($built) \(BLENDER_VERSION=<ver> picks another\)"
  ^$"($pick.loc)/($rel)" ...$rest
}
def --wrapped blender [...rest] { cs-blender-run "build_linux/bin/blender" "blender" ...$rest }
def --wrapped blender-python [...rest] { cs-blender-run "bpy-venv/bin/python" "blender-python" ...$rest }
def --wrapped "blender-5.2" [...rest] { let l = ($env.__cs_blenders | where v == "5.2" | get --optional 0.loc); if ($l != null) { ^$"($l)/build_linux/bin/blender" ...$rest } else { print -e "blender-5.2: not built" } }
def --wrapped "blender-4.3" [...rest] { let l = ($env.__cs_blenders | where v == "4.3" | get --optional 0.loc); if ($l != null) { ^$"($l)/build_linux/bin/blender" ...$rest } else { print -e "blender-4.3: not built" } }
def --wrapped "blender-python-5.2" [...rest] { let l = ($env.__cs_blenders | where v == "5.2" | get --optional 0.loc); if ($l != null) { ^$"($l)/bpy-venv/bin/python" ...$rest } else { print -e "blender-python-5.2: not built" } }
def --wrapped "blender-python-4.3" [...rest] { let l = ($env.__cs_blenders | where v == "4.3" | get --optional 0.loc); if ($l != null) { ^$"($l)/bpy-venv/bin/python" ...$rest } else { print -e "blender-python-4.3: not built" } }
