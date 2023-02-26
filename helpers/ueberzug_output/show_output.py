from contextlib import suppress
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont, UnidentifiedImageError
from bs4 import BeautifulSoup as bs
import numpy as np
import time
import os
import json
import array, fcntl, termios
import subprocess
import shutil

MODULE_PATH = os.path.dirname(os.path.abspath(__file__))
HTMLPREP_SCRIPT = os.path.join(MODULE_PATH, "prepare_html.py")

BORDER_COLOR = "blue"
THEME = "dark"
PYTHON_CMD = "python3"
JUPYTER_CMD = "jupyter"
CUTYCAPT_CMD = "cutycapt"
IMAGEMAGICK_CMD = "convert"

ps = lambda str_: str_.replace(" ", r"\ ")

nbconvert_cmd = lambda in_, out: (
    f"{JUPYTER_CMD} nbconvert {ps(in_)} --output {ps(out)} --log-level "
    f"ERROR --to html --theme {THEME}"
)

def html_to_png_cmd(in_, out):
    if "wkhtmltoimage" in CUTYCAPT_CMD:
        return f"{CUTYCAPT_CMD} --javascript-delay 2000 {ps(in_)} {ps(out)}"
    else:
        return f"{CUTYCAPT_CMD} --url=file://{ps(in_)} --out={ps(out)} --delay=2000 --min-height=200"

imagemagick_cmd = lambda in_, out: (
    f"{IMAGEMAGICK_CMD} -bordercolor {BORDER_COLOR} -border 10 {ps(in_)} {ps(out)}"
)

preparehtml_cmd = (
    lambda in_, none_out: f"{PYTHON_CMD} {HTMLPREP_SCRIPT} {ps(in_)} {int(none_out)}"
)


def _update_template_png(img_name, new_template_type):
    shutil.copyfile(
        os.path.join(MODULE_PATH, "templates", f"{new_template_type}.png"), img_name
    )


def _write_loading_on_img(img_path):
    img = Image.open(img_path)
    img = img.convert("RGB")
    img = img.resize((img.size[0] * 2, img.size[1] * 2))
    img = img.convert("RGBA")

    draw = ImageDraw.Draw(img)

    with suppress(Exception):
        font_path = os.path.join(MODULE_PATH, "arial.ttf")
        font = ImageFont.truetype(font_path, size = max(img.size[0] // 30, 1))
        text = "reloading..."
        text_w, text_h = draw.textsize(text, font=font)
        draw.text(
            (img.size[0] - text_w - 30, img.size[1] - text_h - 30),
            text,
            font=font,
            fill=(255, 0, 0, 255),
        )

        img.save(img_path)


def png_success_check(
    png_path,
    html_path,
    jukit_path,
    cell_id,
    output_json=None,
    ipynb_nb=None,
    open_html=False,
):
    try:
        im = Image.open(png_path)
    except Image.DecompressionBombError:
        im = None

    if im is not None and not (
        im.mode == "RGBA" and len(np.unique(np.array(im.split()[-1]))) == 2
    ):
        is_in_trunc, jukit_info_content = _check_if_cell_truncated(
            cell_id, html_path, jukit_path, action="remove"
        )
        if is_in_trunc:
            info_json = os.path.join(jukit_path, ".jukit_info.json")
            with open(info_json, "w+") as f:
                json.dump(jukit_info_content, f, indent=2)

        return True

    if not os.path.isfile(html_path) and output_json is not None:
        html_path, _ = create_png(cell_id, output_json, only_html=True)
        if html_path is None:
            is_in_trunc, jukit_info_content = _check_if_cell_truncated(
                cell_id, html_path, jukit_path, action="remove"
            )
            if is_in_trunc:
                info_json = os.path.join(jukit_path, ".jukit_info.json")
                with open(info_json, "w+") as f:
                    json.dump(jukit_info_content, f, indent=2)

            return True

    elif not os.path.isfile(html_path) and ipynb_nb is not None:
        html_path, _ = create_markdown_img(cell_id, ipynb_nb, only_html=True)

    new_html_path = os.path.join(
        os.path.split(png_path)[0], os.path.split(html_path)[1]
    )
    shutil.move(html_path, new_html_path)
    html_path = new_html_path

    if open_html:
        html_viewer = _get_html_viewer(jukit_path)
        cmd = f"{html_viewer} {html_path}"
        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    html_trunc_path = os.path.splitext(html_path)[0] + "_trunc.html"
    try_props = [2, 5, 10, 30, 50, 100, 1000]
    for i, trunc_prop in enumerate(try_props):
        _update_template_png(png_path.replace('_temp', ''), f"truncated_img_{trunc_prop}")

        with open(html_path, "r") as f:
            soup = bs(f.read(), "html.parser")

        num_descendants = len(list(soup.body.descendants))

        # TODO: this is lazy and for sure can be done much more efficiently
        for i, el in enumerate(list(soup.body.descendants)):
            if i < num_descendants // trunc_prop:
                continue
            try:
                el.decompose()
            except: # non decomposable descendant
                continue

        new_tag = soup.new_tag(
            "h1", style=f"text-align:center;color:#ff0000;background-color:#000000;"
        )
        new_tag.string = "..."
        soup.append(new_tag)

        new_tag = soup.new_tag(
            "h3", style=f"text-align:center;color:#ff0000;background-color:#000000;"
        )
        new_tag.string = "[VIM-JUKIT] TRUNCATED: SAVED OUTPUTS TOO LARGE FOR IMAGE "
        soup.append(new_tag)

        new_tag = soup.new_tag(
            "h3", style=f"text-align:center;color:#ff0000;background-color:#000000;"
        )
        new_tag.string = "See the following html file for full output:"
        soup.append(new_tag)

        new_tag = soup.new_tag(
            "h3",
            style=f"word-wrap:break-word;text-align:center;color:#ff0000;background-color:#000000;",
        )
        new_tag.string = f"{html_path}"
        soup.append(new_tag)

        with open(html_trunc_path, "w+") as f:
            f.write(str(soup))

        cmds = [
                html_to_png_cmd(html_trunc_path, png_path),
                imagemagick_cmd(png_path, png_path),
        ]

        templates = [
                f"truncated_img_{trunc_prop}_html_to_png",
                f"truncated_img_{trunc_prop}_add_border",
        ]

        for cmd, template in zip(cmds, templates):
            _update_template_png(png_path.replace('_temp', ''), template)
            subprocess.run(
                cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

        os.remove(html_trunc_path)

        try:
            im = Image.open(png_path)
        except Image.DecompressionBombError:
            im = None

        if im is not None and not (
            im.mode == "RGBA" and len(np.unique(np.array(im.split()[-1]))) == 2
        ):
            break

    is_in_trunc, jukit_info_content = _check_if_cell_truncated(
        cell_id, html_path, jukit_path, action="add"
    )
    if not is_in_trunc:
        info_json = os.path.join(jukit_path, ".jukit_info.json")
        with open(info_json, "w+") as f:
            json.dump(jukit_info_content, f, indent=2)

    return False


def _check_if_cell_truncated(cell_id, html_path, jukit_path, action=None):
    info_json = os.path.join(jukit_path, ".jukit_info.json")
    with open(info_json, "r") as f:
        content = json.load(f)

    if "truncated_files" in content.keys():
        is_in = cell_id in content["truncated_files"].keys()

        if action == "add":
            content["truncated_files"][cell_id] = html_path
        elif action == "remove":
            content["truncated_files"].pop(cell_id, None)

        return is_in, content
    else:
        if action == "add":
            content["truncated_files"] = {cell_id: html_path}

        return False, content


def _get_html_viewer(jukit_path):
    info_json = os.path.join(jukit_path, ".jukit_info.json")
    with open(info_json, "r") as f:
        content = json.load(f)

    return content["display_param"]["html_viewer"]


def create_markdown_img(cell_id, temp_nb, only_html=False, first_creation=False):
    dir_, fname = os.path.split(temp_nb)
    fname_noext = os.path.splitext(fname)[0]
    temp_html = os.path.join(dir_, f".temp_{fname_noext}_{cell_id}.html")
    img_dir = os.path.join(dir_, f"{fname_noext}_img")

    if only_html:
        cmd = nbconvert_cmd(temp_nb, temp_html)
        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        os.remove(temp_nb)
        return temp_html, dir_

    if not os.path.isdir(img_dir):
        os.mkdir(img_dir)

    out_png = os.path.join(img_dir, f"{fname_noext}_{cell_id}.png")
    out_png_temp = os.path.join(img_dir, f"{fname_noext}_{cell_id}_temp.png")

    cmds = [
            nbconvert_cmd(temp_nb, temp_html),
            html_to_png_cmd(temp_html, out_png_temp),
            imagemagick_cmd(out_png_temp, out_png_temp),
    ]

    templates = [
            "nb_to_html",
            "html_to_png",
            "add_border",
    ]

    for cmd, template in zip(cmds, templates):
        if first_creation:
            _update_template_png(out_png, template)
        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    png_success_check(out_png_temp, temp_html, dir_, cell_id, open_html=False)
    os.rename(out_png_temp, out_png)

    [os.remove(f) for f in [temp_html, temp_nb] if os.path.isfile(f)]

    return out_png, dir_


def create_png(
    cell_id, outjson_path, use_cached=False, ueberzug_opts=None, only_html=False
):
    if ueberzug_opts is not None:
        # overwrite global variables
        global BORDER_COLOR, THEME, PYTHON_CMD, JUPYTER_CMD, CUTYCAPT_CMD, IMAGEMAGICK_CMD
        (
            BORDER_COLOR,
            THEME,
            PYTHON_CMD,
            JUPYTER_CMD,
            CUTYCAPT_CMD,
            IMAGEMAGICK_CMD,
        ) = ueberzug_opts

    dir_, fname = os.path.split(outjson_path)
    fname_noext = os.path.splitext(fname)[0]
    temp_nb = os.path.join(dir_, f".temp_{fname_noext}_{cell_id}.ipynb")
    temp_html = os.path.join(dir_, f".temp_{fname_noext}_{cell_id}.html")
    img_dir = os.path.join(dir_, f"{fname_noext}_img")

    if only_html:
        tempjson, none_out = _convert_output_to_ipynb(outjson_path, cell_id)
        if none_out:
            return None, dir_

        with open(temp_nb, "w+") as f:
            json.dump(tempjson, f, indent=2)

        cmd = "; ".join(
            [
                nbconvert_cmd(temp_nb, temp_html),
                preparehtml_cmd(temp_html, none_out),
            ]
        )

        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        os.remove(temp_nb)

        return temp_html, dir_

    if not os.path.isdir(img_dir):
        os.mkdir(img_dir)

    out_png = os.path.join(img_dir, f"{fname_noext}_{cell_id}.png")
    out_png_temp = os.path.join(img_dir, f"{fname_noext}_{cell_id}_temp.png")

    if use_cached and os.path.isfile(out_png):
        return out_png

    tempjson, none_out = _convert_output_to_ipynb(outjson_path, cell_id)

    if none_out:
        _update_template_png(out_png, "no_output")
        return out_png

    with open(temp_nb, "w+") as f:
        json.dump(tempjson, f, indent=2)

    cmds = [
            nbconvert_cmd(temp_nb, temp_html),
            preparehtml_cmd(temp_html, none_out),
            html_to_png_cmd(temp_html, out_png_temp),
            imagemagick_cmd(out_png_temp, out_png_temp),
    ]

    templates = [
            "nb_to_html",
            "prepare_html",
            "html_to_png",
            "add_border",
    ]

    for cmd, template in zip(cmds, templates):
        _update_template_png(out_png, template)
        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    png_success_check(out_png_temp, temp_html, dir_, cell_id, outjson_path, open_html=False)
    os.rename(out_png_temp, out_png)

    [os.remove(f) for f in [temp_html, temp_nb] if os.path.isfile(f)]

    return out_png


def _display_loop(
    img, jukit_path, scaler_arg=None, cell_id=None, output_json=None, ipynb_nb=None
):
    display = True
    canvas_created = False

    timestamp_prev = -1
    with ueberzug.Canvas() as canvas:
        while display:
            try:
                (
                    columns,
                    lines,
                    display,
                    scroll_pos,
                    width_prop,
                    height_prop,
                    xpos_prop,
                    ypos_prop,
                    timestamp,
                    term_hw_ratio,
                ) = _get_display_parameters(jukit_path)
            except:
                continue

            if term_hw_ratio == -1:
                term_hw_ratio = _get_termcell_h_to_w()

            width = int(columns * width_prop)
            height = int(lines * height_prop)
            xpos, ypos = int(xpos_prop * columns), int(ypos_prop * lines)

            try:
                w, h = Image.open(img).size
            except Image.DecompressionBombError:
                html_file = f"{os.path.splitext(img)[0]}.html"
                png_success_check(
                    img, html_file, jukit_path, cell_id, output_json, ipynb_nb
                )
                w, h = 600, 600
            except UnidentifiedImageError:
                continue

            ymin = (height / width) / (h / w) * 0.95

            if (h / w < height * term_hw_ratio / width) and scaler_arg is None:
                scaler = ueberzug.ScalerOption.FIT_CONTAIN
            elif scaler_arg is None:
                scaler = ueberzug.ScalerOption.FORCED_COVER
            else:
                scaler = scaler_arg

            if not canvas_created:
                placement = canvas.create_placement(
                    "placement",
                    x=xpos,
                    y=ypos,
                    width=width,
                    height=height,
                    scaler=scaler.value,
                    scaling_position_y=ymin,
                )
                placement.path = img
                placement.visibility = ueberzug.Visibility.VISIBLE
                canvas_created = True

            placement.scaler = scaler.value
            placement.width = width
            placement.height = height
            placement.x = xpos
            placement.y = ypos

            if timestamp_prev != timestamp and timestamp_prev != -1:
                newpos = placement.scaling_position_y + scroll_pos * (
                    0.3 / max(h / w, 2)
                )
                placement.scaling_position_y = max(min(newpos, 1 - ymin), ymin)

            timestamp_prev = timestamp
            time.sleep(0.1)


def show_image(img, jukit_path, scaler, cell_id=None, output_json=None, ipynb_nb=None):
    scaler = getattr(ueberzug.ScalerOption, scaler.upper(), None)
    _display_loop(img, jukit_path, scaler, cell_id, output_json, ipynb_nb)


def show_output(cell_id, output_json, use_cached=True):
    dir_, fname = os.path.split(output_json)
    fname_noext = os.path.splitext(fname)[0]
    img_dir = os.path.join(dir_, f"{fname_noext}_img")
    out_png = os.path.join(img_dir, f"{fname_noext}_{cell_id}.png")

    if not os.path.isdir(img_dir):
        os.mkdir(img_dir)

    if not os.path.isfile(out_png) or not use_cached:
        p = Process(target=create_png, args=(cell_id, output_json, False))
        p.start()
        _update_template_png(out_png, "loading_template")
    else:
        p = Process(target=create_png, args=(cell_id, output_json, use_cached))
        p.start()

    _display_loop(out_png, dir_, cell_id=cell_id, output_json=output_json)


def show_markdown(cell_id, ipynb_file, use_cached=True):
    jukit_path, fname = os.path.split(ipynb_file)
    fname_noext = os.path.splitext(fname)[0]
    img_dir = os.path.join(jukit_path, f"{fname_noext}_img")
    if not os.path.isdir(img_dir):
        os.mkdir(img_dir)

    img_path = os.path.join(img_dir, f"{fname_noext}_{cell_id}.png")
    template_condition = not os.path.isfile(img_path) or not use_cached
    if template_condition:
        _update_template_png(img_path, "loading_template")
    else:
        _write_loading_on_img(img_path)

    def keep_converting(template_condition):
        display = True
        while display:
            create_markdown_img(cell_id, ipynb_file, first_creation = template_condition)
            time.sleep(1)
            display = _get_display_parameters(jukit_path)[2]

            if template_condition:
                template_condition = False

    p = Process(target=keep_converting, args=(template_condition,))
    p.start()
    show_image(img_path, jukit_path, "default", cell_id, ipynb_nb=ipynb_file)
    p.terminate()

    if os.path.isfile(ipynb_file):
        dir_, fname = os.path.split(ipynb_file)
        fname_noext = os.path.splitext(fname)[0]
        temp_html = os.path.join(dir_, f".temp_{fname_noext}_{cell_id}.html")

        [os.remove(f) for f in [temp_html, ipynb_file] if os.path.isfile(f)]


def _get_termcell_h_to_w():
    try:
        buf = array.array("H", [0, 0, 0, 0])
        fcntl.ioctl(1, termios.TIOCGWINSZ, buf)
        return (buf[3] / buf[0]) / (buf[2] / buf[1])
    except:
        return 2.2


def _get_display_parameters(dir_):
    info_json = os.path.join(dir_, ".jukit_info.json")
    with open(info_json, "r") as f:
        content = json.load(f)

    params = content["display_param"]

    return (
        params["columns"],
        params["lines"],
        params["display"],
        params["scroll_pos"],
        params.get("width_prop", 0.5),
        params.get("height_prop", 1.0),
        params.get("xpos", 0),
        params.get("ypos", 0),
        params.get("timestamp", -1),
        params.get("term_hw_ratio", -1),
    )


def _convert_output_to_ipynb(output_json, cell_id):
    outputs = []

    none_out = True
    if os.path.isfile(output_json):
        with open(output_json, "r") as f:
            all_outputs = json.load(f)

        outputs = all_outputs.get(cell_id, None)
        if outputs is not None:
            none_out = False
        else:
            outputs = []

    language = "python3"
    kernel_name = "python3"

    cur_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    excount = 1
    for out in outputs:
        if out["output_type"] == "execute_result":
            excount = out["execution_count"]

    cell = {
        "cell_type": "code",
        "source": f"{cell_id}####{cur_time}",
        "metadata": {},
        "outputs": outputs,
        "execution_count": excount,
    }

    nb = {
        "cells": [cell],
        "metadata": {
            "anaconda-cloud": {},
            "kernelspec": {
                "display_name": language,
                "language": language,
                "name": kernel_name,
            },
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }

    return nb, none_out


def get_cli_args():
    """get arparse arguments"""
    parser = argparse.ArgumentParser(description="Jukit")
    subparsers = parser.add_subparsers(help="display types", dest="display_type")

    config_parser = subparsers.add_parser("config")
    md_parser = subparsers.add_parser("markdown")
    output_parser = subparsers.add_parser("output")

    # config settings
    config_parser.add_argument("img_path", type=str, help="path to image")
    config_parser.add_argument("jukit_path", type=str, help="path to .jukit directory")
    config_parser.add_argument(
        "--scaler",
        type=str,
        default="default",
        help="scaler option for ueberzug",
    )

    # markdown settings
    md_parser.add_argument("cell_id", type=str, help="cell id")
    md_parser.add_argument("ipynb_file", type=str, help="path to ipynb file")
    md_parser.add_argument(
        "--use_cached", type=int, default=1, help="store images / use stored images"
    )

    # output settings
    output_parser.add_argument("cell_id", type=str, help="cell id")
    output_parser.add_argument("output_json", type=str, help="path to output json")
    output_parser.add_argument(
        "--use_cached", type=int, default=1, help="store images / use stored images"
    )

    # common options
    parser.add_argument(
        "--python_cmd",
        type=str,
        help="python command / path to executable",
        default=PYTHON_CMD,
    )
    parser.add_argument(
        "--jupyter_cmd",
        type=str,
        help="jupyter command / path to executable",
        default=JUPYTER_CMD,
    )
    parser.add_argument(
        "--cutycapt_cmd",
        type=str,
        help="cutycapt command",
        default=CUTYCAPT_CMD,
    )
    parser.add_argument(
        "--imagemagick_cmd",
        type=str,
        help="imagemagic command",
        default=IMAGEMAGICK_CMD,
    )
    parser.add_argument(
        "--border_color",
        type=str,
        help="border color",
        default=BORDER_COLOR,
    )
    parser.add_argument(
        "--theme",
        type=str,
        help="theme",
        default=THEME,
    )

    return parser.parse_args()


if __name__ == "__main__":
    import argparse
    from multiprocessing import Process
    import ueberzug.lib.v0 as ueberzug

    args = get_cli_args()

    BORDER_COLOR = args.border_color
    THEME = args.theme
    PYTHON_CMD = args.python_cmd
    JUPYTER_CMD = args.jupyter_cmd
    CUTYCAPT_CMD = args.cutycapt_cmd
    IMAGEMAGICK_CMD = args.imagemagick_cmd

    if args.display_type == "config":
        show_image(args.img_path, args.jukit_path, args.scaler)
    elif args.display_type == "markdown":
        show_markdown(args.cell_id, args.ipynb_file, args.use_cached)
    elif args.display_type == "output":
        show_output(args.cell_id, args.output_json, args.use_cached)
