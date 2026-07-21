'''blender.py — the `blender-build` driver for the configsys-blender plugin.

Builds Blender (editor and/or the `bpy` Python module) from source. The driver does the safe,
generic orchestration (locate + run the recipe, translate the `gpu:` field into Cycles CMake
flags, report state); the actual, wavy recipe lives in `build-blender.sh` right next to this
file — edit that to own the tweakable bits (compiler version, the bpy install target). See
docs/PLAN.md and README.md.

Component shape:
    blender: { install: [ { via: blender-build  ref: v4.3.2  dir: blender-git  target: both
                            gpu: [ cuda, optix ]  requires: [ cuda-toolkit ] } ] }
  ref     git tag/branch to build   (empty = default branch)
  dir     build-tree parent, scope-honored (bare-relative -> ~/<dir> user, /opt/<dir> system)
  target  editor | bpy | both
  gpu     Cycles GPU backends to compile kernels for: a list of tokens (cuda, optix, hip,
          oneapi) or vendor aliases (nvidia -> cuda+optix, amd -> hip, intel -> oneapi). Absent
          = CPU-only. The driver maps these to WITH_CYCLES_* flags AND validates that each
          backend's toolchain is present (the toolchain itself must be declared via the same
          binding's `requires:`, e.g. cuda-toolkit — see the README token table). The gpu: list
          and the requires: list are the two lists the author keeps in sync; a mismatch (gpu
          names a backend whose toolchain isn't installed) is caught here, loudly, before a long
          build — never a silent CPU fallback.

`get_version` reports built once `bpy` is importable. Uninstall LEAVES the source tree in place
(auto-removing a checkout with your local work is too destructive). The driver is user-space; the
recipe's dependency step sudos itself (Blender's install_linux_packages.py).
'''

import shlex
from pathlib import Path

from configsys.plugins import Driver, Result

# a light "is bpy installed?" probe — find_spec doesn't actually import (and load) Blender
_HAS_BPY = ('python3 -c "import importlib.util,sys; '
            'sys.exit(0 if importlib.util.find_spec(\'bpy\') else 1)"')

# Cycles GPU backends. Each token -> the CMake -D flags it turns on (optix needs the CUDA
# toolchain, so it also flips the CUDA binaries flag) and -> a (toolchain probe, SDK component)
# pair. The SDK component name is what the binding's `requires:` should list AND what the error
# message points at. Keep this table and the README's token table in lockstep.
_GPU_FLAGS = {
    'cuda':   ['-D WITH_CYCLES_CUDA_BINARIES=ON'],
    'optix':  ['-D WITH_CYCLES_DEVICE_OPTIX=ON', '-D WITH_CYCLES_CUDA_BINARIES=ON'],
    'hip':    ['-D WITH_CYCLES_HIP_BINARIES=ON'],
    'oneapi': ['-D WITH_CYCLES_DEVICE_ONEAPI=ON', '-D WITH_CYCLES_ONEAPI_BINARIES=ON'],
}
_GPU_PROBE = {
    'cuda':   ('command -v nvcc',  'cuda-toolkit'),
    'optix':  ('command -v nvcc',  'cuda-toolkit'),   # OptiX kernels build with the CUDA toolchain
    'hip':    ('command -v hipcc', 'rocm-hip'),
    'oneapi': ('command -v icpx',  'intel-oneapi-basekit'),
}
_GPU_ALIAS = {'nvidia': ['cuda', 'optix'], 'amd': ['hip'], 'intel': ['oneapi']}


class BlenderBuild(Driver):
    name = 'blender-build'
    privileged = False
    default_scope = 'user'
    honors_scope = True

    def _build_dir(self, rc):
        return self.scoped_dir(rc.fields.get('dir') or 'blender-git', rc)

    def _script(self, rc):
        # build-blender.sh ships next to the .hu that defined this component (the plugin dir)
        root = Path(rc.source).parent if rc.source else Path('.')
        return root / 'build-blender.sh'

    # -- gpu backends -----------------------------------------------------

    def _gpu_backends(self, rc):
        '''The `gpu:` field expanded to canonical backend tokens (aliases resolved, deduped,
        order preserved). Raises ValueError on an unknown token.'''
        raw = rc.fields.get('gpu') or []
        if isinstance(raw, str):
            raw = [raw]
        out = []
        for tok in raw:
            for b in _GPU_ALIAS.get(tok, [tok]):
                if b not in _GPU_FLAGS:
                    raise ValueError(
                        f'unknown gpu backend {b!r} (want one of {", ".join(_GPU_FLAGS)}, '
                        f'or an alias {", ".join(_GPU_ALIAS)})')
                if b not in out:
                    out.append(b)
        return out

    def _gpu_cmake(self, backends):
        '''The deduped CMake flag string for a set of backends (empty = CPU-only).'''
        flags = []
        for b in backends:
            for f in _GPU_FLAGS[b]:
                if f not in flags:
                    flags.append(f)
        return ' '.join(flags)

    # -- read -------------------------------------------------------------

    def get_version(self, rc):
        '''The version actually built = what the source tree is checked out at, via
        `git describe --tags`. For a tag build (`ref: v4.3.2`) that's exactly the tag, so it
        matches get_latest (the ref) and the menu reads "up to date" instead of "built" vs
        "v4.3.2". "installed" still means bpy is importable; a master build describes as
        `<tag>-<n>-g<hash>`. Falls back to 'built' if the tree has no describable tag.'''
        if not self.runner.run(_HAS_BPY).ok:
            return None
        src = self._build_dir(rc) / 'blender'
        r = self.runner.run(f'git -C {shlex.quote(str(src))} describe --tags')
        return (r.stdout.strip() if r.ok else '') or 'built'

    def get_latest(self, rc):
        # the version you'd (re)build = the declared ref; matches get_version for a tag build.
        return rc.fields.get('ref') or 'built'

    def is_locked(self, rc):
        return False

    # -- mutate -----------------------------------------------------------

    def install(self, rc):
        script = self._script(rc)
        if not script.exists():
            return Result(f'(blender-build: recipe {script} not found)', 1)
        try:
            backends = self._gpu_backends(rc)
        except ValueError as e:
            return Result(f'(blender-build: {e})', 1)
        # Each requested backend needs its toolchain on PATH. That toolchain must be declared via
        # the same binding's `requires:` (so resolution installs it); we verify here and fail
        # loud rather than quietly dropping to a CPU-only build. (Under --pretend every probe
        # reports ok, so this never spuriously blocks a dry run.)
        for b in backends:
            probe, sdk = _GPU_PROBE[b]
            if not self.runner.run(probe).ok:
                return Result(
                    f"(blender-build: gpu {b!r} requested but its toolchain is missing — add "
                    f"the {sdk!r} component to this binding's requires:, then sync)", 1)
        gpu_cmake = self._gpu_cmake(backends)
        ref = shlex.quote(rc.fields.get('ref') or '')
        d = shlex.quote(str(self._build_dir(rc)))
        target = shlex.quote(rc.fields.get('target') or 'both')
        env = f'GPU_CMAKE={shlex.quote(gpu_cmake)} ' if gpu_cmake else ''
        return self.runner.run(
            f'{env}bash {shlex.quote(str(script))} {ref} {d} {target}', capture=False)

    def upgrade(self, rc):
        return self.install(rc)   # fetch + checkout + rebuild

    def set_version(self, rc, version):
        return self.install(rc)

    def uninstall(self, rc):
        return Result(f'(blender-build: leaving {self._build_dir(rc)} in place; remove it by hand)', 0)

    def reconcile_scope(self, rc, detected, target):
        # MOVE the build tree between ~/blender-git and /opt/blender-git — never rebuild (the base
        # reinstall would recompile for ~40 min). The bpy wheel is pip --user (scope-agnostic), so
        # nothing else to touch. sudo when either side is /opt; chown back to the user on ->user.
        d = rc.fields.get('dir') or 'blender-git'
        had, saved = 'scope' in rc.fields, rc.fields.get('scope')
        try:
            rc.fields['scope'] = detected
            old = self._build_dir(rc)
            rc.fields['scope'] = target
            new = self._build_dir(rc)
        finally:
            if had:
                rc.fields['scope'] = saved
            else:
                rc.fields.pop('scope', None)
        if old == new:
            return Result('(blender-build: already at the declared scope)', 0)
        tail = f' && chown -R "$USER" {shlex.quote(str(new))}' if (target == 'user' and detected == 'system') else ''
        return self.runner.run(
            f'mkdir -p {shlex.quote(str(new.parent))} && mv {shlex.quote(str(old))} '
            f'{shlex.quote(str(new))}{tail}',
            sudo='system' in (detected, target), capture=False)

    def lock(self, rc):
        return Result('(blender-build lock recorded in ledger)', 0)

    def unlock(self, rc):
        return Result('(blender-build unlock recorded in ledger)', 0)

    def location(self, rc):
        return str(self._build_dir(rc))


DRIVERS = [BlenderBuild]
