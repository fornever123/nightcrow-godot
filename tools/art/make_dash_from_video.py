"""冲刺斩按参考视频接入：视频里左右两个方向各演示一遍，最后一段是多余的定格。
  第 1–21 帧  = 向左冲刺斩（dash_slash_left，动画 dash_left_video，sourceFacing -1）
  第 22–43 帧 = 向右冲刺斩（dash_slash，动画 dash_right_video，sourceFacing 1）
  第 44–56 帧 = 多余的定格姿势，不用

- 锚点用原片根位置（pivotXAuthored）；rootMotionX = 参考视频里这一段的真实位移 × displayScale（朝前为正），
  所以走位和视频一样：向左段冲约 1940px，向右段冲约 2370px（视频像素）。
  帧数据里的 sourceRootX 是跟着角色的“镜头内”坐标，只差约 280px，不能用；真实位移从
  参考视频 mmh3_冲刺攻击_v2.mp4（3072×960，24fps，56 帧，和桌面帧 1:1）逐帧模板匹配量出来，见 VIDEO_ROOT_X。
- 原来的 dash_left / dash_right 动画不动（大招借用它们的姿势）。
- 两招都按原版 24 帧/秒播（去掉分段变速），位移全部来自 rootMotionX。

用法：python tools/art/make_dash_from_video.py   （改 assets/data/battle.json，可重复跑）"""
import copy, json, os

CFG = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'data', 'battle.json')

# 参考视频里每帧角色根位置的 x（视频像素）。桌面帧在视频里的位置用身体像素模板匹配得到，
# + 该帧 pivotXAuthored（去掉 assetFxPad）。第 31 帧桌面帧被手调过、匹配不准，用身体暗部中位数对齐。
VIDEO_ROOT_X = [2317.5, 2091.2, 2103.5, 2092.0, 1852.0, 1652.0, 1554.0, 1277.0, 878.0, 794.0, 630.0, 491.0,
                454.0, 434.0, 409.0, 402.0, 389.0, 377.0, 380.0, 380.0, 381.0, 378.0, 502.0, 838.0, 1055.0, 1035.0,
                1060.0, 1320.0, 1621.0, 1858.0, 2106.0, 2222.0, 2435.0, 2526.5, 2645.0, 2735.0, 2732.5, 2731.5,
                2738.5, 2745.0, 2743.0, 2736.0, 2703.0, 2582.0, 2580.0, 2581.0, 2583.0, 2586.0, 2583.0, 2583.5,
                2585.5, 2584.0, 2582.0, 2584.0, 2584.8, 2581.0]

# 招式 id → (动画名, 中文名, 视频帧范围[从 1 数，含两端], 朝向, 判定帧, 接招帧)。
# 判定从第 1 帧开始覆盖整段冲刺路径（角色一路穿过敌人，每只只吃一刀）；
# 接招帧 = 位移基本停下的那一帧，冲完就能接 J / K / 冲刺 或按方向走开，不用站着等收招。
CLIPS = {
    'dash_slash_left': ('dash_left_video', '向左冲刺斩', (1, 21), -1, (1, 11), 16),
    'dash_slash': ('dash_right_video', '向右冲刺斩', (22, 43), 1, (1, 12), 15),
}
# 手感：只有第一次命中让自己顿帧（hitstopFirstOnly），并且顿得短；路上后面的敌人照样受击，自己不停
HITSTOP = 0.1            # 秒（原来 0.18）


def main():
    cfg = json.load(open(CFG, encoding='utf-8'))
    sprite = cfg['characters'][0]['sprite']
    anims = sprite['animations']
    anims.pop('dash_full', None)
    scale = float(sprite.get('displayScale', 1.0))
    source = anims['dash_left']['frames'] + anims['dash_right']['frames']   # 视频第 1–56 帧
    assert len(source) == len(VIDEO_ROOT_X)
    for move_id, (clip, name, (first, last), facing, active, chain) in CLIPS.items():
        frames = []
        for f in source[first - 1:last]:
            g = copy.deepcopy(f)
            g['pivotX'] = float(g.get('pivotXAuthored', g['pivotX']))
            frames.append(g)
        xs = VIDEO_ROOT_X[first - 1:last]
        root = [round((x - xs[0]) * facing * scale, 3) for x in xs]
        n = len(frames)
        anims[clip] = {
            'name': name, 'fps': 24.0, 'loop': False, 'holdLast': True, 'effectsBaked': True,
            'source': {'collection': 'desktop-actions-20261018', 'animation': '冲刺攻击', 'firstFrame': first, 'lastFrame': last},
            'sourceName': '冲刺攻击', 'sourceFrameStart': first - 1, 'sourceFrameEnd': last - 1, 'sourceDuration': n / 24.0,
            'timingSource': 'FrameBaker .frames.json', 'sourceTransformApplied': True,
            'sourceFacing': facing, 'runtimeCoordinateScale': 1.0,
            'runtimeAnchor': 'source root (pivotXAuthored) + video root motion',
            'rootMotionX': root, 'rootMotionSmooth': True, 'frames': frames,
        }
        m = next(m for m in cfg['moves'] if m['id'] == move_id)
        m['animation'] = clip
        m['name'] = name
        m['animationSpeed'] = 1
        m['syncAnimation'] = True
        m['activeFrameStart'], m['activeFrameEnd'] = active
        m['chainFrame'] = chain
        m['duration'] = n / 24.0
        m['activeStart'] = active[0] / 24.0
        m['activeEnd'] = (active[1] + 1) / 24.0
        m['chainOpen'] = chain / 24.0
        for k in ('startupSpeed', 'activeSpeed', 'recoverySpeed', 'tailSpeed'):
            m.pop(k, None)
        # 位移全部来自 rootMotionX；时间轴留两个零点（空数组会退回 dashDistance 匀速）
        m['movementTimeline'] = [{'time': 0, 'distance': 0}, {'time': 1, 'distance': 0}]
        m['dashDistance'] = 0
        m['hitstop'] = HITSTOP
        m['hitstopFirstOnly'] = True
        print(move_id, clip, n, 'frames, forward', root[-1], 'max', max(root))
    open(CFG, 'w', encoding='utf-8').write(json.dumps(cfg, ensure_ascii=False, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
