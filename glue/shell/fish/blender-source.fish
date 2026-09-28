# Blender built from source (configsys-blender): editor first on PATH; `blender-python` = bpy's interpreter.
set -l loc (configsys location blender 2>/dev/null)
if test -n "$loc"
    test -x "$loc/build_linux/bin/blender"; and fish_add_path -g "$loc/build_linux/bin"
    test -x "$loc/bpy-venv/bin/python"; and alias blender-python "$loc/bpy-venv/bin/python"
end
