# Blender built from source (configsys-blender), every version side by side:
#   blender-<ver> / blender-python-<ver>  for each version that's BUILT (e.g. blender-5.2, blender-4.3)
#   blender / blender-python              the NEWEST built version — its build dir goes FIRST on PATH,
#                                         ahead of a distro /usr/bin/blender. CONFIGSYS_BLENDER=4.3
#                                         makes plain `blender` an older one.
# blender-python runs the interpreter that version's bpy was built against (its bpy-venv).
# Locations come from configsys's glue-locations cache (~1ms); only a cold/stale (>1h) cache costs one
# `configsys location --all` (which rewrites it).
_bl_locs=""
_bl_cache="${CONFIGSYS_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/configsys}/glue-locations.tsv"
if [ -f "$_bl_cache" ] && [ -n "$(find "$_bl_cache" -mmin -60 2>/dev/null)" ]; then
    _bl_locs=$(cat "$_bl_cache")
else
    _bl_locs=$(configsys location --all 2>/dev/null)
fi
_bl_def=""
for _v in 5.2 4.3; do                                  # newest first
    _loc=$(printf '%s\n' "$_bl_locs" | awk -F'\t' -v n="blender-$_v" '$1 == n { print $2; exit }')
    [ -n "$_loc" ] || continue
    if [ -x "$_loc/build_linux/bin/blender" ]; then
        alias "blender-$_v=$_loc/build_linux/bin/blender"
        if [ -z "$_bl_def" ] && { [ -z "${CONFIGSYS_BLENDER:-}" ] || [ "$CONFIGSYS_BLENDER" = "$_v" ]; }; then
            _bl_def="$_loc"
        fi
    fi
    [ -x "$_loc/bpy-venv/bin/python" ] && alias "blender-python-$_v=$_loc/bpy-venv/bin/python"
done
if [ -n "$_bl_def" ]; then
    export PATH="$_bl_def/build_linux/bin:$PATH"
    [ -x "$_bl_def/bpy-venv/bin/python" ] && alias blender-python="$_bl_def/bpy-venv/bin/python"
fi
unset _bl_locs _bl_cache _bl_def _v _loc
