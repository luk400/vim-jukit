import site
import os
import sys

def get_path():
    all_paths = site.getsitepackages()
    path = None
    while (not path and len(all_paths)>1):
        print("\n".join(f"{i}: " + el for i, el in enumerate(all_paths)))
        idx = input(("Multiple Paths found, please choose one of the above by the given " 
                "number to import (or create if non-existent) the backend module:\n"))
        try:
            idx = int(idx)
        except ValueError:
            print("Choose a valid path by specifying the given index!")
        if (type(idx)!=int) and ((idx < 0) or (idx >= len(all_paths))):
            print("Choose a valid path by specifying the given index!")
        else:
            path = all_paths[idx]
    
    if len(all_paths)==1:
        path = all_paths[0]
    
    return path

if __name__=="__main__":
    import os
    import sys
    plugin_path = str(sys.argv[1])
    
    backend_dir = plugin_path + '/helpers/matplotlib-backend-kitty'
    path = get_path() + '/'
    if not "matplotlib-backend-kitty" in os.listdir(path):
        os.system(f"cp -r {backend_dir} {path}")
        print(f"\nCreated matplotlib-backend-kitty module in {path}\n")
    else:
        print(f"\nUsing matplotlib-backend-kitty module found in {path}\n")

