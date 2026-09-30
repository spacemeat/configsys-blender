# Blender built from source (configsys-blender), every version side by side:
#   blender / blender-python      the version BLENDER_VERSION names, read AT LAUNCH (export it, or
#                                 `BLENDER_VERSION=4.3 blender`); unset = the NEWEST built one. Prints a
#                                 one-line note (to stderr) of which version it launches + what's built.
#   blender-<ver> / blender-python-<ver>   that version directly (e.g. blender-5.2, blender-python-4.3)
# The newest build's dir also goes first on PATH, so scripts (which don't see shell functions) get a
# `blender` too. blender-python runs the interpreter that version's bpy was built against (bpy-venv).
# Locations come from configsys's glue-locations cache (~1ms); only a cold/stale (>1h) cache costs one
# `configsys location --all` (which rewrites it).
_bl_locs=""
_bl_cache="${CONFIGSYS_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/configsys}/glue-locations.tsv"
if [ -f "$_bl_cache" ] && [ -n "$(find "$_bl_cache" -mmin -60 2>/dev/null)" ]; then
    _bl_locs=$(cat "$_bl_cache")
else
    _bl_locs=$(configsys location --all 2>/dev/null)
fi
_CS_BLENDERS=""                                        # built versions, newest first: one "5.2=/path" per line
for _v in 5.2 4.3; do
    _loc=$(printf '%s\n' "$_bl_locs" | awk -F'\t' -v n="blender-$_v" '$1 == n { print $2; exit }')
    [ -n "$_loc" ] && [ -x "$_loc/build_linux/bin/blender" ] || continue
    _CS_BLENDERS="${_CS_BLENDERS:+$_CS_BLENDERS
}$_v=$_loc"
    alias "blender-$_v=$_loc/build_linux/bin/blender"
    [ -x "$_loc/bpy-venv/bin/python" ] && alias "blender-python-$_v=$_loc/bpy-venv/bin/python"
done
unset _bl_locs _bl_cache _v _loc

if [ -n "$_CS_BLENDERS" ]; then
    _loc=$(printf '%s\n' "$_CS_BLENDERS" | head -n 1); _loc=${_loc#*=}
    export PATH="$_loc/build_linux/bin:$PATH"          # scripts: the newest build
    unset _loc

    # _cs_blender_run <path-in-build> <command-name> [args…] — pick the build BLENDER_VERSION names
    _cs_blender_run() {
        local rel=$1 name=$2 pick="" built="" entry
        shift 2
        # a line-per-entry here-doc, not `for x in $list`: zsh doesn't word-split an unquoted
        # $var, and a pipe would run the loop in a subshell (losing $pick)
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            built="$built ${entry%%=*}"
            if [ -z "$pick" ] && { [ -z "${BLENDER_VERSION:-}" ] || [ "$BLENDER_VERSION" = "${entry%%=*}" ]; }; then
                pick=$entry
            fi
        done <<EOF_BLENDERS
$_CS_BLENDERS
EOF_BLENDERS
        if [ -z "$pick" ]; then
            echo "$name: BLENDER_VERSION=$BLENDER_VERSION isn't built — built:$built" >&2
            return 1
        fi
        [ -x "${pick#*=}/$rel" ] || { echo "$name: ${pick%%=*} has no $rel" >&2; return 1; }
        echo "$name: launching ${pick%%=*} — built:$built (BLENDER_VERSION=<ver> picks another)" >&2
        "${pick#*=}/$rel" "$@"
    }
    blender() { _cs_blender_run build_linux/bin/blender blender "$@"; }
    blender-python() { _cs_blender_run bpy-venv/bin/python blender-python "$@"; }
fi
