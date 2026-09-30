# configsys-blender

A [configsys](https://github.com/spacemeat/configsys) **code plugin** that builds Blender
(editor + the `bpy` Python module) from source, so `import bpy` matches the editor.

Base's native `blender` stays what `install blender` gets — nothing auto-builds. Each **Blender
version** is its own component — `blender-4.3`, `blender-5.2` — side by side (separate build dirs, so
both can be installed at once: `blender-4.3-git`, `blender-5.2-git`), and each **GPU flavor** is a pinnable install method on it:

```console
$ configsys picks add blender-5.2              # or tick it in the TUI Profiles screen
$ configsys where blender-5.2                  # the flavors: blender-build (CPU, default), blender-cuda,
                                               #   blender-optix, blender-hip, blender-oneapi
$ configsys pin set blender-5.2 blender-optix
$ configsys install blender-5.2                # pulls that version's toolchain (gcc-14, CUDA 12.8)
```

Each version carries its own toolchain as core dependencies — 4.3: `gcc-11` (+ `cuda-toolkit`);
5.2: `gcc-14` (+ `cuda-toolkit-12.8` for CUDA/OptiX). Pinning a flavor pulls just that flavor's SDK;
an unpicked version drags in nothing. **A new Blender release is a new component**, not an upgrade:
each version's `ref:` is pinned, and configsys shows `[R]` (a newer upstream needs a new recipe).

## Migrating from the single `blender` component (plugin < v0.2)

The source methods moved from `blender` to the versioned components, and each version builds in its
own `blender-<ver>-git` dir. An old method pin on `blender` now errors in `configsys check`
("pinned to via:'blender-optix', which is not a binding"). To keep an existing 4.3 build (no rebuild):

```console
$ mv ~/src/blender-git ~/src/blender-4.3-git        # the build dir blender-4.3 now uses
$ cd ~/src/blender-4.3-git                          # repair the bpy venv (it recorded the old path):
$ blender/lib/linux_x64/python/bin/python3.11 -m venv --clear --system-site-packages bpy-venv
$ bpy-venv/bin/pip install --quiet bpy-4.3.2-*.whl  # the wheel the build left here
$ configsys pin unset blender
$ configsys picks rm blender && configsys picks add blender-4.3   # (if blender was picked)
$ configsys pin set blender-4.3 blender-optix                      # your flavor
$ configsys install blender-source-glue                            # refresh the shell glue
```

Why the venv step: a venv is not relocatable — its `python` links, `pyvenv.cfg` and `pip` shebangs
hold absolute paths. The built editor itself runs fine after the move, and a later REBUILD of a moved
tree is handled by the recipe (it notices a build dir configured for another path and reconfigures).
`configsys versions blender-4.3` should then read `installed`.

- `blender.py` — the `blender-build` driver + thin per-flavor subclasses (`blender-cuda`, …), each
  presetting a backend; `gpu:`→CMake mapping + toolchain validation live in the base class.
- `build-blender.sh` — the build recipe (edit the knobs: compiler, bpy install target).
- `blender.hu` — the versioned components (`blender-4.3`, `blender-5.2`): one binding per flavor via.

The GPU SDK components a `gpu:` build depends on (`cuda-toolkit`, `rocm-hip`,
`intel-oneapi-basekit`) live in **base configsys** (`routes.hu`), not this plugin.

Because it ships code, it needs a one-time `configsys plugin trust configsys-blender`.
See `docs/PLAN.md` for the decisions and the parked work.

## Methods (which flavor `pin` selects)

| `via:` | backend preset | `requires:` (SDK, from base) | pin with |
|---|---|---|---|
| `blender-build` | none (CPU) | — | `pin set blender-<ver> blender-build` |
| `blender-cuda` | `cuda` | `cuda-toolkit` (5.2: `>=12.8,<13`) | `pin set blender-<ver> blender-cuda` |
| `blender-optix` | `cuda` + `optix` | `cuda-toolkit` (5.2: `>=12.8,<13`) (+ `optix-root:`) | `pin set blender-<ver> blender-optix` |
| `blender-hip` | `hip` | `rocm-hip` | `pin set blender-<ver> blender-hip` |
| `blender-oneapi` | `oneapi` | `intel-oneapi-basekit` | `pin set blender-<ver> blender-oneapi` |

Each via is a thin subclass that presets its backend, so the flavor is chosen by **which method you
pin** — no editing. The GPU methods carry a `when:` on the vendor they need (`gpu:nvidia` for
CUDA/OptiX, `gpu:amd` for HIP, `gpu:intel` for oneAPI), so the **Components** screen only offers the
ones valid on this machine; the CPU build is always offered, and **Profiles** lists them all (for
authoring across machines). The base source-build fields apply to every binding:

| field | values | default | meaning |
|---|---|---|---|
| `ref` | git tag/branch, e.g. `v5.2.2` | (default branch) | version to build — fixed per versioned component |
| `cc` / `cxx` | compiler commands, e.g. `gcc-14` / `g++-14` | (recipe default) | the version's compiler (5.x needs GCC >= 14) |
| `cuda-root` | a CUDA toolkit dir, e.g. `/usr/local/cuda-12.8` | (nvcc on PATH) | pin the version-matched CUDA (not a stale `/usr/bin/nvcc`) |
| `dir` | path (scope-honored) | `blender-git` | build-tree parent — bare-relative → `$CONFIGSYS_SRC_DIR/<dir>`; each version uses `blender-<ver>-git` |
| `target` | `editor` \| `bpy` \| `both` | `both` | what to build |
| `gpu` | list of backend tokens / vendor aliases | (the via's preset) | **override** the backend set on a single binding (see below) |
| `requires` | SDK component name(s) | — | **must list the SDK for the backend** (auto-installed by resolution) |

## Shell glue (`blender-source-glue`)

Every source method `suggests:` **`blender-source-glue`**, which ships in this plugin
(`glue/shell/<shell>/blender-source.*` — bash, zsh, fish, nu, elvish). In a new shell, for every
version that's BUILT:

- **`blender-<ver>`** (`blender-5.2`, `blender-4.3`) runs that build, and **`blender-python-<ver>`** the
  interpreter its `bpy` was built against (the build's `bpy-venv`);
- plain **`blender`** / **`blender-python`** launch the version **`BLENDER_VERSION`** names, read at
  launch time — the NEWEST built one when it's unset — and say so first, on stderr:

  ```console
  $ blender
  blender: launching 5.2 — built: 5.2 4.3 (BLENDER_VERSION=<ver> picks another)
  $ BLENDER_VERSION=4.3 blender               # just this once
  $ export BLENDER_VERSION=4.3                # this shell, from now on
  ```

  (A `BLENDER_VERSION` that isn't built errors, listing what is.) These are shell functions, so scripts
  don't see them: for scripts, the newest build's dir is also first on `PATH` (ahead of a distro
  `/usr/bin/blender`), or call `<build>/build_linux/bin/blender` directly.

It's a binding-level suggestion, so it's attached only while a source method is installed; configsys
removes it with the last one (a method switch, or `configsys remove blender-<ver>`). Locations come
from configsys's glue-locations cache, so it adds ~no shell-startup time.

## GPU backends (the `gpu:` override + `requires:`)

GPU support is a *set* of backends compiled into one build (additive — exactly how Blender's
official builds ship). Each `via:` presets its set (table above); a binding-level `gpu:` **overrides**
it and can compile several at once. Physical card count is irrelevant to the build; Cycles picks
devices at render time. Whatever the backend set, name the matching SDK in the **same binding's**
`requires:` so resolution installs it. The driver validates each toolchain is present before a long
build and fails loud (never a silent CPU fallback).

| `gpu:` token | CMake flag(s) set | `requires:` (SDK component) | toolchain probe | notes |
|---|---|---|---|---|
| `cuda` | `WITH_CYCLES_CUDA_BINARIES=ON` | `cuda-toolkit` | `nvcc` | NVIDIA general compute |
| `optix` | `WITH_CYCLES_DEVICE_OPTIX=ON` (+ CUDA binaries) + `OPTIX_ROOT_DIR` | `cuda-toolkit` **+ `optix-root:`** | `nvcc` + `optix.h` | RTX ray-tracing; implies the CUDA toolchain |
| `hip` | `WITH_CYCLES_HIP_BINARIES=ON` | `rocm-hip` | `hipcc` | AMD |
| `oneapi` | `WITH_CYCLES_DEVICE_ONEAPI=ON` (+ ONEAPI binaries) | `intel-oneapi-basekit` | `icpx` | Intel Arc / Xe |

Vendor aliases (sugar): `nvidia` → `cuda`+`optix`, `amd` → `hip`, `intel` → `oneapi`. A build may
combine backends: `gpu: [ cuda, optix, hip ]  requires: [ cuda-toolkit, rocm-hip ]`.

**OptiX is special.** CUDA installs itself (`requires: cuda-toolkit`), but the OptiX SDK's build
headers are **EULA-gated and can't be auto-fetched**. Download the SDK once from
[developer.nvidia.com](https://developer.nvidia.com/designworks/optix/download) (accept its EULA),
unpack it, and set **`optix-root:`** to that directory on the binding. The driver validates
`<optix-root>/include/optix.h` exists and passes `OPTIX_ROOT_DIR` to cmake — a missing/unset
`optix-root` fails fast with guidance, not a raw cmake error.  The OptiX version must match your Blender `ref`'s era (Blender 4.3 → OptiX **8.x**; OptiX 9's coop-vector headers don't compile against 4.3). Set **`optix-max-version:`** (a major int) and the driver prints the SDK version and *warns before the build* if it's newer — overridable, never fatal. The OptiX *runtime* ships with the NVIDIA driver (`libnvoptix`), so there's nothing else to install. (No `optix-root` needed for a
CUDA-only build — drop `optix` from `gpu:`.)

Example NVIDIA binding:

```
blender: { install: [
    { via: blender-build  ref: v4.3.2  dir: blender-4.3-git  target: both
      gpu: [ cuda, optix ]  requires: [ cuda-toolkit ]
      optix-root: ~/optix/NVIDIA-OptiX-SDK-8.0.0-linux64-x86_64  optix-max-version: 8 }
] }
```

> The token→flag table above and the driver's `_GPU_FLAGS`/`_GPU_PROBE` maps are the same
> information — keep them in lockstep when adding a backend.

## Recipe knobs (`build-blender.sh`)

These are yours to edit at the top of the script (the driver doesn't touch them):

| knob | default | meaning |
|---|---|---|
| `CC_OVERRIDE` / `CXX_OVERRIDE` | auto: system compiler, but falls back to newest `g++ <= 13` if the default is `>= 14` (Blender's bundled libs don't build with GCC 14+) | e.g. `gcc-13` / `g++-13` |
| `BPY_PIP` | (empty) → auto: a `--system-site-packages` venv built from Blender's **own bundled Python** (`lib/<platform>/python/bin/python3.N`), so `bpy` is ABI-matched and self-contained (no system Python needed). Result lands in `<dir>/bpy-venv`. | set to a `pip … install` command to install into a pip of your choice instead |

**Using `bpy` after a `both`/`bpy` build:** run it from the venv the recipe made —
`<dir>/bpy-venv/bin/python -c 'import bpy; print(bpy.app.version_string)'` (or activate that venv).

`GPU_CMAKE` in the script is computed by the driver from `gpu:` and passed in the environment —
don't hand-edit it.

## Detecting what's built + `locations:`

`get_version` reports installed **only for the GPU flavor actually built**. Each build stamps a
`.configsys-variant` marker (its via + backends); a build configsys made is identified exactly, and
one it didn't is best-effort probed from compiled Cycles kernels (`*.optixir`→optix, `*.cubin`→cuda,
`*.hipfb`→hip). So `configsys versions blender` names which flavor is built, and — even unpinned —
`configsys inspect` surfaces a source build as *"also present"*. Built Blender somewhere nonstandard?
Point configsys at it: `locations: { blender-4.3: /path/to/blender-4.3-git }` in your config.
