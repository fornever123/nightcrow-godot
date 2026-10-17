<script setup lang="ts">
import {computed} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import type {AssetFile,JsonObject} from '../types';
const props=defineProps<{config:JsonObject;assets:AssetFile[];selectedIndex?:number}>();
const emit=defineEmits<{changed:[];selected:[index:number]}>();
const actor=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='player'));
const dummy=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='dummy'));
</script>
<template><div class="studio-layout" v-if="actor&&dummy">
  <PanelShell title="夜鸦角色" eyebrow="只保留 E 盘角色" description="原始显示高度 168；动作素材请在动作工坊调整。">
    <div class="field-grid"><EditorField label="跑动速度" type="number" :model-value="actor.speed" min="1" @update="actor.speed=$event" @changed="emit('changed')"/><EditorField label="起步加速度" type="number" :model-value="actor.acceleration" min="1" @update="actor.acceleration=$event" @changed="emit('changed')"/><EditorField label="空中转向强度" type="number" :model-value="actor.airControl" min="0" max="1" step="0.05" @update="actor.airControl=$event" @changed="emit('changed')"/><EditorField label="跳跃力度" type="number" :model-value="actor.jumpSpeed" min="1" @update="actor.jumpSpeed=$event" @changed="emit('changed')"/><EditorField label="跳跃次数" type="number" :model-value="actor.maxJumps" min="1" max="6" @update="actor.maxJumps=$event" @changed="emit('changed')"/><EditorField label="上升时长（秒）" type="number" :model-value="actor.jumpTimeToPeak" min="0.05" step="0.01" @update="actor.jumpTimeToPeak=$event" @changed="emit('changed')"/><EditorField label="下落时长（秒）" type="number" :model-value="actor.jumpTimeToDescent" min="0.05" step="0.01" @update="actor.jumpTimeToDescent=$event" @changed="emit('changed')"/><EditorField label="显示倍率（1 = 168 高）" type="number" :model-value="actor.sprite.displayScale" min="0.25" max="3" step="0.05" @update="actor.sprite.displayScale=$event" @changed="emit('changed')"/></div>
  </PanelShell>
  <PanelShell title="训练木桩" eyebrow="战斗测试">
    <div class="field-grid"><EditorField label="木桩血量" type="number" :model-value="dummy.maxHp" min="1" @update="dummy.maxHp=$event" @changed="emit('changed')"/><EditorField label="连段输入保留帧数（60 帧 = 1 秒）" type="number" :model-value="config.runtime.attackBufferFrames" min="1" max="64" @update="config.runtime.attackBufferFrames=$event" @changed="emit('changed')"/><EditorField label="长按多少帧认定蓄力" type="number" :model-value="config.runtime.holdToChargeFrames" min="3" max="60" @update="config.runtime.holdToChargeFrames=$event" @changed="emit('changed')"/><EditorField label="两次出招间的连段保留帧数" type="number" :model-value="config.runtime.comboKeepFrames" min="1" max="180" @update="config.runtime.comboKeepFrames=$event" @changed="emit('changed')"/></div>
    <p class="notice">木桩有击退、击飞、撞墙和血量反馈；不会还手。游戏按 R 可立即重置训练。</p>
  </PanelShell>
</div></template>
