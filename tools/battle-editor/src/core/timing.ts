import type {JsonObject} from '../types';
export function syncTimings(config: JsonObject) {
  const animations = config.characters?.find((c: JsonObject) => c.id === 'player')?.sprite?.animations || {};
  for (const m of config.moves || []) {
    const clip = animations[m.animation];
    if (!m.syncAnimation || !clip?.frames?.length) continue;
    const fps = Math.max(1, Number(clip.fps) * Number(m.animationSpeed || 1));
    m.duration = clip.frames.length / fps;
    m.activeStart = m.activeFrameStart / fps;
    m.activeEnd = (m.activeFrameEnd + 1) / fps;
    m.chainOpen = m.chainFrame / fps;
  }
}
export const clipLabels: Record<string,string> = {idle:'待机',run:'跑步',jump:'起跳',fall:'下落',land:'落地',attack_1:'第一刀',attack_up:'上挑',attack_2:'第二刀',attack_3:'第三刀',feather_slash:'羽毛刀光'};
