from bs4 import BeautifulSoup as bs
import subprocess
import os

MODULE_PATH = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(MODULE_PATH, "templates")
BORDER_COLOR = "blue"
THEME = "dark"
PYTHON_CMD = "python3"
JUPYTER_CMD = "jupyter"
CUTYCAPT_CMD = "cutycapt"
IMAGEMAGICK_CMD = "convert"
with open(os.path.join(MODULE_PATH, "..", ".encodings"), "r") as f:
    ENCODING = f.read().strip()

ps = lambda str_: str_.replace(" ", r"\ ")


def html_to_png_cmd(in_, out):
    if "wkhtmltoimage" in CUTYCAPT_CMD:
        return f"{CUTYCAPT_CMD} --javascript-delay 2000 {ps(in_)} {ps(out)}"
    else:
        return f"{CUTYCAPT_CMD} --url=file://{ps(in_)} --out={ps(out)} --delay=2000 --min-height=200"


imagemagick_cmd = lambda in_, out: (
    f"{IMAGEMAGICK_CMD} -bordercolor {BORDER_COLOR} -border 10 {ps(in_)} {ps(out)}"
)


def main(args):
    title = args.title
    html_file = "/home/lukas/Downloads/test.html"
    out_png = os.path.join(TEMPLATE_DIR, args.fname)

    empty_html = """
    <!DOCTYPE html>
    <html>
    <body>
    </body>
    </html>
    """

    soup = bs(empty_html)
    new_tag = soup.new_tag(
        "h1", style="text-align:center;color:#ffffff;background-color:#000000;"
    )
    new_tag.string = title
    soup.insert(0, new_tag)

    soup.body.append(soup.new_tag("style", type="text/css"))
    soup.body.style.append("body {background-color:#181818;}")

    with open(html_file, "w+", encoding=ENCODING) as file:
        file.write(str(soup))

    cmds = [
        html_to_png_cmd(html_file, out_png),
        imagemagick_cmd(out_png, out_png),
    ]

    for cmd in cmds:
        subprocess.run(
            cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    os.system(f"xdg-open {out_png}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()

    parser.add_argument("fname", type=str, help="template_name.png")
    parser.add_argument("title", type=str, help="displayed text")
    args = parser.parse_args()

    main(args)
