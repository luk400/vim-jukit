import site
import os
import sys

if __name__ == "__main__":
    plugin_path = str(sys.argv[1])
    backend_dir = plugin_path + "/helpers/matplotlib-backend-kitty"

    paths = [path + "/" for path in site.getsitepackages()]
    all_modules = [os.listdir(path) for path in paths]
    all_modules = [el for sublist in all_modules for el in sublist]  # flatten

    if not "matplotlib-backend-kitty" in all_modules:
        os.system(f"cp -r {backend_dir} {paths[0]}")
        print(f"\nCreated matplotlib-backend-kitty module in {paths[0]}\n")
    else:
        print(f"\nUsing matplotlib-backend-kitty module found in {paths}\n")
