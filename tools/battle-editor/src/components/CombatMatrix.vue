<script setup lang="ts">
import {computed} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import {syncTimings} from '../core/timing';
import type {JsonObject} from '../types';
const props=defineProps<{config:JsonObject;selectedIndex?:number}>();
const emit=defineEmits<{changed:[];selected:[index:number]}>();
const current=computed(()=>props.config.moves?.[props.selectedIndex||0]||{});
const clips=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='player')?.sprite?.animations||{});
function change(){syncTimings(props.config);emit('changed');}
function seconds(m:JsonObject){return m.syncAnimation?(clips.value[m.animation]?.frames.length||0)/(Number(clips.value[m.animation]?.fps||36)*Number(m.animationSpeed||1)):m.duration;}
function frame(key:string,e:Event){current.value[key]=Math.max(0,Number((e.target as HTMLInputElement).value)-1);change();}
</script>
<template>
  <div>
    <PanelShell title="战斗参数总表" eyebrow="C 盘战斗 · E 盘动作" description="招式速度和动作同步；数值改完后点顶部保存。灰色字段对应固定基础输入，不需要编程。">
      <div class="matrix-scroll"><table class="combat-matrix"><thead><tr><th>招式</th><th>伤害</th><th>动作速度</th><th>完整时长</th><th>角色命中停顿</th><th>水平击退</th><th>向上击飞</th></tr></thead><tbody><tr v-for="(m,i) in config.moves" :key="m.id" :class="{selected:Number(i)===(selectedIndex||0)}" @click="emit('selected',Number(i))"><td>{{m.name}}</td><td><input type="number" v-model.number="m.damage" min="0" @change="change"></td><td><input type="number" v-model.number="m.animationSpeed" min="0.25" max="3" step="0.05" :disabled="!m.syncAnimation" @change="change"></td><td>{{seconds(m).toFixed(3)}} 秒</td><td><input type="number" v-model.number="m.hitstop" min="0" max="0.5" step="0.01667" @change="change"></td><td><input type="number" v-model.number="m.knockbackX" @change="change"></td><td><input type="number" v-model.number="m.launchY" @change="change"></td></tr></tbody></table></div>
    </PanelShell>
    <div class="studio-layout" v-if="current.id">
      <PanelShell :title="current.name+' · 出刀时间'" eyebrow="攻击窗口">
        <p class="notice">第几帧开始能打中、第几帧结束、第几帧允许接下一招。显示从第 1 帧开始计数。</p>
        <div class="field-grid"><label class="editor-field"><span>对应角色动作</span><select v-model="current.animation" @change="change"><option v-for="(_,name) in clips" :key="name" :value="name">{{name}}</option></select></label><EditorField label="按动作帧同步" type="checkbox" :model-value="current.syncAnimation" @update="current.syncAnimation=$event" @changed="change"/></div>
        <div v-if="current.syncAnimation" class="field-grid"><label v-for="(label,key) in {activeFrameStart:'开始命中帧',activeFrameEnd:'结束命中帧',chainFrame:'允许接招帧'}" :key="key" class="editor-field"><span>{{label}}</span><input type="number" :value="Number(current[key])+1" min="1" :max="(clips[current.animation]?.frames.length||1)+(key==='chainFrame'?1:0)" @change="frame(key,$event)"></label></div>
        <div v-else class="field-grid"><EditorField v-for="(label,key) in {duration:'完整时长（秒）',activeStart:'开始生效（秒）',activeEnd:'结束生效（秒）',chainOpen:'允许接招（秒）'}" :key="key" :label="label" type="number" :model-value="current[key]" min="0" step="0.01667" @update="current[key]=$event" @changed="change"/></div>
        <p class="notice">预备 {{current.activeStart?.toFixed(3)}} 秒 → 生效 {{(current.activeEnd-current.activeStart).toFixed(3)}} 秒 → 收刀 {{Math.max(0,seconds(current)-current.activeEnd).toFixed(3)}} 秒。命中停顿另计。</p>
      </PanelShell>
      <PanelShell title="攻击范围与手感" eyebrow="实际游戏判定">
        <div class="field-grid"><EditorField v-for="(label,key) in {x:'攻击框中心 X',y:'攻击框中心 Y（脚底为 0）',width:'攻击框宽度',height:'攻击框高度'}" :key="key" :label="label" type="number" :model-value="current.hitbox[key]" @update="current.hitbox[key]=$event" @changed="change"/><EditorField label="木桩命中停顿（秒）" type="number" :model-value="current.victimHitstop" min="0" max="0.5" step="0.01667" @update="current.victimHitstop=$event" @changed="change"/><EditorField label="受击硬直（秒）" type="number" :model-value="current.hitstun" min="0" step="0.01667" @update="current.hitstun=$event" @changed="change"/><EditorField label="出招移动倍率" type="number" :model-value="current.movementSpeedMultiplier" min="0" max="2" step="0.05" @update="current.movementSpeedMultiplier=$event" @changed="change"/><EditorField label="出刀前冲力度" type="number" :model-value="current.lunge" min="0" @update="current.lunge=$event" @changed="change"/><EditorField label="震屏强度" type="number" :model-value="current.shakeAmount" min="0" @update="current.shakeAmount=$event" @changed="change"/><EditorField label="撞墙伤害系数" type="number" :model-value="current.wallDamageFactor" min="0" step="0.1" @update="current.wallDamageFactor=$event" @changed="change"/><EditorField label="强制击飞" type="checkbox" :model-value="current.forcesLaunch" @update="current.forcesLaunch=$event" @changed="change"/></div>
        <div v-if="current.id==='charge_1'" class="field-grid"><EditorField label="最短蓄力（秒）" type="number" :model-value="current.minHold" min="0" step="0.05" @update="current.minHold=$event" @changed="change"/><EditorField label="最大蓄力（秒）" type="number" :model-value="current.maxHold" min="0.05" step="0.05" @update="current.maxHold=$event" @changed="change"/><EditorField label="满蓄力伤害倍率" type="number" :model-value="current.chargeDamageBonus" min="1" step="0.1" @update="current.chargeDamageBonus=$event" @changed="change"/><EditorField label="满蓄力击退倍率" type="number" :model-value="current.chargeKnockbackBonus" min="1" step="0.1" @update="current.chargeKnockbackBonus=$event" @changed="change"/><EditorField label="满蓄力额外顿帧（秒）" type="number" :model-value="current.chargeHitstopBonus??0.1" min="0" max="0.5" step="0.01667" @update="current.chargeHitstopBonus=$event" @changed="change"/></div>
        <div v-if="current.id==='ranged_1'" class="field-grid"><EditorField label="弹丸速度" type="number" :model-value="current.projectile.speed" min="1" @update="current.projectile.speed=$event" @changed="change"/><EditorField label="弹丸存在时长（秒）" type="number" :model-value="current.projectile.life" min="0.05" step="0.05" @update="current.projectile.life=$event" @changed="change"/></div>
      </PanelShell>
    </div>
  </div>
</template>
