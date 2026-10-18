"""Bind the archived desktop batch to the shared Godot/editor configuration.

Run import_desktop_actions.py first. Source PNG pixels are never changed here;
runtime coordinate calibration, source ranges and mechanics live in battle.json.
"""
from pathlib import Path
import copy
import json

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'assets/data/battle.json'

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def main():
    patch = json.loads((ROOT/'.runtime/desktop-actions-patch.json').read_text(encoding='utf-8'))
    config = json.loads(CONFIG.read_text(encoding='utf-8-sig'))
    backup = ROOT/'assets/data/backups/before-desktop-actions-20261018.json'
    if not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(CONFIG.read_bytes())
    player = next(c for c in config['characters'] if c['id']=='player')
    sprite = player['sprite']
    sprite.update(copy.deepcopy(patch['sprite']))
    clips = sprite['animations']
    clean_path=ROOT/'.runtime/desktop-clean-map.json'
    if clean_path.exists():
        clean_rows=json.loads(clean_path.read_text(encoding='utf-8')).get('replacements',[])
    else:
        clean_report=ROOT/'docs/desktop-actions-cleanup.json'
        clean_rows=[{'source':row['source'],'asset':row['cleaned']} for row in json.loads(clean_report.read_text(encoding='utf-8')).get('frames',[]) if row.get('changed')] if clean_report.exists() else []
    clean_map={row['source'].removeprefix('assets/'):row['asset'].removeprefix('assets/') for row in clean_rows if (ROOT/row['asset']).is_file()}

    # Group factors are presentation coordinates only, never PNG resampling.
    ground = {'attack_1','attack_2','attack_3','attack_2_start','attack_2_recovery','strong_attack'}
    calibration = {}
    for key, clip in clips.items():
        if key.startswith('source_'):
            continue
        factor = 409/344 if key in ground else 409/982 if key=='fall' else 1.0
        stabilize = key in {'fall','jump','land','dash_left','dash_right'}
        for frame in clip['frames']:
            if frame.get('blank'):
                continue
            if stabilize:
                frame['pivotX'] += frame.get('sourceRootDeltaX',0)
                frame['pivotY'] += frame.get('sourceRootDeltaY',0)
            for field in ['width','height','pivotX','pivotY']:
                frame[field] = round(frame[field]*factor,5)
            if frame.get('asset') in clean_map:
                frame['runtimeOriginalAsset']=frame['asset']
                frame['asset']=clean_map[frame['asset']]
        clip['runtimeCoordinateScale'] = factor
        clip['runtimeAnchor'] = 'tracked visible feet' if stabilize else 'authored export origin'
        clip['sourceFacing'] = -1 if clip.get('sourceFacing') in [-1,'left'] else 1
        calibration[key] = {'scale':factor,'anchor':clip['runtimeAnchor']}
    for key in ['idle','run']:
        clips[key]['loop']=True
    clips['jump']['fullSequence']=False
    clips['fall']['loop']=True
    # The jump starts/lands facing left; its middle body turn is intentional.
    for key in ['jump','fall','land']:
        clips[key]['sourceFacing']=-1
    for key in ['turn_left_right','turn_right_left']:
        clips[key]['authoredTurn']=True

    def slice_source(name,start,end,title):
        original = next(c for k,c in clips.items() if k.startswith('source_') and c['sourceName']==name)
        result=copy.deepcopy(original)
        result['name']=title
        result['frames']=result['frames'][start:end+1]
        result.update(sourceFrameStart=start,sourceFrameEnd=end,sourceDuration=len(result['frames'])/result['fps'])
        result['source'].update(firstFrame=start+1,lastFrame=end+1)
        result['sourceFacing']=1
        return result

    # Idle defense uses clean preparation poses. Success clips run only after a hit.
    clips['guard_start']=slice_source('格挡_前组01',0,11,'格挡起架')
    clips['guard_start']['playDuringParry']=True
    clips['guard_hold']=slice_source('格挡_前组01',11,11,'持剑防守')
    clips['guard_hold']['loop']=True
    clips['guard_hold']['playDuringParry']=True
    clips['guard_hit_1']=slice_source('格挡_前组01',42,50,'第一种格挡反馈')
    clips['guard_hit_2']=slice_source('格挡_前组02',0,12,'第二种格挡反馈')
    clips['guard_hit_3']=slice_source('格挡_前组03',0,35,'第三种格挡反馈')
    for key in ['guard_hit_1','guard_hit_2','guard_hit_3','parry_react_1','parry_react_2','parry_react_3']:
        clips[key]['playDuringParry']=True
    aliases={'attack_up':'strong_attack','charge_slash':'strong_attack','air_slash':'air_attack_1','parry':'guard_start'}
    for alias,key in aliases.items():
        clips[alias]=copy.deepcopy(clips[key])
    names={'idle':'待机','run':'跑步','jump':'起跳','fall':'空中下坠','land':'落地',
           'turn_left_right':'左跑转向右跑','turn_right_left':'右跑转向左跑',
           'attack_1':'第一刀','attack_2':'第二刀','attack_3':'第三刀',
           'attack_2_start':'第二刀·带前摇候选','attack_2_recovery':'第二刀·带后摇候选',
           'strong_attack':'强化普攻·挑飞','attack_up':'强化普攻·挑飞','charge_slash':'蓄力挑飞',
           'air_attack_1':'空中第一刀','air_attack_2':'空中第二刀','air_attack_3':'空中第三刀','air_slash':'空中第一刀（兼容）',
           'dash_left':'向左冲刺斩','dash_right':'向右冲刺斩','draw':'拔刀','sheathe':'收刀','death':'死亡',
           'parry':'弹刀起架','guard_start':'格挡起架','guard_hold':'持续格挡'}
    for key,label in names.items():
        clips[key]['name']=label
    sprite.update(filter='linear',worldScale=1.0,chargeAnimation='charge_slash',chargeFrame=0,
                  idle=clips['idle']['frames'][0]['asset'],
                  locomotion={'enabled':True,'turnRight':{'animation':'turn_left_right','flipFrame':2,'cancelFrame':3},
                              'turnLeft':{'animation':'turn_right_left','flipFrame':2,'cancelFrame':3},'landingCancelFrame':3},
                  guard={'enabled':True,'parryWindowFrames':8,'startupAnimation':'guard_start',
                         'holdAnimation':'guard_hold','blockAnimation':'guard_hit_1','damageMultiplier':0.2,'movementScale':0.25},
                  airCombo={'maxSuspendFrames':180},
                  drawSheathe={'enabled':True,'drawAnimation':'draw','sheatheAnimation':'sheathe',
                               'idleDelay':4.0,'drawCancelFrame':5,'sheatheCancelFrame':0})
    sprite['preloadAnimations']=['idle','run','jump','fall','land','turn_left_right','turn_right_left',
                                'attack_1','attack_2','attack_3','strong_attack','air_attack_1','air_attack_2','air_attack_3',
                                'guard_start','guard_hold']
    # Native slow walk/run cycle gets a matching physical speed, not the old 450px/s slide.
    player.update(speed=170,jumpTimeToPeak=9/17,jumpTimeToDescent=0.48,jumpSpeed=2*170/(9/17))
    config['input'].update(dashAttack=['SHIFT+J'],guard=['L_HOLD'])
    source_moves={m['id']:copy.deepcopy(m) for m in config['moves']}
    bindings={
        'light_1':('attack_1',5,7,10,'第一刀'),
        'light_2':('attack_2',3,6,13,'第二刀'),
        'light_3':('attack_3',1,6,23,'第三刀 · 回旋终结'),
        'up_strike':('attack_up',8,11,21,'强化普攻 · 挑飞'),
        'charge_1':('charge_slash',8,11,21,'蓄力 · 强化挑飞'),
        'air_up':('air_slash',8,13,16,'空中旧指令兼容'),
        'parry_1':('parry',0,2,8,'弹刀起架（兼容）')}
    for move_id,(key,begin,end,chain,name) in bindings.items():
        m=source_moves[move_id]
        m.update(animation=key,animationSpeed=1.0,activeFrameStart=begin,activeFrameEnd=end,chainFrame=chain,
                 syncAnimation=True,effect='',name=name)
    source_moves['ranged_1'].update(animation='attack_1',effect='',syncAnimation=False)
    for i,(begin,end,chain) in enumerate([(8,13,16),(2,9,10),(0,6,18)],1):
        m=copy.deepcopy(source_moves['air_up'])
        key=f'air_attack_{i}'
        m.update(id=f'air_light_{i}',name=f'空中第{i}刀',input=f'AIR_J_{i}',animation=key,
                 activeFrameStart=begin,activeFrameEnd=end,chainFrame=chain,animationSpeed=1.0,
                 airGravityScale=0.12,airSuspendFrames=40 if i<3 else 50,upward=False,
                 damage=12 if i<3 else 18,launchY=160 if i<3 else 260,forcesLaunch=False,
                 movementSpeedMultiplier=0.6,syncAnimation=True,effect='')
        source_moves[m['id']]=m
    for key,move_id,source_facing in [('dash_right','dash_slash',1),('dash_left','dash_slash_left',-1)]:
        m=copy.deepcopy(source_moves['light_3'])
        clip=clips[key]
        roots=[float(f.get('sourceRootX',0)) for f in clip['frames']]
        # Use the source path as a bounded monotonic motion envelope, then normalize to arena distance.
        progression=[max(0,(x-roots[0])*source_facing) for x in roots]
        running=0.0
        for i,value in enumerate(progression):
            running=max(running,value)
            progression[i]=running
        distance=210.0
        if progression[-1]>1:
            curve=[{'time':round(i/(len(roots)-1),6),'distance':round(value/progression[-1]*distance,4)} for i,value in enumerate(progression)]
        else:
            curve=[{'time':0,'distance':0},{'time':0.12,'distance':0},{'time':0.55,'distance':distance},{'time':1,'distance':distance}]
        m.update(id=move_id,name='向右冲刺斩' if source_facing>0 else '向左冲刺斩',animation=key,input='SHIFT+J',
                 activeFrameStart=6 if source_facing>0 else 5,activeFrameEnd=12 if source_facing>0 else 11,
                 chainFrame=len(roots)-2,movementTimeline=curve,dashDistance=distance,
                 animationSpeed=1.0,syncAnimation=True,effect='',damage=20)
        source_moves[move_id]=m
    for prefix in ['guard_hit','parry_react']:
        for i in range(1,4):
            key=f'{prefix}_{i}'
            clip=clips[key]
            m=copy.deepcopy(source_moves['parry_1'])
            m.update(id=key,name=('格挡反馈' if prefix=='guard_hit' else '成功弹刀')+str(i),
                     animation=key,input='GUARD_HIT' if prefix=='guard_hit' else 'PARRY_SUCCESS',
                     activeFrameStart=0,activeFrameEnd=0,chainFrame=max(1,len(clip['frames'])-2),
                     damage=0,knockbackX=0,launchY=0,forcesLaunch=False,movementSpeedMultiplier=0.25)
            source_moves[key]=m
    config['moves']=list(source_moves.values())
    for m in config['moves']:
        clip=clips.get(m.get('animation'))
        if not clip or not m.get('syncAnimation'):
            continue
        fps=clip['fps']*m.get('animationSpeed',1)
        before=lambda boundary:sum(f.get('durationTicks',1) for f in clip['frames'][:boundary])/fps
        m.update(duration=before(len(clip['frames'])),activeStart=before(m['activeFrameStart']),
                 activeEnd=before(m['activeFrameEnd']+1),chainOpen=before(m['chainFrame']))
    config['metadata']['description']='桌面手调24组动作：转向跑跳、地面三连、空中三连、双向冲刺、格挡弹刀与拔收刀。'
    config['metadata']['activeArtCollection']='desktop-actions-20261018'
    save(CONFIG,config)
    save(ROOT/'docs/desktop-actions-bindings.json',{'collection':'desktop-actions-20261018','sourcePngs':734,
        'sourceDirectories':24,'animations':len(clips),'runtimeCalibration':calibration,
        'bindings':{m['id']:{'animation':m['animation'],'input':m.get('input'),'duration':m.get('duration')} for m in config['moves']}})
    print(f'BOUND {len(clips)} clips / {len(config["moves"])} moves, original 734 PNG preserved')

if __name__=='__main__':
    main()
