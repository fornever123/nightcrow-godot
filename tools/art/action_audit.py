"""盘点战斗角色的全部动作剪辑，导出「哪些动作值得用即梦视频重做」的实测表。

只读 assets/data/battle.json 和帧文件的尺寸，不改游戏资源。
输出：.runtime/action-audit/action_inventory.md 和 .csv

用法：python tools/art/action_audit.py
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BATTLE = ROOT / "assets" / "data" / "battle.json"
OUT = ROOT / ".runtime" / "action-audit"

# 每条线的现状判断（人工结论，脚本只负责把数字填进来）
VERDICT = {
    "run": ("重做 · 最高优先级", "6 帧够不到一个步态；剑是焊在身上的，压腿；没有接触/腾空四拍"),
    "idle": ("保留", "69 帧够长，呼吸和发梢已经在动"),
    "turn_left_right": ("重做 · 中", "7 帧转向，脚没有交叉步，转身像原地扭"),
    "turn_right_left": ("重做 · 中", "5 帧更薄，同上"),
    "jump": ("重做 · 高", "9 帧起跳，没有蓄力压腿和下蹲起跳的重量"),
    "fall": ("重做 · 中", "8 帧循环，披肩和鸦羽完全不动，下落像悬浮"),
    "land": ("重做 · 高", "8 帧落地，缺缓冲下压和起身，砸地没有反馈"),
    "attack_1": ("保留（刀光已定稿）", "13 帧 24fps，刀光是画进帧里的硬边，重做会打掉光线线定稿"),
    "attack_2": ("保留（刀光已定稿）", "18 帧，同上"),
    "attack_3": ("保留（刀光已定稿）", "30 帧，同上"),
    "strong_attack": ("保留（刀光已定稿）", "31 帧挑飞，同上"),
    "attack_up": ("保留（刀光已定稿）", "31 帧强化挑飞，帧里带刀光"),
    "attack_2_start": ("保留（刀光已定稿）", "17 帧第二刀前摇变体，帧里带刀光"),
    "attack_2_recovery": ("保留（刀光已定稿）", "30 帧第二刀后摇变体，帧里带刀光"),
    "air_attack_1": ("保留（刀光已定稿）", "18 帧空中连段"),
    "air_attack_2": ("保留（刀光已定稿）", "12 帧"),
    "air_attack_3": ("保留（刀光已定稿）", "26 帧"),
    "dash_left": ("保留", "21 帧冲刺斩左向，帧里有烘焙尘土，重做要重铺 FX"),
    "dash_right": ("保留", "35 帧冲刺斩右向，同上"),
    "guard_start": ("保留", "12 帧起架，读招用"),
    "guard_hold": ("重做 · 低", "只有 1 帧定格，格挡时完全静止"),
    "guard_hit_1": ("保留 · 低", "9 帧"),
    "guard_hit_2": ("保留 · 低", "13 帧"),
    "guard_hit_3": ("保留 · 低", "36 帧"),
    "parry_react_1": ("重做 · 中", "16 帧弹刀，弹开的方向感和剑的震颤要重做"),
    "parry_react_2": ("重做 · 中", "16 帧，同上"),
    "parry_react_3": ("重做 · 中", "20 帧，同上"),
    "draw": ("重做 · 中", "50 帧拔刀，收刀/拔刀是玩家每秒都会看两遍的动作"),
    "sheathe": ("重做 · 中", "39 帧收刀，同上"),
    "death": ("保留 · 低", "124 帧，够长"),
    "charge_slash": ("保留（另一套成品帧）", "85 帧 60fps，charge-20261026 单独一套"),
    "charge_hold": ("保留（另一套成品帧）", "24 帧 60fps 蓄力循环"),
    "air_slash": ("保留", "18 帧，旧指令兼容"),
    "parry": ("保留", "12 帧，兼容"),
    "dash_left_video": ("保留", "21 帧，兼容"),
    "dash_right_video": ("保留", "22 帧，兼容"),
}


def main() -> None:
    data = json.loads(BATTLE.read_text(encoding="utf-8"))
    anims = data["characters"][0]["sprite"]["animations"]

    rows = []
    for name, clip in anims.items():
        if name.startswith("source_"):
            continue
        frames = clip.get("frames") or []
        if not frames:
            continue
        fps = float(clip.get("fps", 24))
        ticks = sum(int(f.get("durationTicks", 1)) for f in frames)
        dur = ticks / fps
        root = frames[0]["asset"].split("/")[0] + "/" + frames[0]["asset"].split("/")[1]
        verdict, why = VERDICT.get(name, ("未评估", ""))
        rows.append({
            "clip": name,
            "frames": len(frames),
            "fps": round(fps, 2),
            "duration_s": round(dur, 3),
            "loop": bool(clip.get("loop", False)),
            "root": root,
            "verdict": verdict,
            "why": why,
        })
    order = {"run": 0, "jump": 1, "land": 2, "fall": 3, "turn_left_right": 4,
             "turn_right_left": 5, "idle": 6}
    rows.sort(key=lambda r: (order.get(r["clip"], 50), r["clip"]))

    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "action_inventory.csv").open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    lines = ["| 动作 | 帧数 | 帧率 | 时长 | 循环 | 素材目录 | 结论 | 原因 |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(
            f"| `{r['clip']}` | {r['frames']} | {r['fps']} | {r['duration_s'] * 1000:.0f}ms"
            f" | {'是' if r['loop'] else ''} | `{r['root']}` | {r['verdict']} | {r['why']} |")
    (OUT / "action_inventory.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(rows)} clips -> {OUT / 'action_inventory.md'}")


if __name__ == "__main__":
    main()
