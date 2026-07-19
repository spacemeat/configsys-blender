# configsys-blender

A [configsys](https://github.com/spacemeat/configsys) **code plugin** that builds Blender
(editor + the `bpy` Python module) from source, so `import bpy` matches the editor. It
overrides base configsys's native `blender` wherever this plugin is loaded and trusted.

- `blender.py` — the `blender-build` driver (orchestration + `gpu:`→CMake mapping + validation).
- `build-blender.sh` — the build recipe (edit the knobs: compiler, bpy install target).
- `blender.hu` — the `blender` component override.
- `gpu-sdks.hu` — the GPU SDK components a `gpu:` build depends on.

Because it ships code, it needs a one-time `configsys plugin trust configsys-blender`.
See `docs/PLAN.md` for the decisions and the parked work.

## Component fields (`blender.hu`)

The `blender` binding is `{ via: blender-build ... }` with these fields:

| field | values | default | meaning |
|---|---|---|---|
| `ref` | git tag/branch, e.g. `v4.3.2` | (default branch) | version to build; pin it to match your editor |
| `dir` | path (scope-honored) | `blender-git` | build-tree parent — bare-relative → `~/<dir>` (user) or `/opt/<dir>` (system) |
| `target` | `editor` \| `bpy` \| `both` | `both` | what to build |
| `gpu` | list of backend tokens / vendor aliases | (absent = CPU-only) | Cycles GPU backends to compile kernels for (see below) |
| `requires` | SDK component name(s) | — | **must list the SDK for each `gpu:` backend** (auto-installed by resolution) |

## GPU backends (`gpu:` + `requires:`)

GPU support is a *set* of backends compiled into one build (additive — exactly how Blender's
official builds ship). Physical card count is irrelevant to the build; Cycles picks devices at
render time. Set `gpu:` to drive the flags **and** name the matching SDK in the **same
binding's** `requires:` so resolution installs it. The driver validates each toolchain is present
before a long build and fails loud (never a silent CPU fallback).

| `gpu:` token | CMake flag(s) set | `requires:` (SDK component) | toolchain probe | notes |
|---|---|---|---|---|
| `cuda` | `WITH_CYCLES_CUDA_BINARIES=ON` | `cuda-toolkit` | `nvcc` | NVIDIA general compute |
| `optix` | `WITH_CYCLES_DEVICE_OPTIX=ON` (+ CUDA binaries) | `cuda-toolkit` | `nvcc` | RTX ray-tracing; implies the CUDA toolchain |
| `hip` | `WITH_CYCLES_HIP_BINARIES=ON` | `rocm-hip` | `hipcc` | AMD |
| `oneapi` | `WITH_CYCLES_DEVICE_ONEAPI=ON` (+ ONEAPI binaries) | `intel-oneapi-basekit` | `icpx` | Intel Arc / Xe |

Vendor aliases (sugar): `nvidia` → `cuda`+`optix`, `amd` → `hip`, `intel` → `oneapi`. A build may
combine backends: `gpu: [ cuda, optix, hip ]  requires: [ cuda-toolkit, rocm-hip ]`.

Example NVIDIA binding:

```
blender: { install: [
    { via: blender-build  ref: v4.3.2  dir: blender-git  target: both
      gpu: [ cuda, optix ]  requires: [ cuda-toolkit ] }
] }
```

> The token→flag table above and the driver's `_GPU_FLAGS`/`_GPU_PROBE` maps are the same
> information — keep them in lockstep when adding a backend.

## Recipe knobs (`build-blender.sh`)

These are yours to edit at the top of the script (the driver doesn't touch them):

| knob | default | meaning |
|---|---|---|
| `CC_OVERRIDE` / `CXX_OVERRIDE` | (system compiler) | e.g. `gcc-14` / `g++-14` |
| `BPY_PIP` | `python3 -m pip install --user --force-reinstall` | how the `bpy` wheel is installed — **must run on the CPython `bpy` was built against** (point at a matching venv's `pip`) |

`GPU_CMAKE` in the script is computed by the driver from `gpu:` and passed in the environment —
don't hand-edit it.
