import sys, re


def display_style_0(cmd, shell):
    sys.stdout.write(shell.pycolorize(cmd))
    if not cmd.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.write("## -- End pasted text --\n")


def display_style_1(cmd, shell):
    col_in = "\u001b[32m"
    sys.stdout.write("\n" + col_in + "--------- In ---------\n")
    cmd = re.sub(r"^\s+", "", cmd)
    cmd = col_in + shell.pycolorize(cmd)
    cmd = re.sub(r"\s+$", "", cmd)
    cmd = re.sub(r"\n", col_in + "\n", cmd)
    sys.stdout.write(cmd)
    sys.stdout.write(col_in + "\n----------------------\u001b[0m\n")


def display_style_2(cmd, shell):
    col_in = "\u001b[32m"
    sys.stdout.write("\n" + col_in + "╭───────── In ─────────•••\n")
    cmd = re.sub(r"^\s+", "", cmd)
    cmd = col_in + "│ " + shell.pycolorize(cmd)
    cmd = re.sub(r"\s+$", "", cmd)
    cmd = re.sub(r"\n", col_in + "\n│ ", cmd)
    sys.stdout.write(cmd)
    sys.stdout.write(col_in + "\n╰──────────────────────•••\u001b[0m\n")


def display_style_3(cmd, shell):
    col_in = "\u001b[32m"
    sys.stdout.write("\n" + col_in + "───────── In ─────────•••\n")
    cmd = re.sub(r"^\s+", "", cmd)
    cmd = col_in + shell.pycolorize(cmd)
    cmd = re.sub(r"\s+$", "", cmd)
    cmd = re.sub(r"\n", col_in + "\n", cmd)
    sys.stdout.write(cmd)
    sys.stdout.write(col_in + "\n──────────────────────•••\u001b[0m\n")


def display_style_4(cmd, shell):
    col_in = "\u001b[32m"
    sys.stdout.write("\n" + col_in + "╭───────── In ─────────•••\n")
    cmd = re.sub(r"^\s+", "", cmd)
    cmd = col_in + "│ " + shell.pycolorize(cmd)
    cmd = re.sub(r"\s+$", "", cmd)
    cmd = re.sub(r"\n", col_in + "\n│ ", cmd)
    sys.stdout.write(cmd)
    sys.stdout.write(col_in + "\n╰──────────────────────•••\u001b[0m\n")

    col_out = "\u001b[35m"
    sys.stdout.write(col_out + "╭───────── Out ────────•••\u001b[0m\n")
    sys.stdout.write(col_out + "▼\u001b[0m\n")


display_functions = {
    0: display_style_0,
    1: display_style_1,
    2: display_style_2,
    3: display_style_3,
    4: display_style_4,
}
