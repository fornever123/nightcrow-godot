<script setup lang="ts">
import {computed} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import type {AssetFile,JsonObject} from '../types';
const props=defineProps<{config:JsonObject;assets:AssetFile[]}>();
const emit=defineEmits<{changed:[]}>();
const sounds=computed(()=>props.assets.filter(a=>a.kind==='audio'));
const events={swing:'挥剑',blade_hit:'刀刃命中',launch:'重击击飞',wall:'撞击',parry:'弹刀成功',jump:'跳跃',land:'落地',charge_start:'开始蓄力',charge_release:'释放蓄力',shuriken_throw:'远射发出',shuriken_hit:'远射命中'};
</script>
<template>
  <div class="studio-layout">
    <PanelShell title="整体打击感" eyebrow="命中反馈" description="挥空不停顿。命中后角色和木桩各自停顿，下一刀输入仍然能提前接收。">
      <div class="field-grid">
        <EditorField label="命中停顿倍率" type="number" :model-value="config.feedback.hitstopMultiplier??1" min="0" max="3" step="0.1" @update="config.feedback.hitstopMultiplier=$event" @changed="emit('changed')"/>
        <EditorField label="震屏倍率（C 盘原版为 1.55）" type="number" :model-value="config.feedback.shakeMultiplier??1.55" min="0" max="3" step="0.1" @update="config.feedback.shakeMultiplier=$event" @changed="emit('changed')"/>
        <EditorField label="命中、撞击与落地特效" type="checkbox" :model-value="config.feedback.effectsEnabled" @update="config.feedback.effectsEnabled=$event" @changed="emit('changed')"/>
        <EditorField label="角色挤压强度（0 保持原画）" type="number" :model-value="config.feedback.squashStrength??0.35" min="0" max="1" step="0.05" @update="config.feedback.squashStrength=$event" @changed="emit('changed')"/>
        <EditorField label="弹刀成功停顿（秒）" type="number" :model-value="config.feedback.parryHitstop??0.05" min="0" max="0.5" step="0.01667" @update="config.feedback.parryHitstop=$event" @changed="emit('changed')"/>
        <EditorField label="显示伤害数字" type="checkbox" :model-value="config.ui.showDamageNumbers" @update="config.ui.showDamageNumbers=$event" @changed="emit('changed')"/>
        <EditorField label="显示连击与浮空次数" type="checkbox" :model-value="config.ui.showComboCounter" @update="config.ui.showComboCounter=$event" @changed="emit('changed')"/>
      </div>
      <p class="notice">木桩不会主动攻击；L 的招架窗口和弹刀机制已保留。单招的角色顿帧、木桩顿帧与震屏强度在“战斗参数”中设置。</p>
    </PanelShell>
    <PanelShell title="镜头震屏" eyebrow="轻击 / 重击 / 撞击">
      <div class="field-grid">
        <EditorField label="震屏回稳速度（越大越快）" type="number" :model-value="config.camera.shakeDecay??7" min="1" max="30" step="0.5" @update="config.camera.shakeDecay=$event" @changed="emit('changed')"/>
        <EditorField label="最大震屏幅度" type="number" :model-value="config.camera.maxShake??42" min="0" max="80" step="1" @update="config.camera.maxShake=$event" @changed="emit('changed')"/>
      </div>
      <p class="notice">上挑向上震，普通攻击顺着击退方向震。重击、撞击更强；远射使用较轻的震屏。</p>
    </PanelShell>
    <PanelShell title="战斗音效" eyebrow="C 盘音效已接入" description="命中、弹刀、撞击、蓄力、远射和跳跃使用各自的声音。">
      <div class="field-grid">
        <EditorField label="开启战斗音效" type="checkbox" :model-value="config.audio.enabled??true" @update="config.audio.enabled=$event" @changed="emit('changed')"/>
        <EditorField label="总音量" type="number" :model-value="config.audio.masterVolume" min="0" max="1" step="0.05" @update="config.audio.masterVolume=$event" @changed="emit('changed')"/>
        <EditorField label="音效音量" type="number" :model-value="config.audio.sfxVolume" min="0" max="1" step="0.05" @update="config.audio.sfxVolume=$event" @changed="emit('changed')"/>
        <label v-for="(label,key) in events" :key="key" class="editor-field"><span>{{label}}音效</span><select v-model="config.audio.events[key]" @change="emit('changed')"><option value="">使用默认音效</option><option v-for="sound in sounds" :key="sound.path" :value="sound.path">{{sound.path.replace('audio/','')}}</option></select></label>
      </div>
      <p class="notice">可以在“素材工坊”试听、裁剪或导入声音，再在这里选择；保存后游戏生效。</p>
    </PanelShell>
    <PanelShell title="即时应用" eyebrow="保存到 GODOT">
      <EditorField label="保存后自动应用并重置训练场" type="checkbox" :model-value="config.runtime.autoReload" @update="config.runtime.autoReload=$event" @changed="emit('changed')"/>
      <p class="notice">关闭自动应用后，需关掉游戏重新打开。刀光消散速度在“动作工坊 → 刀光特效”中设置。</p>
    </PanelShell>
  </div>
</template>
