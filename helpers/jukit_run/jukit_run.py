from IPython.core.magic import line_magic, cell_magic, magics_class, magics_class
from IPython.core.magic_arguments import argument, magic_arguments, parse_argstring
from IPython.utils.capture import CapturedIO
from IPython.terminal.magics import TerminalMagics
from IPython.terminal.prompts import Prompts
from IPython.lib.pretty import pretty
from pygments.token import Token

import io, json, re, os, sys
from matplotlib import pyplot as plt
from typing import Optional, Any, TextIO

from ipynb_convert import add_to_output_history, HEADER
from . import util
from .input_styles import display_functions, display_style_2


def _fix_db(shell):
    hist_manager = shell.history_manager

    max_line = shell.execution_count
    sid = hist_manager.get_last_session_id()

    hist_manager.db.execute(
        f"DELETE FROM history WHERE line>={max_line} and session={sid}"
    )
    hist_manager.db.commit()


def monitor_excount_dec(func):
    def monitor_wrapper(self, *args):
        _fix_db(self.shell)
        self.execution_count = self.shell.execution_count
        func(self, *args)
        if self.execution_count != self.shell.execution_count:
            self.shell.execution_count = self.execution_count

    return monitor_wrapper


class monitor_execution_count(object):
    def __init__(self, shell):
        self.shell = shell

    def __enter__(self):
        self.execution_count = self.shell.execution_count
        _fix_db(self.shell)

    def __exit__(self, *_):
        if self.execution_count != self.shell.execution_count:
            self.shell.execution_count = self.execution_count


class MyPrompt(Prompts):
    def in_prompt_tokens(self):
        # NOTE: for some reason, simply returning [] or [(Token.Prompt, "")]
        # or even [(Token.Prompt, " ")] caused a segmentation fault for
        # (n)vimterm after specific resize operations of the terminal, while
        # using two or more spaces did not.
        return [(Token.Prompt, "  ")]


class JukitCaptureOutput(object):
    """context manager for capturing stdout/err"""

    def __init__(self, max_plots_size: int, cell_id: Optional[str] = None):
        self.shell = None
        self.cell_id = cell_id
        self.max_plots_size = max_plots_size

    def __enter__(self):
        self.sys_stdout = sys.stdout
        self.sys_stderr = sys.stderr

        stdout = stderr = outputs = None
        stdout = sys.stdout = StringIOWrapper(
            io.StringIO(), sys.stdout, self.max_plots_size, self.cell_id
        )
        stderr = sys.stderr = StringIOWrapper(
            io.StringIO(), sys.stderr, self.max_plots_size, self.cell_id
        )

        return CapturedIO(stdout, stderr, outputs)

    def __exit__(self, *_):
        sys.stdout = self.sys_stdout
        sys.stderr = self.sys_stderr


class StringIOWrapper(object):
    def __init__(
        self,
        obj: TextIO,
        sys_stdout: TextIO,
        max_plots_size: int,
        cell_id: Optional[str] = None,
    ):
        self._wrapped_stdout = obj
        self._sys_stdout = sys_stdout
        self.cell_id = cell_id
        self.jukit_plots = []
        self.jukit_plots_size = 0
        self.max_plots_size = max_plots_size

    def __getattr__(self, attr):
        if attr in self.__dict__:
            return getattr(self, attr)
        elif hasattr(self._wrapped_stdout, attr):
            return getattr(self._wrapped_stdout, attr)
        elif hasattr(self._sys_stdout, attr):
            return getattr(self._sys_stdout, attr)

    def write(self, text):
        self._wrapped_stdout.write(text)
        self._sys_stdout.write(text)

    def add_jukit_plot(self, b64):
        img_output = {
            "data": {"image/png": b64},
            "metadata": {},
            "output_type": "display_data",
        }
        self.jukit_plots.append(img_output)
        self.jukit_plots_size = sum(
            [sys.getsizeof(plot["data"]["image/png"]) for plot in self.jukit_plots]
        )


@magics_class
class JukitRun(TerminalMagics):
    def __init__(self, shell):
        super().__init__(shell)

    def _get_info_json_keys(self, *keys: str) -> list:
        info = util.catch_load_json(self.info_file)

        return [info.get(key) for key in keys]

    def _write_to_info_json(self, key: str, val: Any):
        info = util.catch_load_json(self.info_file)

        with open(self.info_file, "w", encoding="utf-8") as f:
            info[key] = val
            json.dump(info, f)

    @magic_arguments()
    @argument("py_file", type=str, help="Absolute path to current .py file")
    @argument("in_style", type=int, help="Input-display style to use")
    @argument("--max_size", type=int, help="Max size of .ipynb file in MiB", default=20)
    @line_magic
    def jukit_init(self, param: str):
        args = parse_argstring(self.jukit_init, param)
        py_file = args.py_file.replace("<JUKIT_WS_PH>", " ")
        dir_, fname = os.path.split(py_file)
        fname_outhist = os.path.splitext(fname)[0] + "_outhist.json"

        self.py_file = py_file

        self.jukit_dir = os.path.join(dir_, ".jukit")
        self.cmd_file = os.path.join(dir_, ".jukit", ".cmd")

        self.info_file = os.path.join(self.jukit_dir, ".jukit_info.json")
        self.outhist_file = os.path.join(self.jukit_dir, fname_outhist)
        self.display_input = display_functions.get(args.in_style)
        if self.display_input is None:
            self.display_input = display_style_2

        self.max_bytes = args.max_size * 2**20

        if not os.path.isdir(self.jukit_dir):
            os.mkdir(self.jukit_dir)
            with open(self.info_file, "w", encoding="utf-8") as f:
                json.dump({}, f)

        self._write_to_info_json("import_complete", 1)

    @magic_arguments()
    @argument("--cell_id", type=str)
    @cell_magic
    def jukit_capture(self, param: str, cell: str):
        args = parse_argstring(self.jukit_capture, param)
        plt.close()
        with JukitCaptureOutput(self.max_bytes, cell_id=args.cell_id) as io:
            result = self.shell.run_cell(cell).result

            if any([plt.figure(k).stale for k in plt.get_fignums()]):
                self.shell.run_cell("plt.show()")

            captured_out = str(io)

            if result is not None and hasattr(result, "__repr__"):
                if self.shell.display_formatter.formatters["text/plain"].pprint:
                    pattern = re.escape(pretty(result))
                else:
                    pattern = re.escape(repr(result))
                pattern += r"(?=\s*<-- JUKIT_PLOT_PLACEHOLDER -->\s*$|\s*$)"
                try:
                    exec_result = {
                        "result": re.findall(pattern, captured_out)[-1],
                        "count": self.shell.execution_count,
                    }
                    captured_out = re.sub("\n*" + pattern + "\n*", "\n", captured_out)
                except IndexError:
                    exec_result = None
            else:
                exec_result = None

            captured_out = util.check_output_size(
                captured_out, self.outhist_file, self.max_bytes
            )

            if captured_out is not None:
                add_to_output_history(
                    captured_out, args.cell_id, self.outhist_file, exec_result
                )

    @line_magic
    def jukit_run(self, cmd_param: Optional[str] = None):
        assert hasattr(
            self, "jukit_dir"
        ), "Must first run `%jukit_init <path/to/file.py>`"

        if cmd_param:
            cmd, param = cmd_param
            opts, name = self.parse_options(param, "pqs", "cell_id=", mode="string")
        else:
            param, cmd = self._get_info_json_keys("cmd_opts", "cmd")
            opts, name = self.parse_options(param, "pqs", "cell_id=", mode="string")

        if "p" not in opts:
            util.hide_prompt(self.shell)

        if "q" not in opts:
            self.display_input(cmd, self.shell)
        else:
            sys.stdout.write("\r")

        if "s" in opts and cmd not in ["", "\n"]:
            cmd = f"%%jukit_capture --cell_id={opts.cell_id}\n" + cmd

        with monitor_execution_count(self.shell):
            self.store_or_execute(cmd, name)

    @line_magic
    def jukit_run_split(self, _):
        assert hasattr(
            self, "jukit_dir"
        ), "Must first run `%jukit_init <path/to/file.py>`"
        param, all_cmd = self._get_info_json_keys("cmd_opts", "cmd")

        cells = re.split(rf".*{re.escape(HEADER)}.*", all_cmd)
        cell_ids1 = re.findall(rf"{re.escape(HEADER)} <(.*)\|.*>", all_cmd)
        cell_ids2 = re.findall(rf"{re.escape(HEADER)} <.*\|(.*)>", all_cmd)
        cell_ids = [cell_ids1[0]] + cell_ids2

        for i, (cell, id_) in enumerate(zip(cells, cell_ids)):
            p = param + " -p" * (i > 0) + f" --cell_id={id_}"
            self.jukit_run(cmd_param=(cell, p))
            if i > 0:
                self.shell.execution_count += 1

    @monitor_excount_dec
    @line_magic
    def jukit_out_hist(self, _):
        assert hasattr(
            self, "jukit_dir"
        ), "Must first run `%jukit_init <path/to/file.py>`"
        cell_id, out_title, is_md, term = self._get_info_json_keys(
            "outhist_cell", "outhist_title", "is_md", "terminal"
        )

        self.shell.prompts = MyPrompt(self.shell)
        if os.name != "nt":
            self.shell.run_line_magic("clear", "")

        x, _ = os.get_terminal_size()

        if not os.path.isfile(self.outhist_file):
            util.jukit_info(f"File {self.outhist_file} not found")
            return

        out_hist = util.catch_load_json(self.outhist_file)

        util.display_cell_id(cell_id, x, min_frame_width=25)

        outputs = out_hist.get(cell_id)

        if outputs is None and not is_md:
            util.jukit_info("No saved output found", color="\u001b[35m")
            return
        elif is_md:
            util.jukit_info("Markdown Cell", color="\u001b[33m")
            return

        self._write_to_info_json("output_complete", 0)
        plt.close()
        util.display_outputs(outputs, term, self.shell)
        self._write_to_info_json("output_complete", 1)
