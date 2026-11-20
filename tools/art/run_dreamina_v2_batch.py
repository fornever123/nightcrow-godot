#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
即梦画布 CLI (dreamina-canvas 1.2.1) 自动化执行脚本（严格对齐 schema 字段契约）。
"""
from __future__ import annotations

import json
import subprocess
import sys
import uuid
import webbrowser
from pathlib import Path

CLI = r"C:\Users\MECHREVO\bin\dreamina-canvas.exe"
ROOT = Path(__file__).resolve().parents[2]
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\动作补齐_即梦v2_20261117"
UP_DIR = ROOT / ".runtime" / "dm_up"
DL_TMP_DIR = ROOT / ".runtime" / "dm_dl"
OUT_MP4_DIR = WORK_DIR / "即梦成片_v2"
STATE_PATH = WORK_DIR / "dreamina_job_state.json"
APPROVED_CEILING = 300
CREATED_CANVAS_ID = "a1497b84-3bf7-4b8e-8756-e1a3a69c614b"
CREATED_WEB_URL = "https://jimeng.jianying.com/ai-tool/ai-canvas/a1497b84-3bf7-4b8e-8756-e1a3a69c614b"


def load_state() -> dict:
    if STATE_PATH.exists():
        st = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    else:
        st = {"canvasId": CREATED_CANVAS_ID, "webUrl": CREATED_WEB_URL, "uploads": {}, "nodes": {}, "videos": {}}
    st.setdefault("uploads", {}).setdefault("img_main", "7c200e7f-b2a5-4829-b0eb-4c3f996e3f0f")
    return st


def save_state(st: dict) -> None:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")


def run_cli(args: list[str], allow_exit_codes: tuple[int, ...] = (0,)) -> tuple[int, dict]:
    cmd = [CLI, "--format", "json", "--non-interactive", *args]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    out = proc.stdout.strip()
    parsed = {}
    if out:
        for ln in reversed(out.splitlines()):
            ln = ln.strip()
            if ln.startswith("{") and ln.endswith("}"):
                parsed = json.loads(ln)
                break
    if proc.returncode not in allow_exit_codes:
        raise RuntimeError(f"CLI failed (rc={proc.returncode}): {' '.join(args[:6])}\nSTDOUT: {out}\nSTDERR: {proc.stderr}")
    return proc.returncode, parsed


def ensure_canvas(st: dict) -> str:
    cid = st.get("canvasId") or CREATED_CANVAS_ID
    _, res = run_cli(["canvas", "use", cid])
    cinfo = res["data"].get("currentCanvas", {}).get("canvas", res["data"].get("canvas", {}))
    cid = cinfo.get("projectId", cid)
    wurl = cinfo.get("webUrl", st.get("webUrl", CREATED_WEB_URL))
    st["canvasId"] = cid
    st["webUrl"] = wurl
    save_state(st)
    print(f"CANVAS_ACTIVE: projectId={cid} webUrl={wurl}", flush=True)
    try:
        webbrowser.open(wurl)
    except Exception:
        pass
    return cid


def ensure_uploaded_node(st: dict, cid: str, key: str, file_path: Path, media_type: str, title: str) -> str:
    if key in st["nodes"]:
        return st["nodes"][key]
    pending_ids = st.setdefault("pendingUploadIds", {})
    if key not in st["uploads"]:
        req_res_id = pending_ids.get(key) or str(uuid.uuid4())
        pending_ids[key] = req_res_id
        save_state(st)
        res_id = ""
        import time
        for attempt in range(5):
            # 先做只读检查，若远端已落地则直接复用，绝不盲目重复创建
            rc_g, g_res = run_cli(["resource", "get", req_res_id, "--project-id", cid], allow_exit_codes=(0, 1, 2, 13, 21, 22))
            if rc_g == 0 and g_res.get("ok") and (g_res.get("data") or {}).get("resourceId"):
                res_id = g_res["data"]["resourceId"]
                break
            rc_u, up_res = run_cli([
                "resource", "upload",
                "--project-id", cid,
                "--file", str(file_path),
                "--resource-id", req_res_id,
                "--name", key,
                "--import-kind", "local_upload",
            ], allow_exit_codes=(0, 21, 22))
            if rc_u == 0 and up_res.get("ok"):
                res_id = up_res["data"]["resourceId"]
                break
            time.sleep(2.0 * (attempt + 1))
        if not res_id:
            # 最后再做一次只读确认
            rc_g, g_res = run_cli(["resource", "get", req_res_id, "--project-id", cid], allow_exit_codes=(0, 1, 2, 13, 21, 22))
            if rc_g == 0 and g_res.get("ok") and (g_res.get("data") or {}).get("resourceId"):
                res_id = g_res["data"]["resourceId"]
            else:
                raise RuntimeError(f"Failed to upload {key} ({file_path}) after retries with resource-id {req_res_id}")
        st["uploads"][key] = res_id
        save_state(st)
    else:
        res_id = st["uploads"][key]

    submit_id = str(uuid.uuid4())
    _, nd_res = run_cli([
        "node", "create", media_type,
        "--project-id", cid,
        "--title", title,
        "--resource-id", res_id,
        "--import-kind", "local_upload",
        "--submit-id", submit_id,
    ])
    node_obj = nd_res["data"]["node"]
    nid = node_obj["nodeId"]
    st["nodes"][key] = nid
    save_state(st)
    print(f"IMPORTED_NODE [{key}] -> {nid} (res={res_id})", flush=True)
    return nid


def ensure_element(st: dict, cid: str, main_nid: str, aux_nids: list[str]) -> str:
    if "elem_shuo" in st["nodes"]:
        return st["nodes"]["elem_shuo"]
    cmd = [
        "node", "create", "element",
        "--project-id", cid,
        "--title", "朔_实机标准主体",
        "--description", "断晓主角夜鸦朔：2.8头身实机2D赛璐璐比例，细银挑染，白色抹胸，白边黑百褶裙，十字长筒袜，笔直紫晶长剑",
        "--main", main_nid,
    ]
    for a in aux_nids:
        cmd.extend(["--auxiliary", a])
    _, res = run_cli(cmd)
    eid = res["data"]["node"]["nodeId"]
    st["nodes"]["elem_shuo"] = eid
    save_state(st)
    print(f"ELEMENT_CREATED -> {eid}", flush=True)
    return eid


def build_specs(elem_nid: str, nids: dict[str, str]) -> list[dict]:
    e = f"{{{{node:{elem_nid}}}}}"
    return [
        {
            "key": "V1_小受击",
            "mode": "m2v",
            "refs": [f"node:{elem_nid}", f"node:{nids['vid_v1']}"],
            "prompt": (
                f"以 {e} 中的2D赛璐璐Q版黑发少女剑士作为唯一主角，严格保持她的2.8头身比例、五官发型、细银挑染、白色抹胸、"
                f"黑色百褶短裙、十字长筒袜与手中笔直的黑银紫晶长直剑不变，完整复刻 {{{{node:{nids['vid_v1']}}}}} 中的原地受击动作、"
                f"受击节奏与肢体幅度：角色面朝画面右侧持剑待机，正面受击瞬间胸前迸发冷白色短促星芒冲击闪光，低头弯腰前折并抬起前脚缓冲，"
                f"随即迅速弹回持剑预备架势，紧接着再次受击弯腰前折缓冲并干脆利落弹回待机姿态。全程横版游戏正侧视固定机位不推拉不晃动，"
                f"纯净平涂 #7FA88F 灰绿背景，无地面线、无阴影倒影、无任何文字数字与水印，线条锐利清晰无重影。"
            ),
        },
        {
            "key": "V2_大受击",
            "mode": "m2v",
            "refs": [f"node:{elem_nid}", f"node:{nids['vid_v2']}"],
            "prompt": (
                f"以 {e} 中的2D赛璐璐Q版黑发少女剑士作为唯一主角，严格保持她的2.8头身比例、服装配饰与笔直的黑银紫晶长直剑不变，"
                f"完整复刻 {{{{node:{nids['vid_v2']}}}}} 中的连续两次重受击动作轨迹、扭身幅度与节奏：角色面朝右侧持剑站立，"
                f"第一次重受击时胸前爆开冷白色冲击闪光，身体被巨力打得向左侧滑退、大幅弯腰扭身甩动头发与背后鸦羽披肩后稳住架势；"
                f"紧接着第二次重受击时身体向前扑倒低伏缓冲，随后撑起身体利落站回面朝右侧的持剑待机姿势。全程横版正侧视固定机位，"
                f"纯净平涂 #7FA88F 灰绿背景，无地面线、无文字数字与水印，动作干净清晰不模糊。"
            ),
        },
        {
            "key": "V3_击飞倒地起身",
            "mode": "m2v",
            "refs": [f"node:{elem_nid}", f"node:{nids['vid_v3']}"],
            "prompt": (
                f"以 {e} 中的2D赛璐璐Q版黑发少女剑士作为唯一主角，严格保持她的2.8头身比例、服装配饰与手中笔直的黑银紫晶长直剑不变，"
                f"完整复刻 {{{{node:{nids['vid_v3']}}}}} 中的被击飞倒地与起身全过程动作：角色面朝右侧遭重击后双脚离地向左侧横飞腾空，"
                f"重重摔落地面平躺缓冲，短暂停顿后单手单膝撑地发力站起，重新稳稳回到面朝右侧的持剑待机架势。全程横版正侧视固定机位，"
                f"纯净平涂 #7FA88F 灰绿背景，画面中只有主角一人，无敌人、无地面线、无文字数字与水印，肢体与长剑结构清晰稳定。"
            ),
        },
        {
            "key": "V4_K键远程空翻剑气",
            "mode": "m2v",
            "refs": [f"node:{elem_nid}", f"node:{nids['vid_v4']}"],
            "prompt": (
                f"以 {e} 中的2D赛璐璐Q版黑发少女剑士作为唯一主角，严格保持她的2.8头身比例、服装配饰与笔直的黑银紫晶长直剑不变，"
                f"完整复刻 {{{{node:{nids['vid_v4']}}}}} 中的跃起空翻挥斩动作与位移节奏：角色面朝右侧迅速屈膝下蹲蓄力，"
                f"随即向前上方跃起在空中利落前空翻一周，落地的瞬间双手挥动长直剑向右前方全力横斩劈出一道外亮白内电光紫的月牙刀弧与向前飞射的细直剑气，"
                f"随后单膝缓冲稳稳站起回到面朝右侧的持剑待机姿势。全程横版正侧视固定机位，纯净平涂 #7FA88F 灰绿背景，无地面线、无文字数字与水印，线条锐利。"
            ),
        },
        {
            "key": "V5_空中急坠下劈砸地",
            "mode": "m2v",
            "refs": [f"node:{elem_nid}", f"node:{nids['vid_v5']}"],
            "prompt": (
                f"以 {e} 中的2D赛璐璐Q版黑发少女剑士作为唯一主角，严格保持她的2.8头身比例、服装配饰与笔直的黑银紫晶长直剑不变，"
                f"完整复刻 {{{{node:{nids['vid_v5']}}}}} 中的空中急坠下劈砸地与收势动作：角色在半空面朝右侧双手高举长直剑蓄势，"
                f"随即极速垂直向下俯冲重劈落地，挥出一道凌厉的外亮白内电光紫竖劈刀弧，落地屈膝深蹲稳住重心后利落起身回到持剑待机架势。"
                f"全程横版正侧视固定机位，纯净平涂 #7FA88F 灰绿背景，无方块障碍物、无地面线、无文字数字与水印，结构清晰不糊。"
            ),
        },
        {
            "key": "V6_普攻1段收招回待机",
            "mode": "first_last_frame",
            "refs": [f"node:{nids['img_a1_end']}", f"node:{nids['img_main']}"],
            "prompt": (
                f"横版2D赛璐璐Q版动作游戏固定侧视镜头，纯净 #7FA88F 灰绿背景。角色从 {{{{node:{nids['img_a1_end']}}}}} 的右前方低姿挥剑结束架势开始，"
                f"顺着惯性自然旋腕将手中笔直的黑银紫晶长直剑轻巧收回体侧右前方，双腿平稳收步站起，流畅自然地过渡回 {{{{node:{nids['img_main']}}}}} "
                f"的标准持剑待机姿势并保持轻微呼吸。全程人物比例、五官服装与长剑笔直形态严格一致，双脚踩稳同一水平基线，无多余刀光、无文字水印。"
            ),
        },
        {
            "key": "V7_跑步急停收步回待机",
            "mode": "first_last_frame",
            "refs": [f"node:{nids['img_run']}", f"node:{nids['img_main']}"],
            "prompt": (
                f"横版2D赛璐璐Q版动作游戏固定侧视镜头，纯净 #7FA88F 灰绿背景。角色从 {{{{node:{nids['img_run']}}}}} 的向右前倾奔跑姿态开始急停刹步："
                f"前脚向前踏实微屈膝缓冲卸去冲力，上身由前倾平稳回正，身后拖持的笔直黑银紫晶长直剑顺势收回体侧右前方，后脚跟进站稳，"
                f"干净利落地收束到 {{{{node:{nids['img_main']}}}}} 的标准持剑待机姿势。全程人物比例、五官服装与长剑形态严格一致，双脚不悬空，无地面线与文字水印。"
            ),
        },
    ]


def pending_idx_name(vkey: str) -> str:
    return vkey.split("_")[0]


def main() -> None:
    OUT_MP4_DIR.mkdir(parents=True, exist_ok=True)
    st = load_state()
    cid = ensure_canvas(st)

    media_defs = [
        ("img_main", UP_DIR / "img_main_pose002.png", "image", "图主_实机待机真身pose002"),
        ("img_side", UP_DIR / "img_aux_side.png", "image", "图辅1_三视图单人侧面"),
        ("img_back", UP_DIR / "img_aux_back.png", "image", "图辅2_三视图单人背面与剑"),
        ("img_a1_end", UP_DIR / "img_start_a1_end.png", "image", "首帧_普攻1末帧净人物"),
        ("img_run", UP_DIR / "img_start_run.png", "image", "首帧_跑步迈步帧"),
        ("vid_v1", UP_DIR / "vid_V1_hurt_light.mp4", "video", "参考视频_V1小受击_60高对齐"),
        ("vid_v2", UP_DIR / "vid_V2_hurt_heavy.mp4", "video", "参考视频_V2大受击_60高对齐"),
        ("vid_v3", UP_DIR / "vid_V3_launch_down_getup.mp4", "video", "参考视频_V3击飞倒地起身_60高对齐"),
        ("vid_v4", UP_DIR / "vid_V4_ranged_cast.mp4", "video", "参考视频_V4远程空翻剑气_60高对齐"),
        ("vid_v5", UP_DIR / "vid_V5_air_plunge.mp4", "video", "参考视频_V5空中急坠下劈_60高对齐"),
    ]
    nids: dict[str, str] = {}
    for k, fp, mtype, title in media_defs:
        nids[k] = ensure_uploaded_node(st, cid, k, fp, mtype, title)

    elem_nid = ensure_element(st, cid, nids["img_main"], [nids["img_side"], nids["img_back"]])

    specs = build_specs(elem_nid, nids)
    pending_keys: list[str] = []
    pending_nids: list[str] = []

    for sp in specs:
        vkey = sp["key"]
        vrec = st["videos"].get(vkey, {})
        if not vrec.get("nodeId"):
            cmd = [
                "node", "create", "video",
                "--project-id", cid,
                "--title", vkey,
                "--mode", sp["mode"],
                "--model", "seedance_2.0_fast_vip",
                "--ratio", "16:9",
                "--resolution", "720p",
                "--duration", "4",
                "--count", "1",
                "--prompt", sp["prompt"],
            ]
            for r in sp["refs"]:
                cmd.extend(["--ref", r])
            _, res = run_cli(cmd)
            vnid = res["data"]["node"]["nodeId"]
            vrec["nodeId"] = vnid
            st["videos"][vkey] = vrec
            save_state(st)
            print(f"SAVED_VIDEO_DRAFT [{vkey}] -> {vnid}", flush=True)
        if not vrec.get("submitId"):
            pending_keys.append(vkey)
            pending_nids.append(vrec["nodeId"])

    if pending_nids:
        q_cmd = ["node", "quote", "--project-id", cid]
        for vnid in pending_nids:
            q_cmd.extend(["--node-id", vnid])
        _, q_res = run_cli(q_cmd)
        q_data = q_res["data"]
        print("QUOTE_RESULT:", json.dumps(q_data, ensure_ascii=False), flush=True)
        total_ceil = int(q_data["totalMaxCredits"])
        st["lastQuoteTotal"] = total_ceil
        save_state(st)
        if total_ceil > APPROVED_CEILING:
            print(f"STOP_OVER_CEILING: quote={total_ceil} > approved={APPROVED_CEILING}", flush=True)
            sys.exit(10)

        credit_token = ""
        if q_data.get("confirmationRequired", True):
            c_cmd = ["node", "confirm", "--project-id", cid, "--credit-ceiling", str(APPROVED_CEILING)]
            for vnid in pending_nids:
                c_cmd.extend(["--node-id", vnid])
            _, c_res = run_cli(c_cmd)
            credit_token = c_res["data"].get("creditConfirmationToken", "")

        submit_ids = []
        for vkey in pending_keys:
            sid = str(uuid.uuid4())
            st["videos"][vkey]["submitId"] = sid
            submit_ids.append(sid)
        save_state(st)

        r_cmd = ["node", "run", "--project-id", cid]
        for vnid, sid in zip(pending_nids, submit_ids):
            r_cmd.extend(["--node-id", vnid, "--submit-id", sid])
        if credit_token:
            r_cmd.extend(["--credit-token", credit_token])
        _, r_res = run_cli(r_cmd)
        credit_token = ""
        print("RUN_ACCEPTED:", json.dumps(r_res["data"], ensure_ascii=False), flush=True)

    for sp in specs:
        vkey = sp["key"]
        vrec = st["videos"][vkey]
        out_mp4 = OUT_MP4_DIR / f"{vkey}.mp4"
        if out_mp4.exists() and out_mp4.stat().st_size > 50_000 and vrec.get("selectedResourceId"):
            print(f"ALREADY_DOWNLOADED [{vkey}] -> {out_mp4}", flush=True)
            continue
        sid = vrec["submitId"]
        vnid = vrec["nodeId"]
        print(f"WAITING [{vkey}] submitId={sid} ...", flush=True)
        rc, w_res = run_cli(["operation", "wait", sid, "--project-id", cid, "--timeout", "12m", "--interval", "6s"], allow_exit_codes=(0, 20))
        if rc == 20:
            _, w_res = run_cli(["operation", "wait", sid, "--project-id", cid, "--timeout", "10m", "--interval", "6s"])

        selected_res = ""
        w_resources = (w_res.get("data") or {}).get("resources") or []
        if w_resources:
            selected_res = w_resources[0].get("resourceId", "")

        if not selected_res:
            _, sh_res = run_cli(["node", "show", "--project-id", cid, "--node-id", vnid])
            nodes_arr = sh_res["data"].get("nodes") or []
            if nodes_arr:
                nd = nodes_arr[0].get("node", nodes_arr[0])
                selected_res = nd.get("selectedResourceId") or ((nd.get("resources") or [{}])[0].get("resourceId", ""))

        if not selected_res:
            print(f"WARN_NO_RESOURCE [{vkey}]", flush=True)
            continue
        vrec["selectedResourceId"] = selected_res
        save_state(st)

        DL_TMP_DIR.mkdir(parents=True, exist_ok=True)
        ascii_mp4 = DL_TMP_DIR / f"vid_{ pending_idx_name(vkey) }.mp4"
        _, dl_res = run_cli(["resource", "download", selected_res, "--project-id", cid, "--output", str(ascii_mp4)])
        import shutil
        shutil.copy2(ascii_mp4, out_mp4)
        vrec["sha256"] = dl_res["data"].get("sha256", "")
        vrec["bytes"] = dl_res["data"].get("size", out_mp4.stat().st_size if out_mp4.exists() else 0)
        save_state(st)
        print(f"DOWNLOADED [{vkey}] -> {out_mp4} ({vrec['bytes']} bytes)", flush=True)

    _, acc_res = run_cli(["auth", "account"])
    print("FINAL_CREDITS_AVAILABLE:", acc_res["data"].get("availableCredits"), flush=True)


if __name__ == "__main__":
    main()
