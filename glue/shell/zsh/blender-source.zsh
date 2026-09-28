# Blender built from source (configsys-blender): the editor goes FIRST on PATH — ahead of a distro
# /usr/bin/blender — and `blender-python` runs the interpreter the `bpy` module was built against.
# Attached only while a source method is blender's install method (a binding-level suggests), and
# removed with it when you switch methods or uninstall.
_bl=$(configsys location blender 2>/dev/null)
if [ -n "$_bl" ]; then
    [ -x "$_bl/build_linux/bin/blender" ] && export PATH="$_bl/build_linux/bin:$PATH"
    [ -x "$_bl/bpy-venv/bin/python" ] && alias blender-python="$_bl/bpy-venv/bin/python"
fi
unset _bl
