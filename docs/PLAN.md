# configsys-blender — decisions

A configsys **code plugin** that builds Blender (editor + `bpy` module) from source, overriding
base configsys's native `blender` where this plugin is loaded + trusted. Structure: a thin
`blender-build` driver (orchestration) + `build-blender.sh` (the recipe you own) + a `blender`
component override.

## Locked (decided)

- **Target: editor + bpy**, from one source tree (`make` then `make bpy`), so the module matches
  the editor by construction. `get_version` = `bpy` importable.
- **Recipe split:** driver does safe orchestration (clone/checkout/run/state); the wavy recipe is
  `build-blender.sh` (compiler / bpy-install / GPU are commented knobs there). No command comes
  from data, so no injection surface via other plugins.
- **Deps:** the recipe calls Blender's own `build_files/linux/install_linux_packages.py`
  (distro-aware, self-updating), after a tiny python3/git/git-lfs bootstrap.
- **Where:** its own plugin (NOT base configsys, NOT configsys-user). Drivers that turn out
  general + safe can graduate to base later.
- **GPU backends: a set-valued `gpu:` field + co-located `requires:`.** The build compiles Cycles
  kernels for a *set* of backends (cuda/optix/hip/oneapi) — additive, exactly how Blender's own
  releases ship, and independent of how many physical cards you have (runtime device count is a
  Cycles concern, not a build one). Because a driver only ever sees its own fields, backend
  selection MUST live on `blender`'s binding, not in a sibling component or a `when:` atom (and a
  `when:` atom couldn't union multiple vendors anyway — binding-select is winner-take-all). So:
  - `gpu: [ cuda, optix ]` on the binding drives the flags; the driver owns the token→flag map
    (encoding optix→CUDA-toolchain once) and validates each toolchain is on PATH, failing loud
    rather than dropping silently to CPU.
  - the **same binding** carries `requires: [ cuda-toolkit ]` — so the SDK is *declared and
    auto-resolved* like every other dependency (no "go install cuda by hand" — that would have
    broken the norm), and because it sits on the GPU binding only, a casual CPU build never pulls
    a heavyweight toolkit. The `gpu:`/`requires:` pair is two hand-kept lists; the driver's
    PATH validation catches a desync, so it's acceptable (decided: keep two lists).
  - SDK toolchains (`cuda-toolkit`, `rocm-hip`, `intel-oneapi-basekit`) are modeled as ordinary
    components in the plugin (`gpu-sdks.hu`).

## Open / defaults (proposed — override freely)

- Tree `~/blender-git` (`dir:` field), scope **user**; `ref: v4.3.2` (matches the release you run).
- bpy install = a wheel `pip install --user`, with a Python-version-match warning in the script
  (bpy is pinned to Blender's bundled CPython; use a venv on that Python for a clean match).
- `get_version` = `bpy` importable via `find_spec` (light; doesn't load Blender). Uninstall leaves
  the source tree in place.

## Parked (revisit)

- **Promote `cuda-toolkit` to base configsys.** It's a general-purpose component (used well beyond
  Blender); it starts in this plugin (`gpu-sdks.hu`) and should graduate to base once its binding
  is solid. Move the component definition, drop it from the plugin.
- **Real SDK repo wiring.** The `gpu-sdks.hu` bindings use distro-repo package names (first pass,
  often lagging/partial). NVIDIA's `cuda-toolkit` repo, AMD ROCm, and Intel oneAPI apt/dnf repos
  each need their own repo setup + versioned packages before these are production-grade.
- **GPU hardware detection (advisory only).** A helper that sniffs installed vendors
  (`lspci`/`nvidia-smi`/`/sys/class/drm`) and *suggests* a `gpu:` set + SDK component — never
  auto-populates the field (that would surprise, and would break build-here/deploy-there render
  nodes). Explicit `gpu:` stays the source of truth.
- **Per-backend nuance not yet modeled:** OptiX SDK headers (beyond the CUDA toolkit), compiler
  version pins some backends want, `OPTIX_ROOT_DIR`-style path knobs.
- Editor launch/PATH (a desktop entry or a bash.d alias to `build_linux/bin/blender`) — not done.
