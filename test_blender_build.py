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


def test_binding_gpu_overrides_the_preset(drivers):
    r = Runner(pretend=True)
    # a binding-level `gpu:` still wins over the via's preset
    assert drivers['blender-cuda'](r)._gpu_backends(_rc(gpu=['hip'])) == ['hip']
    # aliases still expand (nvidia -> cuda+optix)
    assert drivers['blender-build'](r)._gpu_backends(_rc(gpu=['nvidia'])) == ['cuda', 'optix']
