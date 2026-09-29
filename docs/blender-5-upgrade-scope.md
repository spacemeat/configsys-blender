# Scope: moving the recipe from Blender 4.3.2 to 5.2.x

**Status:** IMPLEMENTED (2026-09-28/29) as a side-by-side `blender-5.2` component beside
`blender-4.3` (see "What was done" at the end). Original scope follows.

configsys *shows* the gap: the source methods declare `upstream:`, so `configsys versions`,
`inspect`, and the TUI (`[R]` in LATEST + the detail line) say "recipe pins 4.3.2; upstream is 5.2.2 —
a new version needs a NEW RECIPE".

This is **not an upgrade** in configsys's sense. A pinned `ref:` bump changes the compiler, the Python
ABI of `bpy`, and the GPU SDK floors — each a recipe/route change that must be validated by a real
build, not a version-string edit.

## What changes between 4.3.2 and 5.2.2 (from Blender's own build files)

| | 4.3.2 | 5.2.2 | Source |
|---|---|---|---|
| GCC minimum | **11.0** | **14.0** | `CMakeLists.txt` (`The minimum supported version of GCC is …`) |
| Clang minimum | 8.0 | 17.0 | same |
| Bundled Python (bpy ABI) | 3.11.9 | **3.13.13** | `build_files/build_environment/cmake/versions.cmake` |
| OptiX minimum | 7.3.0 | **8.0.0** | `intern/cycles/CMakeLists.txt` (`find_package(OptiX …)`) |
| OSL / OpenVDB | 1.13.7 / 11.0 | 1.15.3 / 13.0 | `versions.cmake` (precompiled libs — `make update`) |
| NVIDIA driver (Cycles UI floor) | — | ≥ 575 (raised from 570 in 5.2.1) | 5.2.1 tag note |

## Work items

1. **Compiler: gcc-11 → gcc-14.** The recipe currently *requires* `gcc-11` and falls back off a
   too-new default g++. For 5.x that inverts: 14 is the floor. `gcc-14` exists in base `routes.hu`;
   on Ubuntu 22.04 (this desktop, Pop 22.04) it comes from the ubuntu-toolchain-r PPA (14.3 is
   published for jammy); 24.04 has it natively. Fedora ships 14/15 natively — the "no gcc-11 on
   Fedora" unmet-require in the current recipe goes away. EL: check `gcc-toolset-14`.
   - Update `requires: [ gcc-11 ]` → `[ gcc-14 ]` on every source binding, and the compiler knobs in
     `build-blender.sh` (`CXX_OVERRIDE` / the "no g++<=12 found" warning logic).
2. **nvcc host compiler.** CUDA caps the host GCC it accepts. Confirm the CUDA version configsys
   installs (`cuda-toolkit`) accepts gcc-14 as nvcc's host compiler; if not, the recipe's existing
   "nvcc host-compiler cap" step must pick a separate, older host compiler for nvcc only.
   **Open question — verify against NVIDIA's CUDA installation guide for the installed version.**
3. **bpy: Python 3.11 → 3.13.** `bpy` is ABI-locked to Blender's bundled CPython. The recipe's
   `bpy-venv` must be rebuilt on 3.13 (and `blender-python` glue then points at it). Anyone importing
   `bpy` from their own interpreter needs 3.13.
4. **OptiX.** Floor rises 7.3 → 8.0. The SDK already configured (`NVIDIA-OptiX-SDK-8.0.0`) meets it.
   The binding's `optix-max-version: 8` was a 4.3 ceiling — **open question: does 5.2 accept OptiX 9?**
   If yes, raise or drop the cap; if not, keep 8.
5. **HIP / oneAPI.** Check 5.2's minimum ROCm/HIP and oneAPI versions against the `rocm-hip` and
   `intel-oneapi-basekit` components before offering those flavors on 5.x (no hardware here to test).
6. **Precompiled libraries.** `make update` fetches lib/linux_x64 for the checked-out ref; verify the
   recipe's fetch step still works for 5.x (library layout / git-lfs).
7. **The ref itself.** `ref: v4.3.2` → `v5.2.2` on all five bindings, in ONE change with 1–3, since
   they're interdependent. Keep `upstream:` as is.
8. **Plugin release.** Tag (e.g. `v0.2.0` — a toolchain-breaking change), bump the ref in the primary
   config, `plugin sync` + `plugin trust`.

## Validation

- **Real builds, not version-string checks.** At minimum: the CPU flavor (`blender-build`) and the
  flavor in use here (`blender-optix`) on this desktop. ~40+ min each.
- Confirm: the editor launches; `blender --version` reports 5.2.2; `blender-python -c "import bpy;
  print(bpy.app.version_string)"` works; Cycles lists the OptiX device.
- Confirm the method-switch path: the old 4.3.2 build tree is rebuilt in place (same `dir:`) or kept
  alongside — decide which (a side-by-side `dir:` keeps a known-good 4.3 while validating 5.2).
- A podman container build (Ubuntu 24.04, CPU flavor) to prove the recipe on a clean machine.

## Risks

- gcc-14 via a PPA on 22.04 is a toolchain change on the host; it is parallel-installable (like
  gcc-11 was) but should be called out in the plan the user approves.
- A too-new nvcc host compiler is the most likely hard failure (item 2).
- bpy users' scripts pinned to 3.11 will break (item 3).

## Effort

Roughly: half a day of recipe/route edits and research on items 2/4/5, plus 2–3 long real builds
to validate. Don't start it inside other work — do it as its own change set.

## What was done (2026-09-28/29)

**Side by side, not a replacement.** The single `blender` component's source methods became two
versioned components — `blender-4.3` (unchanged recipe) and `blender-5.2` — each `provides: { blender:
<ver> }` + `never-auto` (the python3.X / jdk-N pattern), each building in its own `blender-<ver>-git`.
Pick a version; pin its GPU flavor. A future Blender is another component, never an upgrade.

**Toolchain as core dependencies.** 5.2 requires core `gcc-14` and passes it explicitly (`cc:`/`cxx:`
binding fields → the recipe's CC/CXX_OVERRIDE). Its CUDA/OptiX methods require `cuda-toolkit:
">=12.8,<13"`, which selects the new core **`cuda-toolkit-12.8`**, and pin it via `cuda-root:`
(`/usr/local/cuda-12.8`; the recipe then uses THAT nvcc and its host-compiler cap).

**Why CUDA 12.8 (tested on the dev machine, RTX 2070 / driver 580):** CUDA 12.6's nvcc refuses gcc-14
as a host compiler (`host_config.h: gcc versions later than 13 are not supported`), and forcing it
(`-allow-unsupported-compiler`) fails compiling libstdc++-14 headers; 12.6 also can't target `sm_120`,
in 5.2's default arch list. CUDA 13 dropped sm_50–sm_72, which 5.2 still builds — hence `<13`. 5.2
does NOT use cuDNN (its denoiser is OpenImageDenoise 2.5). Note: a distro `/usr/bin/nvcc` (CUDA 11.5 on
Ubuntu 22.04) sits first on PATH — `cuda-root:` keeps the build off it.

**Glue.** One `blender-source-glue` for all versions: `blender-<ver>` / `blender-python-<ver>` per built
version; plain `blender` / `blender-python` = the newest (`CONFIGSYS_BLENDER=4.3` to override). Reads the
glue-locations cache (the machine's PICKS — so pick the version). Tested in bash/zsh/fish/elvish.

**Validation — Ubuntu 24.04 container, CPU flavor (`blender-build`), via `configsys install
blender-5.2`:** configured with GNU 14.3.0; editor built (~2 h on 8 cores) and runs (`Blender 5.2.2
LTS`, embedded Python 3.13.13); bpy built and installed into `bpy-venv` on Blender's bundled Python
3.13.13 (`import bpy` → 5.2.2 LTS, default scene loads); a rerun after an interruption RESUMED (caches
kept, no wipe); `configsys versions blender-5.2` → installed v5.2.2; the installed bash glue put the
5.2 editor first on PATH and `blender-python` imported bpy.

**Not yet validated:** the OptiX/CUDA flavors on real hardware (needs sudo on the dev machine: CUDA
12.8 install + build deps); HIP/oneAPI 5.2 floors; OptiX 9 acceptance (capped at 8).

**Migration** (README): the old `blender` pin errors in `check`; rename `blender-git` →
`blender-4.3-git`, recreate its `bpy-venv` from Blender's bundled Python + the wheel left in the tree
(tested: bpy 4.3.2 imports), re-pin on `blender-4.3`, reinstall the glue — no rebuild.
