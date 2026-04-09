# Module-wide config for the sixelcat matplotlib backend.
#
# ``max_width_factor`` is the fraction of the pane the image fills when
# scaled. 1.0 = fit exactly, < 1.0 = margin, > 1.0 = cut off (allowed).
# See cat.py::sixelcat for the scaling math.
#
# ``info_file`` is the absolute path to ``.jukit_info.json``. When set,
# cat.py re-reads ``sixelcat_width_factor`` from this file on every
# render so that runtime updates from vim take effect without
# restarting IPython. Seeded by ``%jukit_init`` from jukit_run.py.
_config = {
    'max_width_factor': 1.0,
    'info_file': None,
}


def configure(max_width_factor=None, info_file=None):
    if max_width_factor is not None:
        _config['max_width_factor'] = max_width_factor
    if info_file is not None:
        _config['info_file'] = info_file
