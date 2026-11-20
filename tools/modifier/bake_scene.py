"""修改器的“出图”：把场景里的拼接方案（一段）交给背景线的 rain_kit_compose.compose 拼成近景成图。

只调它的 compose，不改它的脚本、不写 rain_street_layout.json（改动都存在 tuning.json 里）。
stdin：{"plan": 一段方案, "out": "edits/xxx.png", "extra": {用户导入的件}}
stdout 最后一行：{"art": {...}}
相比方案原有字段，这里多支持一个 item.y：这一件整体上下挪多少（世界单位）。
"""
import copy
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/art"))
import rain_kit_compose as rc  # noqa: E402


def shifted(piece, dy):
    q = copy.deepcopy(piece)
    q["top"] = piece["top"] + dy
    q["stand"] = [[a, b, y + dy, s] for a, b, y, s in piece["stand"]]
    q["blocks"] = [[a, b, y + dy, s] for a, b, y, s in piece["blocks"]]
    q["lamps"] = [[x, y + dy, k, r] for x, y, k, r in piece["lamps"]]
    return q


def main():
    job = json.load(sys.stdin)
    plan = job["plan"]
    px, kit = rc.load_kit()
    kit = dict(kit, **job.get("extra", {}))
    # 上下挪过的件换成一份挪好的元数据，compose 就不用改
    for item in plan["items"]:
        dy = float(item.get("y", 0) or 0)
        if dy:
            key = f'{item["piece"]}@{dy}'
            kit[key] = shifted(kit[item["piece"]], dy)
            item["piece"] = key
    index = int(plan["index"])
    # compose 写回的是这份内存里的布局，不落盘
    layout = {"sections": [{} for _ in range(index + 1)]}
    plan["out"] = job["out"]
    (rc.ART / job["out"]).parent.mkdir(parents=True, exist_ok=True)
    rc.compose(plan, px, kit, layout)
    art = layout["sections"][index]["art"]
    art["near"] = "res://assets/image/rain_street/" + job["out"]
    print(json.dumps({"art": art}, ensure_ascii=False))


if __name__ == "__main__":
    main()
