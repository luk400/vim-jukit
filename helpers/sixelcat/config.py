_config = {'max_width_factor': 1.8}

def configure(max_width_factor=None):
    if max_width_factor is not None:
        _config['max_width_factor'] = max_width_factor
