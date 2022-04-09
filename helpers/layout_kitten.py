import json
from typing import List, Tuple

from kitty.boss import Boss
from kittens.tui.handler import result_handler
from kitty.layout.splits import Splits, Pair


def main(args: List[str]) -> None:
    pass


@result_handler(no_ui=True)
def handle_result(
    args: List[str], answer: None, target_window_id: int, boss: Boss
) -> None:
    layout, splits = _parse_arglist(args[1:])
    splits.update({"file_content": target_window_id})

    apply_layout(splits, layout, boss)


def apply_layout(splits: dict, layout: dict, boss: Boss):
    id_map = _get_id_map(splits, boss)

    if len(id_map) < 2:
        return

    tab = boss.active_tab

    layout = JukitLayout(tab.os_window_id, tab.id, layout=layout, id_map=id_map)
    _set_tab_layout(tab, layout)


def _parse_arglist(arglist: list) -> Tuple[dict, dict]:
    layout = json.loads(arglist[0])
    splits = {}
    for arg in arglist[1:]:
        splits.update(json.loads(arg))

    return layout, splits


def _get_id_map(splits: dict, boss: Boss) -> dict:
    windows = {}
    for name, id_ in splits.items():
        if name == "file_content":
            windows[name] = id_
        else:
            win = next(iter(boss.match_windows(f"title:{id_}")), None)
            if win is not None:
                windows[name] = win.id

    return windows


def _set_tab_layout(tab, layout):
    tab.current_layout = layout
    tab._current_layout_name = "jukit"
    tab._last_used_layout = tab._current_layout_name
    tab._current_layout_name = "jukit"
    tab.enabled_layouts += ["jukit"]
    tab.mark_tab_bar_dirty()
    tab.relayout()


class JukitLayout(Splits):
    def __init__(self, os_window_id: int, tab_id: int, layout: dict, id_map: dict):
        super().__init__(os_window_id, tab_id, "")
        self.jukit_layout = layout
        self.id_map = id_map
        self.layout_pair = None

    def do_layout(self, all_windows):
        if self.layout_pair is None:
            self.layout_pair = self._pair_from_layout(self.jukit_layout)
            self.pairs_root = self.layout_pair
            # self.pairs_root(p)
            super().do_layout(all_windows)
        else:
            super().do_layout(all_windows)

    def _pair_from_layout(self, ld):
        p = Pair(horizontal=ld["split"] == "horizontal")
        p.bias = ld["p1"]
        v1, v2 = ld["val"]
        p.one = (
            self.id_map.get(v1) if isinstance(v1, str) else self._pair_from_layout(v1)
        )
        p.two = (
            self.id_map.get(v2) if isinstance(v2, str) else self._pair_from_layout(v2)
        )
        return p
