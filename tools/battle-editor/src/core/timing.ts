import type {JsonObject} from '../types';

function rate(clip: JsonObject, speed=1): number {
  const fps=Number(clip.fps), multiplier=Number(speed);
  return (Number.isFinite(fps)&&fps>0?fps:24)*(Number.isFinite(multiplier)&&multiplier>0?multiplier:1);
}
function ticks(frame: JsonObject): number {
  const value=Number(frame?.durationTicks??1);
  return Number.isFinite(value)&&value>0?value:1;
}
export function frameStartTime(clip:JsonObject,index:number,speed=1):number {
  return (clip.frames||[]).slice(0,Math.max(0,Math.floor(index))).reduce((sum:number,f:JsonObject)=>sum+ticks(f),0)/rate(clip,speed);
}
export function animationDuration(clip:JsonObject,speed=1):number {
  return frameStartTime(clip,(clip.frames||[]).length,speed);
}
export function frameTimeInCycle(clip:JsonObject,seconds:number,speed=1):number {
  const count=clip.frames?.length||0;
  if(!count)return 0;
  const total=animationDuration(clip,speed);
  const time=Math.max(0,Number.isFinite(seconds)?seconds:0);
  if(time+1e-9<total)return time;
  const start=frameStartTime(clip,Math.max(0,Math.min(count-1,Number(clip.loopFrame||0))),speed);
  return start+((time-start)%(total-start));
}
export function frameIndexAtTime(clip:JsonObject,seconds:number,speed=1,loop=true):number {
  const frames:JsonObject[]=clip.frames||[];
  if(!frames.length)return 0;
  const time=loop?frameTimeInCycle(clip,seconds,speed):Math.max(0,Number.isFinite(seconds)?seconds:0);
  let boundary=0;
  for(let i=0;i<frames.length;i++){
    boundary+=ticks(frames[i]!)/rate(clip,speed);
    if(time+1e-9<boundary)return i;
  }
  return frames.length-1;
}
export function clampMoveFrames(move:JsonObject,clip:JsonObject) {
  const last=Math.max(0,(clip.frames?.length||1)-1);
  move.activeFrameStart=Math.max(0,Math.min(last,Number(move.activeFrameStart)||0));
  move.activeFrameEnd=Math.max(move.activeFrameStart,Math.min(last,Number(move.activeFrameEnd)||0));
  move.chainFrame=Math.min(last+1,Math.max(move.activeFrameEnd+1,Number(move.chainFrame)||0));
}

export function syncTimings(config: JsonObject) {
  const animations = config.characters?.find((c: JsonObject) => c.id === 'player')?.sprite?.animations || {};
  for (const m of config.moves || []) {
    const clip = animations[m.animation];
    if (!m.syncAnimation || !clip?.frames?.length) continue;
    const speed=Number(m.animationSpeed||1);
    m.duration = animationDuration(clip,speed);
    m.activeStart = frameStartTime(clip,m.activeFrameStart,speed);
    m.activeEnd = frameStartTime(clip,m.activeFrameEnd+1,speed);
    m.chainOpen = frameStartTime(clip,m.chainFrame,speed);
  }
}
export const clipLabels: Record<string,string> = {idle:'待机',run:'跑步',jump:'起跳',fall:'下落',land:'落地',attack_1:'第一刀',attack_up:'上挑',attack_2:'第二刀',attack_3:'第三刀',feather_slash:'羽毛刀光'};
