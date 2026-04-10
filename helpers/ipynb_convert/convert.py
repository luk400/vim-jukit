import argparse, json, os, re


HEADER = "|%%--%%|"
MD_MARK = "°°°"
MODULE_PATH = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(MODULE_PATH, "..", ".encodings"), "r") as f:
    ENCODING = f.read().strip()


def nb_to_script(nb, cell_ids=None, language="python"):
    md_start = lang[language]["multiline_start"] + MD_MARK
    md_end = MD_MARK + lang[language]["multiline_end"]
    cchar = lang[language]["cchar"]

    result = []
    cells = nb["cells"]

    if cell_ids is None:
        cell_ids = generate_cell_ids(len(cells))

    for i, cell in enumerate(cells):
        cell_type = cell["cell_type"]
        cell_text = "".join(cell["source"])

        if cell_type == "markdown":
            cell_content = md_start + f"\n{cell_text}\n" + md_end
        elif cell_type == "code":
            cell_content = f"\n{cell_text}\n"
        elif cell_type == "raw":
            cell_content = (
                md_start + f"\n**RAW CELLS NOT SUPPORTED BY JUKIT; CONVERTED "
                "TO MARKDOWN**; original raw-cell content:\n"
                f"```\n{cell_text}\n```\n" + md_end
            )
        else:
            raise ValueError("Invalid cell type encountered!")

        if i > 0:
            result.append(f"{cchar} {HEADER} <{cell_ids[i-1]}|{cell_ids[i]}>")

        result.append(cell_content)

    return "\n".join(result)


def script_to_nb(py_str, out_hist, language="python"):
    md_start = lang[language]["multiline_start"] + MD_MARK
    md_end = MD_MARK + lang[language]["multiline_end"]

    py_str = re.sub(r"^\s+", "", py_str)
    py_str = re.sub(r"\s+$", "", py_str)

    cells = []
    chunks = re.split(rf".*{re.escape(HEADER)}.*", py_str)
    if len(chunks) == 1:
        cell_ids = ["NONE"]
    else:
        cell_ids1 = re.findall(rf"{re.escape(HEADER)} <(.*)\|.*>", py_str)
        cell_ids2 = re.findall(rf"{re.escape(HEADER)} <.*\|(.*)>", py_str)
        cell_ids = [cell_ids1[0]] + cell_ids2

    ex_count = 0
    for chunk, id_ in zip(chunks, cell_ids):
        chunk = re.sub(r"^\n+", "", chunk)
        chunk = re.sub(r"\n+$", "", chunk)
        if chunk.startswith(md_start):
            chunk = chunk.strip("".join(set(md_start + md_end)) + "\n")
            cell_type = "markdown"
        else:
            cell_type = "code"

        cell = {
            "cell_type": cell_type,
            "metadata": {"jukit_cell_id": id_},
            "source": chunk.splitlines(True),
        }

        if cell_type == "code":
            outputs = out_hist.get(id_)
            if outputs is not None and len(outputs):
                ex_count += 1
                if "execution_count" in outputs[-1].keys():
                    outputs[-1]["execution_count"] = ex_count
                ex = ex_count
            else:
                outputs = []
                ex = None

            cell.update({"outputs": outputs, "execution_count": ex})

        cells.append(cell)

    nb = {
        "cells": cells,
        "metadata": {
            "anaconda-cloud": {},
            "kernelspec": {
                "display_name": language,
                "language": language,
                "name": lang[language]["kernel_name"],
            },
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }

    return nb


def convert(in_file, language, jukit_copy, create=True, session="",
            no_outputs=False, session_save=""):
    """Convert between .py (jukit-formatted) and .ipynb.

    The session/session_save/no_outputs args choose which per-session
    outhist file (added 2026-04 with the load-previous picker) drives
    the conversion:

      .py -> .ipynb (this direction): `session` selects which saved
        outhist to embed into the notebook. Empty string falls back to
        the legacy <basename>_outhist.json so users with pre-session
        installs keep working. `no_outputs=True` skips the lookup
        entirely and produces a clean notebook.

      .ipynb -> .py (with jukit_copy): `session_save` is the session
        name under which the notebook's per-cell outputs are stored
        in .jukit/. Empty string defaults to the legacy filename.
    """
    dir_, fname = os.path.split(in_file)
    name, in_ext = os.path.splitext(fname)
    jukit_dir = os.path.join(dir_, ".jukit")

    if in_ext != ".ipynb" and jukit_copy:
        raise ValueError("`jukit_copy` can only be `True` when converting ipynb to py")

    if in_ext == ".ipynb":
        nb = get_json(in_file)
        language, nb = get_nb_and_language(nb, lang)
        out_file = os.path.join(dir_, f"{name}.{lang[language]['ext']}")

        if jukit_copy:
            if not os.path.isdir(jukit_dir):
                os.mkdir(jukit_dir)
            # session_save names the per-session outhist file the
            # notebook outputs land in. Empty -> legacy filename.
            outhist_file = session_outhist_filename(jukit_dir, name, session_save)
            cell_ids = create_output_history(outhist_file, nb)
        else:
            cell_ids = None

        py_str = nb_to_script(nb, cell_ids, language)

        if create:
            with open(out_file, "w+", encoding=ENCODING) as f:
                f.write(py_str)

        return out_file
    else:
        out_file = os.path.join(dir_, name + ".ipynb")

        with open(in_file, "r", encoding=ENCODING) as f:
            py_str = f.read()

        if no_outputs:
            out_hist = {}
        else:
            # session selects which per-session outhist to embed.
            # Empty -> legacy filename, preserving the pre-session
            # behavior for old installs.
            outhist_file = session_outhist_filename(jukit_dir, name, session)
            if os.path.isfile(outhist_file):
                with open(outhist_file, "r", encoding=ENCODING) as f:
                    out_hist = json.load(f)
            else:
                out_hist = {}

        nb = script_to_nb(py_str, out_hist, language)

        if create:
            with open(out_file, "w+", encoding=ENCODING) as f:
                json.dump(nb, f, indent=2)

        return out_file


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fin", type=str, help="input file to convert")
    parser.add_argument("--lang", default="python", type=str, help="language")
    parser.add_argument(
        "--jukit-copy",
        action="store_true",
        help=(
            "Whether to create copy of given ipynb file outputs in .jukit/ folder."
            " Only used when converting ipynb to py."
        ),
    )
    parser.add_argument(
        "--session",
        type=str,
        default="",
        help=(
            "When converting .py->.ipynb: name of the saved session "
            "whose outhist file should be embedded as cell outputs. "
            "Empty -> legacy <basename>_outhist.json. Ignored if "
            "--no-outputs is given."
        ),
    )
    parser.add_argument(
        "--session-save",
        type=str,
        default="",
        help=(
            "When converting .ipynb->.py with --jukit-copy: name of "
            "the session under which the notebook's outputs are saved. "
            "Empty -> legacy <basename>_outhist.json."
        ),
    )
    parser.add_argument(
        "--no-outputs",
        action="store_true",
        help=(
            "When converting .py->.ipynb: skip reading any outhist "
            "file and produce a notebook with no cell outputs."
        ),
    )
    args = parser.parse_args()

    print(convert(args.fin, args.lang, args.jukit_copy,
                  session=args.session, no_outputs=args.no_outputs,
                  session_save=args.session_save))


if __name__ == "__main__":
    from util import *
    from languages import languages as lang

    main()
else:
    from .util import *
    from .languages import languages as lang
