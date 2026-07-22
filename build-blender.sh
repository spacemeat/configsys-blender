#!/usr/bin/env bash
# build-blender.sh — configsys-blender's build recipe, invoked by the blender-build driver as
#   build-blender.sh <ref> <root-dir> <target>
# Core is transcribed from the Blender docs (building_blender/linux + .../python_module).
# CPU-only today; GPU (CUDA/OptiX/HIP/OneAPI) is PARKED — see the marked knob + docs/PLAN.md.
#
# ---- YOU OWN THE KNOBS BELOW ----  (compiler, bpy install target, GPU)
set -euo pipefail

REF="${1:-}"                                   # git tag/branch, e.g. v4.3.2 (empty = default branch)
ROOT="${2:?build root dir required}"           # parent dir, e.g. ~/blender-git
TARGET="${3:-both}"                            # editor | bpy | both
SRC="$ROOT/blender"

# --- knobs -----------------------------------------------------------------
CC_OVERRIDE=""            # e.g. "gcc-14"  (empty = system default compiler)
CXX_OVERRIDE=""          # e.g. "g++-14"

# bpy install target. bpy is an ABI-locked extension for Blender's OWN bundled CPython (e.g. the
#   cp311 wheel imports ONLY under Python 3.11) — the system python is usually a different version,
#   so `import bpy` fails there. DEFAULT (BPY_PIP empty): the bpy step builds a venv FROM Blender's
#   bundled interpreter (perfectly ABI-matched, self-contained, no system Python needed) and
#   installs bpy into it — see the bpy step. Set BPY_PIP to a `pip ... install` command to instead
#   install into a pip of your choice (e.g. your own matching-version venv).
BPY_PIP="${BPY_PIP:-}"

# GPU: the driver computes GPU_CMAKE from the component's `gpu:` field (see the README token
# table) and passes it in the environment. Don't hand-edit this — change the gpu: field instead.
GPU_CMAKE="${GPU_CMAKE:-}"   # empty = CPU-only
# ---------------------------------------------------------------------------

# Blender's bundled libs (nanovdb/openvdb, ...) don't compile with a very new GCC — GCC >= 14
# rejects nanovdb's template bodies (-Wtemplate-body). Blender 4.3's reference compiler is GCC 11.
# So if no compiler is forced and the DEFAULT g++ is >= 14 (e.g. a machine whose update-alternatives
# points cc/g++ at gcc-15), fall back to the newest installed g++ <= 13. Override via CC/CXX_OVERRIDE.
if [ -z "$CXX_OVERRIDE" ] && command -v g++ >/dev/null 2>&1; then
    _gv=$(g++ -dumpversion 2>/dev/null | cut -d. -f1)
    if [ "${_gv:-0}" -ge 14 ] 2>/dev/null; then
        for _v in 13 12 11; do
            if command -v "g++-$_v" >/dev/null 2>&1 && command -v "gcc-$_v" >/dev/null 2>&1; then
                CC_OVERRIDE="gcc-$_v"; CXX_OVERRIDE="g++-$_v"
                echo "build-blender: default g++ is $_gv (too new for Blender's bundled libs) — using g++-$_v"
                break
            fi
        done
        [ -z "$CXX_OVERRIDE" ] && echo "build-blender: WARNING default g++ is $_gv and no g++<=13 found; build may fail on bundled libs" >&2
    fi
fi

# CUDA/OptiX kernels are compiled by nvcc, which rejects a HOST compiler newer than the CUDA
# toolkit supports (host_config.h: e.g. CUDA 11.5 allows gcc <= 11). Only nvcc hits this — Cycles'
# CUDA host .cpp uses the driver API via cuew, not cuda_runtime.h — so we DON'T lower the main
# compiler (which may need to be newer for Blender's bundled libs); we point just nvcc at a
# compatible g++ via CUDA_HOST_COMPILER (Cycles passes it to nvcc as -ccbin). Read the limit from
# the toolkit's host_config.h so it tracks whatever CUDA is installed.
case " $GPU_CMAKE " in
    *CUDA*|*OPTIX*)
        _cuda_max=""
        for _hc in /usr/include/crt/host_config.h /usr/local/cuda*/include/crt/host_config.h \
                   "$(command -v nvcc 2>/dev/null | xargs -r dirname 2>/dev/null)/../include/crt/host_config.h"; do
            if [ -f "$_hc" ]; then
                _cuda_max=$(grep -oE 'later than [0-9]+' "$_hc" 2>/dev/null | grep -oE '[0-9]+' | head -1)
                [ -n "$_cuda_max" ] && break
            fi
        done
        if [ -n "$_cuda_max" ]; then
            _v="$_cuda_max"
            while [ "$_v" -ge 8 ]; do
                if command -v "g++-$_v" >/dev/null 2>&1; then
                    GPU_CMAKE="$GPU_CMAKE -D CUDA_HOST_COMPILER=$(command -v "g++-$_v")"
                    echo "build-blender: CUDA toolkit caps the nvcc host compiler at g++ $_cuda_max — using g++-$_v for kernels"
                    break
                fi
                _v=$((_v - 1))
            done
        fi
    ;;
esac

CC_ENV=()
[ -n "$CC_OVERRIDE" ]  && CC_ENV+=("CC=$CC_OVERRIDE")
[ -n "$CXX_OVERRIDE" ] && CC_ENV+=("CXX=$CXX_OVERRIDE")

# 0. bootstrap: python3 + git + git-lfs (needed before Blender's own installer runs / we clone)
if   command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y python3 git git-lfs
elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y python3 git git-lfs
elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm python git git-lfs
elif command -v zypper  >/dev/null 2>&1; then sudo zypper install -y python3 git git-lfs
else echo "build-blender: unknown package manager — install python3/git/git-lfs yourself" >&2; fi

# 1. sources
# Create the build root. At user scope $ROOT is under ~ (writable directly). At system scope it's
# /opt/... — a normal user can't mkdir there, so fall back to sudo + hand ownership back, and the
# rest of the build runs unprivileged in place (world-readable under /opt — an admin can build
# Blender for all users, no root compile).
if ! mkdir -p "$ROOT" 2>/dev/null; then
    sudo mkdir -p "$ROOT" && sudo chown "$(id -un):$(id -gn)" "$ROOT"
fi
if [ ! -d "$SRC/.git" ]; then
    git clone https://projects.blender.org/blender/blender.git "$SRC"
fi
cd "$SRC"
[ -n "$REF" ] && git checkout "$REF"

# 2. build dependencies (Blender's own distro-aware installer; it self-sudos). Path is
#    build_files/build_environment/ as of 4.x — adjust if a future Blender moves it.
./build_files/build_environment/install_linux_packages.py

# 3. Precompiled libraries (a git-lfs submodule under lib/) + submodules + add-ons. CRUCIAL on
#    Linux: these precompiled libs are OPT-IN — plain `make update` leaves lib/<platform> EMPTY,
#    which makes cmake fall back to SYSTEM vulkan/shaderc/... (a dead end on distros that don't
#    package all of them as dev libs, e.g. Ubuntu 22.04 has no libshaderc-dev). Fetch them with
#    --use-linux-libraries (several GB via git-lfs) so the build is self-contained and immune to
#    old distro libs — the whole point of Blender's precompiled deps. Run the updater directly so
#    the flag reaches it (the `make update` wrapper doesn't forward it).
python3 ./build_files/utils/make_update.py --use-linux-libraries

# 4. build the requested target(s)
if [ "$TARGET" = editor ] || [ "$TARGET" = both ]; then
    env "${CC_ENV[@]}" make BUILD_CMAKE_ARGS="$GPU_CMAKE"
    echo "build-blender: editor at $ROOT/build_linux/bin"
fi
if [ "$TARGET" = bpy ] || [ "$TARGET" = both ]; then
    env "${CC_ENV[@]}" make bpy BUILD_CMAKE_ARGS="$GPU_CMAKE"
    # 5. package the module as a wheel and install it (into an ABI-matched interpreter).
    python3 ./build_files/utils/make_bpy_wheel.py "$ROOT/build_linux_bpy/bin" \
        --build-dir "$ROOT/build_linux_bpy" --output-dir "$ROOT"
    wheel=$(ls "$ROOT"/bpy-*.whl 2>/dev/null | head -1)
    [ -n "$wheel" ] || { echo "build-blender: no bpy wheel produced in $ROOT" >&2; exit 1; }
    if [ -n "$BPY_PIP" ]; then
        # user-chosen pip (their responsibility to match Blender's bundled Python version).
        $BPY_PIP "$wheel"
        echo "build-blender: bpy installed via BPY_PIP — test 'import bpy' under that interpreter"
    else
        # DEFAULT: a venv built from Blender's OWN bundled Python — the exact interpreter bpy was
        # compiled against, so it always matches (cp311 wheel -> the bundled 3.11), self-contained,
        # no system Python required. `lib/<platform>_<arch>/python/bin/python3.N` (has venv+pip).
        bpy_py=$(ls "$SRC"/lib/*/python/bin/python3.* 2>/dev/null | grep -E 'python3\.[0-9]+$' | head -1)
        [ -n "$bpy_py" ] || { echo "build-blender: bundled python not found under $SRC/lib/*/python/bin — set BPY_PIP to a matching-ABI pip" >&2; exit 1; }
        # --system-site-packages so the venv inherits Blender's bundled deps — critically numpy.
        # bpy is compiled against the bundled numpy's C-ABI (1.x here); a fresh PyPI numpy 2.x
        # breaks it with "_ARRAY_API not found". This runs bpy against exactly what Blender ships
        # (numpy/cython/requests/zstandard), no PyPI pull, and tracks whatever a future Blender
        # bundles. bpy itself installs into the venv and takes precedence.
        "$bpy_py" -m venv --clear --system-site-packages "$ROOT/bpy-venv"
        "$ROOT/bpy-venv/bin/pip" install --disable-pip-version-check --quiet "$wheel"
        echo "build-blender: bpy installed into $ROOT/bpy-venv (Blender's bundled $("$bpy_py" -V 2>&1))"
        echo "build-blender: test:  $ROOT/bpy-venv/bin/python -c 'import bpy; print(bpy.app.version_string)'"
    fi
fi
