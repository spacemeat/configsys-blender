# Blender built from source (configsys-blender), every version side by side:
#   blender-<ver> / blender-python-<ver> for each BUILT version; blender / blender-python -> the NEWEST
#   built one (its build dir first on PATH). CONFIGSYS_BLENDER=4.3 makes plain `blender` an older one.
set -l cache (string join / (set -q CONFIGSYS_STATE_DIR; and echo $CONFIGSYS_STATE_DIR; or echo (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/configsys) glue-locations.tsv)
set -l locs
if test -f $cache; and test -n (find $cache -mmin -60 2>/dev/null | string collect)
    set locs (cat $cache)
else
    set locs (configsys location --all 2>/dev/null)
end
set -l def ""
for v in 5.2 4.3
    set -l loc (string match -r "^blender-$v\t(.*)" -- $locs)[2]
    test -n "$loc"; or continue
    if test -x "$loc/build_linux/bin/blender"
        alias blender-$v "$loc/build_linux/bin/blender"
        if test -z "$def"; and begin; not set -q CONFIGSYS_BLENDER; or test "$CONFIGSYS_BLENDER" = $v; end
            set def $loc
        end
    end
    test -x "$loc/bpy-venv/bin/python"; and alias blender-python-$v "$loc/bpy-venv/bin/python"
end
if test -n "$def"
    fish_add_path -gP "$def/build_linux/bin"   # -P: PATH itself (no reliance on fish_user_paths handlers)
    test -x "$def/bpy-venv/bin/python"; and alias blender-python "$def/bpy-venv/bin/python"
end
