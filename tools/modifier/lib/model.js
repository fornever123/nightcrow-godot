/* 同时供 Node 服务、浏览器和回归测试使用；无依赖。 */
(function (target, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else target.Modifier = api;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';
  const phases = ['startup', 'active', 'recovery', 'tail'];
  const clone = value => JSON.parse(JSON.stringify(value));
  const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
  function resolve(documents, path) {
    return path.split('/').reduce((at,key) => Array.isArray(at) ? at.find(x => x && (x.id === key || x.name === key)) : at && Object.hasOwn(at,key) ? at[key] : undefined, documents);
  }
  function setPath(at, path, value) {
    const parts=path.split('/');
    for (const key of parts.slice(0,-1)) { if (!at[key] || typeof at[key] !== 'object') at[key]={}; at=at[key]; }
    at[parts.at(-1)]=value;
  }
  function ticksBefore(frames,n) {
    return frames.slice(0,Math.max(0,Math.trunc(n))).reduce((sum,f)=>sum+(typeof f.durationTicks==='number' && Number.isFinite(f.durationTicks) && f.durationTicks>0 ? f.durationTicks : 1),0);
  }
  function timingFor(battle,source) {
    const actor=(battle.characters||[]).find(x=>x.id==='player')||{};
    const clip=actor.sprite?.animations?.[source.animation||'idle'];
    const fps=(clip?.fps ?? 36)*(source.animationSpeed ?? 1);
    let duration=source.duration ?? .5, start=source.activeStart ?? .08, end=source.activeEnd ?? .16, chain=source.chainOpen ?? end;
    let burst=null;
    if(source.syncAnimation && clip) {
      const f=clip.frames||[];
      duration=ticksBefore(f,f.length)/fps; start=ticksBefore(f,source.activeFrameStart??2)/fps;
      end=ticksBefore(f,(source.activeFrameEnd??12)+1)/fps; chain=ticksBefore(f,source.chainFrame??f.length)/fps;
    }
    if(clip && source.burstFrameStart!==undefined) burst={start:ticksBefore(clip.frames||[],source.burstFrameStart)/fps,end:ticksBefore(clip.frames||[],source.burstFrameEnd??clip.frames.length)/fps};
    return {raw:{duration,start,end,chain},settings:{startupSpeedMultiplier:battle.settings?.startupSpeedMultiplier??1,recoverySpeedMultiplier:battle.settings?.recoverySpeedMultiplier??1},burst};
  }
  function normalized(timing) {
    let {duration,start,end,chain}=timing.raw;
    end=Math.max(end,start);chain=Math.max(end,Math.min(chain,Math.max(duration,end)));duration=Math.max(duration,chain);
    return {duration,start,end,chain};
  }
  function phaseSeconds(timing) { const r=normalized(timing);return {startup:r.start,active:r.end-r.start,recovery:r.chain-r.end,tail:r.duration-r.chain}; }
  function phaseEditable(timing,phase) { return phaseSeconds(timing)[phase] > .000001; }
  function effectiveSpeeds(timing,source) {
    const a=timing.settings?.startupSpeedMultiplier??1, b=timing.settings?.recoverySpeedMultiplier??1;
    return [(source.startupSpeed??1)*a,source.activeSpeed??1,(source.recoverySpeed??1)*b,(source.tailSpeed??source.recoverySpeed??1)*b].map(x=>Math.max(x,.05));
  }
  function frames(timing,source={}) {
    const speed=effectiveSpeeds(timing,source), timed=speed.some(x=>Math.abs(x-1)>.0001);
    const ceil=x=>Math.ceil(x*60-.0001);
    let {duration,start,end,chain}=timed?normalized(timing):timing.raw;
    let s,e,c,t;
    if(timed) {
      s=Math.max(0,ceil(start/speed[0]));e=Math.max(s+1,s+ceil((end-start)/speed[1]));
      c=e+Math.max(0,ceil((chain-end)/speed[2]));t=Math.max(e+1,c+ceil((duration-chain)/speed[3]));
    } else {
      s=Math.max(0,ceil(start));e=Math.max(s+1,ceil(end));t=e+Math.max(1,ceil(duration)-e);c=e+Math.max(0,ceil(chain)-e);
    }
    const burstSpeed=Math.max(source.burstSpeed??1,.05);
    if(Math.abs(burstSpeed-1)>.0001 && timing.burst) {
      ({duration,start,end,chain}=normalized(timing));
      const base=[start,end,chain,duration], {start:b0,end:b1}=timing.burst;
      const ts=[...new Set([0,...base,b0,b1].map(x=>Math.max(0,Math.min(x,duration))))].sort((a,b)=>a-b);
      const at=new Map();let acc=0,last=0;
      for(let i=1;i<ts.length;i++) { const lo=ts[i-1],hi=ts[i],mid=(lo+hi)/2;let seg=base.findIndex(x=>mid<x);if(seg<0)seg=3;
        acc+=(hi-lo)/((timed?speed[seg]:1)*(mid>b0&&mid<b1?burstSpeed:1))*60;
        last=Math.max(last,Math.ceil(acc-.0001));at.set(hi,last);
      }
      s=at.get(start)??0;e=Math.max(s+1,at.get(end)??s+1);c=Math.max(e,at.get(chain)??e);t=Math.max(e+1,at.get(duration)??c);
    }
    return {startup:s,active:e-s,recovery:c-e,tail:t-c,total:t};
  }
  function speedForFrames(timing,phase,n) {
    if(!Number.isInteger(n)||n<1) throw Error('阶段帧数必须是正整数');
    if(!phaseEditable(timing,phase)) throw Error('这招没有这一段');
    const multiplier=phase==='startup'?(timing.settings?.startupSpeedMultiplier??1):['recovery','tail'].includes(phase)?(timing.settings?.recoverySpeedMultiplier??1):1;
    const speed=phaseSeconds(timing)[phase]*60/n;
    if(speed<.05 || multiplier<=0) throw Error('此帧数受游戏最低播放速度限制');
    return (Math.abs(speed-1)<=.0001 ? speed*1.0002 : speed)/multiplier;
  }
  const sceneFields=['platforms','blocks','slopes','spawns','lamps','foreground','art'];
  function pieceMeta(piece,mirror) {
    if(!mirror)return piece;
    const w=piece.w;
    return {...piece,attach:[w-piece.attach[1],w-piece.attach[0]],stand:piece.stand.map(([a,b,y,s])=>[w-b,w-a,y,s]),blocks:piece.blocks.map(([a,b,y,s])=>[w-b,w-a,y,s]),slopes:(piece.slopes||[]).map(([a,ya,b,yb,s])=>[w-b,yb,w-a,ya,s]),lamps:piece.lamps.map(([x,y,k,r])=>[w-x,y,k,r])};
  }
  // 把方案摊平：每件都有明确的 x、上下偏移 y、前后 z；接缝上的石挑台也变成普通的件。摆法和 rain_kit_compose.py 一致。
  function normalizePlan(plan,pieces) {
    const items=[];let cursor=null;
    plan.items.forEach((it,n)=>{const meta=pieceMeta(pieces[it.piece],it.mirror);const x=it.x!==undefined?Number(it.x):cursor;const left=x-meta.attach[0];cursor=left+meta.attach[1];items.push({piece:it.piece,x:Math.round(x*10)/10,y:Number(it.y||0),z:it.z??n,mirror:!!it.mirror});});
    if(plan.join_ledges){const lp=pieces[plan.join_ledges.piece];const places=items.map(it=>({it,meta:pieceMeta(pieces[it.piece],it.mirror)}));for(let i=0;i+1<places.length;i++){const a=places[i],b=places[i+1];if(a.meta.seam&&b.meta.seam){const jx=a.it.x-a.meta.attach[0]+a.meta.attach[1];const left=jx-lp.w/2;items.push({piece:plan.join_ledges.piece,x:Math.round((left+lp.attach[0])*10)/10,y:Number(plan.join_ledges.y)-lp.stand[0][2],z:1000,mirror:false});}}}
    const out={index:plan.index,x0:plan.x0,x1:plan.x1,items};
    if(plan.y0!==undefined)out.y0=plan.y0;
    if(plan.reflections)out.reflections=plan.reflections;
    return out;
  }
  function createModel(catalog,documents) {
    const items=[],defaults={},issues=[];
    const moves=(documents.battle.moves||[]).map(source=> { const meta=catalog.pages.find(p=>p.template==='moves')?.moves.find(x=>x.id===source.id)||{};
      const timing=timingFor(documents.battle,source);return {...meta,id:source.id,label:meta.label||source.name||source.id,source:clone(source),timing,frames:frames(timing,source)};
    });
    const allowed=(rule,id)=> (!rule.only||rule.only.includes(id))&&(!rule.exclude||!rule.exclude.includes(id));
    for(const page of catalog.pages) {
      if(page.template==='waves') {defaults[page.path]=clone(resolve(documents,page.path));continue;}
      const entities=page.template==='moves'?page.moves:page.template==='enemies'?page.kinds:[{id:null}];
      for(const entity of entities) for(const section of page.sections||[]) {
        if(!allowed(section,entity.id))continue;
        for(const item of section.items||[]) {
          if(!allowed(item,entity.id)||(item.excludeBurst&&entity.burst))continue;
          const prefix=page.template==='moves'?'battle/moves/'+entity.id+'/':page.template==='enemies'?'encounters/kinds/'+entity.id+'/':'';
          const path=item.path||prefix+(item.phase?item.phase+'Speed':item.key);
          let value=resolve(documents,path);
          if(item.phase) value=value??(item.phase==='tail'?resolve(documents,prefix+'recoverySpeed')??1:1);
          else if(value===undefined) value=item.default;
          if(value===undefined) {issues.push({path,message:'字段缺失且清单未给默认值，按规则隐藏'});continue;}
          defaults[path]=clone(value);items.push({...item,path,pageId:page.id,entityId:entity.id,sectionTitle:section.title,defaultValue:clone(value)});
          for(const linked of entity.linked||[]) { const linkedPath=path.replace('/'+entity.id+'/','/'+linked+'/');const v=resolve(documents,linkedPath)??item.default;if(v!==undefined)defaults[linkedPath]=clone(v);else issues.push({path:linkedPath,message:'关联招式缺少默认值'}); }
        }
      }
    }
    // 场景：每段的地形和拼接方案整块存，远层按键存。
    for(const section of documents.layout?.sections||[]) for(const field of sceneFields) defaults['layout/sections/'+section.name+'/'+field]=clone(section[field]??(field==='art'?{}:[]));
    for(const [index,plan] of Object.entries(documents.scene?.plan||{})) defaults['scene/plan/'+index]=clone(plan);
    const scenePage=catalog.pages.find(p=>p.template==='scene');
    if(documents.layout) for(const [path,value] of Object.entries(scenePage?.defaults||{})) defaults[path]=clone(value);
    // 分段速度的四个字段均允许；没有阶段面板的招式不扩大写入范围。
    for(const entity of catalog.pages.find(p=>p.template==='moves')?.moves||[]) if(!entity.burst) for(const id of [entity.id,...entity.linked||[]]) for(const phase of phases) {
      const path='battle/moves/'+id+'/'+phase+'Speed';defaults[path]=resolve(documents,path)??(phase==='tail'?resolve(documents,'battle/moves/'+id+'/recoverySpeed')??1:1);
    }
    return {catalog,items,defaults,moves,issues};
  }
  function moveSource(state,values,id) { const source=clone(state.moves.find(m=>m.id===id).source),prefix='battle/moves/'+id+'/';for(const [p,v] of Object.entries(values)) if(p.startsWith(prefix))setPath(source,p.slice(prefix.length),clone(v));return source; }
  function moveFrames(state,values,id) { const move=state.moves.find(x=>x.id===id);return frames(move.timing,moveSource(state,values,id)); }
  function displayValue(state,values,item) {
    if(item.phase) return moveFrames(state,values,item.entityId)[item.phase];
    const value=values[item.path]??item.defaultValue;
    // 换算出来的数（秒→帧、比例→百分比、跳跃高度）只留三位小数，免得界面上出现 7.9998 帧。
    const tidy=x=>Math.round(x*1000)/1000;
    if(item.derive==='jumpHeight') { const p=item.path.replace(/jumpSpeed$/,'jumpTimeToPeak');return tidy(value*(values[p]??state.defaults[p])*.5); }
    return item.type==='bool'?value:item.scale?tidy(value*item.scale):value;
  }
  function put(state,values,path,value) {
    const match=path.match(/^battle\/moves\/([^/]+)\/tailSpeed$/);
    const source=match?state.moves.find(move=>move.id===match[1])?.source:null;
    const recoveryPath=match?'battle/moves/'+match[1]+'/recoverySpeed':null;
    const needsExplicitTail=source && source.tailSpeed===undefined && (values[recoveryPath]??source.recoverySpeed??1)!==(source.recoverySpeed??1);
    if(equal(value,state.defaults[path])&&!needsExplicitTail)delete values[path];else values[path]=value;
  }
  function editValues(state,values,item,display) {
    const next=clone(values);
    if(item.phase) {
      const move=state.moves.find(x=>x.id===item.entityId),source=moveSource(state,values,move.id),current=frames(move.timing,source);
      if(display===current[item.phase])return next;
      // 显式固定四个速度，避免 recovery 的缺省值连带改变 tail。
      for(const phase of phases) {
        const path='battle/moves/'+move.id+'/'+phase+'Speed';
        const n=phase===item.phase?display:current[phase];
        put(state,next,path,phaseEditable(move.timing,phase)&&n>0?speedForFrames(move.timing,phase,n):source[phase+'Speed']??state.defaults[path]);
      }
      // 在接近全 1 的边界选择略快的等价速度，确保仍走分段公式。
      if(!effectiveSpeeds(move.timing,moveSource(state,next,move.id)).some(x=>Math.abs(x-1)>.0001)) {
        const path=item.path;put(state,next,path,(next[path]??state.defaults[path])*1.0002);
      }
      if(moveFrames(state,next,move.id)[item.phase]!==display)throw Error('这个阶段帧数无法按游戏规则精确表示');
      return next;
    }
    let value=display;
    if(item.type!=='bool') { if(!Number.isFinite(display))throw Error('请输入有限数字');
      if(item.derive==='jumpHeight') {const p=item.path.replace(/jumpSpeed$/,'jumpTimeToPeak'),peak=values[p]??state.defaults[p];if(peak<=0)throw Error('升到最高点的时间必须大于 0');value=display*2/peak;}
      else value=display/(item.scale??1);
    }
    put(state,next,item.path,value);
    const move=state.catalog.pages.find(p=>p.id===item.pageId)?.moves?.find(m=>m.id===item.entityId);
    for(const id of move?.linked||[]) {const p=item.path.replace('/'+move.id+'/','/'+id+'/');if(!Object.hasOwn(state.defaults,p))continue;put(state,next,p,item.type==='bool'||item.defaultValue===0?value:state.defaults[p]*value/item.defaultValue);}
    return next;
  }
  function resetValue(state,values,item) {
    if(item.phase) return resetPhase(state,values,item);
    const next=clone(values);delete next[item.path];
    const move=state.catalog.pages.find(p=>p.id===item.pageId)?.moves?.find(m=>m.id===item.entityId);
    for(const id of move?.linked||[])delete next[item.path.replace('/'+move.id+'/','/'+id+'/')];
    return next;
  }
  // 帧数编辑会显式写四个速度。恢复一段时回到默认帧数；四段都回到默认就把四个速度全删掉，不留残余。
  function resetPhase(state,values,item) {
    const id=item.entityId,paths=phases.map(phase=>'battle/moves/'+id+'/'+phase+'Speed');
    const defaults=moveFrames(state,{},id),without=clone(values);paths.forEach(path=>delete without[path]);
    const next=defaults[item.phase]===moveFrames(state,values,id)[item.phase]?clone(values):editValues(state,values,item,defaults[item.phase]);
    const same=phases.every(phase=>moveFrames(state,next,id)[phase]===defaults[phase]);
    return same?without:next;
  }
  return {pieceMeta,normalizePlan,sceneFields,phases,resolve,ticksBefore,timingFor,phaseSeconds,phaseEditable,frames,speedForFrames,createModel,moveSource,moveFrames,displayValue,editValues,resetValue};
});
