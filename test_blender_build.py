'''Unit tests for the blender-build driver — the pinnable GPU-flavor vias and their preset
backend sets (an actual Blender build is far too heavy for CI; this covers the driver logic
the recipe depends on). Run from this dir with configsys importable:  python -m pytest -q'''

from pathlib import Path

import pytest

from configsys import plugins
from configsys.componentObj import ResolvedComponent
from configsys.runner import Runner

PLUG = Path(__file__).resolve().parent


@pytest.fixture(scope='module')
def drivers():
    return {d.name: d for d in plugins._import_drivers(PLUG, plugins.read_manifest(PLUG))}


def _rc(**fields):
    return ResolvedComponent(key='blender-build\\blender', driver='blender-build', comp='blender',
                             fields=dict(fields), source=str(PLUG / 'blender.hu'))


def test_validation_error_is_a_fail_result_reason_in_output_not_command(drivers):
    # a pre-flight validation failure (here: an unknown gpu backend, which raises before any command
    # runs) must be a Result.fail -> the reason rides in `output`/stderr (so the CLI, the ! screen,
    # and the report all surface it), and `cmd` stays empty (no spurious Command block).
    d = drivers['blender-build'](Runner(pretend=True))
    res = d.install(_rc(dir='blender-git', target='both', ref='v4.3.2', gpu=['bogus-backend']))
    assert not res.ok and res.cmd == ''
    assert 'bogus-backend' in res.output          # the WHY is in output, not stuffed into the command


def test_manifest_and_variant_vias(drivers):
    m = plugins.read_manifest(PLUG)
    assert m['name'] == 'configsys-blender' and m['code'] == 'blender.py'
    # the pinnable install methods (one via per GPU flavor)
    assert set(drivers) == {'blender-build', 'blender-cuda', 'blender-optix',
                            'blender-hip', 'blender-oneapi'}


def test_each_via_presets_its_backend_set(drivers):
    r = Runner(pretend=True)
    assert drivers['blender-build'](r)._gpu_backends(_rc()) == []            # CPU
    assert drivers['blender-cuda'](r)._gpu_backends(_rc()) == ['cuda']
    assert drivers['blender-optix'](r)._gpu_backends(_rc()) == ['cuda', 'optix']
    assert drivers['blender-hip'](r)._gpu_backends(_rc()) == ['hip']
    assert drivers['blender-oneapi'](r)._gpu_backends(_rc()) == ['oneapi']


def test_variant_marker_discriminates_get_version(drivers):
    from configsys.runner import Result

    class Fake:
        '''A built blender whose marker records `via=<marked>`.'''
        def __init__(self, marked):
            self.marked = marked

        def run(self, cmd, **kw):
            if cmd.startswith('test -x'):
                return Result(cmd, 0)                        # editor present
            if cmd.startswith('cat ') and '.configsys-variant' in cmd:
                return Result(cmd, 0, stdout=f'via={self.marked}\ngpu=x\n')
            if 'describe' in cmd:
                return Result(cmd, 0, stdout='v4.3.2\n')
            return Result(cmd, 0)

    # marker says blender-optix -> ONLY that via reports installed
    for via, drv in drivers.items():
        v = drv(Fake('blender-optix')).get_version(_rc(dir='blender-git'))
        assert (v == 'v4.3.2') == (via == 'blender-optix'), (via, v)
    # marker says blender-build (base/CPU) -> only the base via claims it
    for via, drv in drivers.items():
        v = drv(Fake('blender-build')).get_version(_rc(dir='blender-git'))
        assert (v == 'v4.3.2') == (via == 'blender-build'), (via, v)


def test_probe_variant_from_kernels(drivers):
    from configsys.runner import Result

    class Kernels:
        '''No marker; a .optixir kernel is present under the build tree -> optix.'''
        def run(self, cmd, **kw):
            if cmd.startswith('test -x'):
                return Result(cmd, 0)
            if cmd.startswith('cat '):
                return Result(cmd, 1)                        # no marker
            if 'optixir' in cmd:
                return Result(cmd, 0)                        # find ... optixir -> found
            if 'find ' in cmd:
                return Result(cmd, 1)                        # other kernels absent
            return Result(cmd, 0)

    assert drivers['blender-build'](Kernels()).detected_variant(_rc(dir='blender-git')) == 'blender-optix'


def test_binding_gpu_overrides_the_preset(drivers):
    r = Runner(pretend=True)
    # a binding-level `gpu:` still wins over the via's preset
    assert drivers['blender-cuda'](r)._gpu_backends(_rc(gpu=['hip'])) == ['hip']
    # aliases still expand (nvidia -> cuda+optix)
    assert drivers['blender-build'](r)._gpu_backends(_rc(gpu=['nvidia'])) == ['cuda', 'optix']
