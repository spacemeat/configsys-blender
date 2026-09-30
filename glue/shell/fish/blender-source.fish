# Blender built from source (configsys-blender), every version side by side:
#   blender / blender-python      the version BLENDER_VERSION names, read AT LAUNCH; unset = the NEWEST
#                                 built one. Prints a one-line note (stderr) of which version + what's built.
#   blender-<ver> / blender-python-<ver>   that version directly. The newest build is also first on PATH.
set -l cache (string join / (set -q CONFIGSYS_STATE_DIR; and echo $CONFIGSYS_STATE_DIR; or echo (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/configsys) glue-locations.tsv)
set -l locs
if test -f $cache; and test -n (find $cache -mmin -60 2>/dev/null | string collect)
    set locs (cat $cache)
else
    set locs (configsys location --all 2>/dev/null)
end
set -g __cs_blender_vers
set -g __cs_blender_locs
for v in 5.2 4.3
    set -l loc (string match -r "^blender-$v\t(.*)" -- $locs)[2]
    test -n "$loc"; and test -x "$loc/build_linux/bin/blender"; or continue
    set -a __cs_blender_vers $v
    set -a __cs_blender_locs $loc
    alias blender-$v "$loc/build_linux/bin/blender"
    test -x "$loc/bpy-venv/bin/python"; and alias blender-python-$v "$loc/bpy-venv/bin/python"
end
if set -q __cs_blender_vers[1]
    fish_add_path -gP "$__cs_blender_locs[1]/build_linux/bin"   # scripts: the newest build
    function __cs_blender_run
        set -l rel $argv[1]; set -l name $argv[2]; set -e argv[1..2]
        set -l i 1
        if set -q BLENDER_VERSION; and test -n "$BLENDER_VERSION"
            set i (contains -i -- $BLENDER_VERSION $__cs_blender_vers)
            if test -z "$i"
                echo "$name: BLENDER_VERSION=$BLENDER_VERSION isn't built — built: $__cs_blender_vers" >&2
                return 1
            end
        end
        echo "$name: launching $__cs_blender_vers[$i] — built: $__cs_blender_vers (BLENDER_VERSION=<ver> picks another)" >&2
        $__cs_blender_locs[$i]/$rel $argv
    end
    function blender; __cs_blender_run build_linux/bin/blender blender $argv; end
    function blender-python; __cs_blender_run bpy-venv/bin/python blender-python $argv; end
end
