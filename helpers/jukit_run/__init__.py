from .jukit_run import StringIOWrapper, JukitRun

def load_ipython_extension(ipython):
    magics = JukitRun(ipython)
    ipython.register_magics(magics)

__all__ = ['StringIOWrapper', 'JukitRun']
