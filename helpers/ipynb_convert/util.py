import json, sys, os, random, string, re
from typing import Union


def get_nb_and_language(nb, lang_dict):
    assert nb["nbformat"] > 3, (
        "Notebook format not correct! Use "
        "`jupyter nbconvert --to notebook --nbformat 4 <FILENAME>` "
        "to convert it to the correct format!"
    )

    kernel_spec = nb["metadata"].get("kernelspec")
    if kernel_spec is None:
        language = "python"
    else:
        language = kernel_spec.get("language")

    if language is None:
        match_vals = [fuzzy_match(kernel_spec["name"], key) for key in lang_dict.keys()]
        idx_max = max(range(len(match_vals)), key=match_vals.__getitem__)
        if match_vals[idx_max] > 0.6:
            language = list(lang_dict.keys())[idx_max]
        else:
            raise ValueError("Could not find matching language.")
    else:
        assert (
            lang_dict.get(language) is not None
        ), f"Language `{language}` not supported"

    return language, nb


def create_output_history(outhist_file, nb=None):
    if nb is None:
        with open(outhist_file, "w+") as f:
            json.dump({}, f)

        return

    out_hist, cell_ids = {}, []
    for cell in nb["cells"]:
        cell_id = cell["metadata"].get("jukit_cell_id")
        if cell_id is None:
            cell_id = generate_cell_ids(1)[0]
        cell_ids.append(cell_id)
        if cell["cell_type"] == "code" and cell["execution_count"] is not None:
            out_hist[cell_id] = cell["outputs"]

    with open(outhist_file, "w+") as f:
        json.dump(out_hist, f)

    return cell_ids


def delete_cell_output(outhist_file, cell_id=None):
    if cell_id is None:
        with open(outhist_file, "w+") as f:
            json.dump({}, f)

    outhist = get_json(outhist_file)

    if cell_id not in outhist.keys():
        return

    outhist.pop(cell_id)
    with open(outhist_file, "w+") as f:
        json.dump(outhist, f)


def copy_output(from_id: str, to_ids: Union[str, list], outhist_file: str):
    if isinstance(to_ids, str):
        to_ids = [to_ids]

    outhist = get_json(outhist_file)
    from_out = outhist.get(from_id)

    for to_id in to_ids:
        outhist[to_id] = from_out

    if not os.path.isdir(os.path.split(outhist_file)[0]):
        return

    with open(outhist_file, "w+") as f:
        json.dump(outhist, f)


def clear_obsolete_output(current_ids, outhist_file):
    outhist = get_json(outhist_file)

    keys_deleted = False
    for key in tuple(outhist.keys()):
        if key not in current_ids:
            outhist.pop(key)
            keys_deleted = True

    if not keys_deleted:
        return

    with open(outhist_file, "w+") as f:
        json.dump(outhist, f)


def merge_outputs(outhist_file, cell_above, cell_below, new_id):
    out_hist = get_json(outhist_file)

    out_above = out_hist.get(cell_above)
    out_below = out_hist.get(cell_below)

    if out_above is None and out_below is None:
        return

    if out_above is None:
        out_above = []

    if out_below is None:
        out_below = []

    out_combined = out_above + out_below
    out_hist[new_id] = out_combined

    with open(outhist_file, "w") as f:
        out_hist = json.dump(out_hist, f)


def add_to_output_history(out_str, cell_id, outhist_file, exec_result):
    if not os.path.isfile(outhist_file):
        create_output_history(outhist_file)

    out_jsons = []
    num_plots = min(
        len(re.findall(r"<-- JUKIT_PLOT_PLACEHOLDER -->", out_str)),
        len(sys.stdout.jukit_plots),
    )
    if hasattr(sys.stdout, "jukit_plots") and num_plots:
        out_split = out_str.split("<-- JUKIT_PLOT_PLACEHOLDER -->")
        i = 0
        for i, plot in enumerate(sys.stdout.jukit_plots):
            if len(out_split[i]):
                text_json = {
                    "output_type": "stream",
                    "name": "stdout",
                    "text": out_split[i],
                }
                out_jsons.extend([text_json, plot])
            else:
                out_jsons.append(plot)

        if len(out_split[i + 1]):
            text_json = {
                "output_type": "stream",
                "name": "stdout",
                "text": out_split[i + 1],
            }
            out_jsons.append(text_json)
    elif len(out_str):
        out_jsons = [{"output_type": "stream", "name": "stdout", "text": out_str}]

    if exec_result is not None:
        exec_json = {
            "output_type": "execute_result",
            "execution_count": exec_result["count"],
            "data": {"text/plain": exec_result["result"]},
            "metadata": {},
        }
        out_jsons.append(exec_json)

    with open(outhist_file, "r") as f:
        out_hist = json.load(f)

    out_hist[cell_id] = out_jsons

    with open(outhist_file, "w") as f:
        out_hist = json.dump(out_hist, f)


def generate_cell_ids(num):
    ids = []
    len_ = 10
    alphabet = string.ascii_uppercase + string.ascii_lowercase + string.digits

    ids_flattened = random.choices(alphabet, k=len_ * num)
    ids = ["".join(ids_flattened[i * len_ : (i + 1) * len_]) for i in range(num)]

    # prevent collusion (not really necessary, VERY unlikely)
    if len(set(ids)) != len(ids):
        ids = generate_cell_ids(num)

    return ids


def get_json(file):
    if os.path.isfile(file):
        with open(file, "r") as f:
            content = json.load(f)
        return content
    else:
        return {}


def fuzzy_match(s, t):
    """levenshtein_ratio_and_distance:
    CREDIT: https://www.datacamp.com/community/tutorials/fuzzy-string-python
    """
    if not len(s) or not len(t):
        return 0

    rows = len(s) + 1
    cols = len(t) + 1
    distance = [[0 for _ in range(cols)] for _ in range(rows)]

    for i in range(1, rows):
        for k in range(1, cols):
            distance[i][0] = i
            distance[0][k] = k

    for col in range(1, cols):
        for row in range(1, rows):
            if s[row - 1] == t[col - 1]:
                cost = 0
            else:
                cost = 2
            distance[row][col] = min(
                distance[row - 1][col] + 1,
                distance[row][col - 1] + 1,
                distance[row - 1][col - 1] + cost,
            )
    Ratio = ((len(s) + len(t)) - distance[row][col]) / (len(s) + len(t))
    return Ratio
