<script setup lang="ts">
import {computed} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import type {AssetFile,JsonObject} from '../types';
const props=defineProps<{config:JsonObject;assets:AssetFile[];selectedIndex?:number}>();
const emit=defineEmits<{changed:[];selected:[index:number]}>();
const actor=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='player'));
const dummy=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='dummy'));
const animations=computed(()=>actor.value?.sprite?.animations||{});
const movement=computed(()=>actor.value?.sprite?.locomotion||{});
const guard=computed(()=>actor.value?.sprite?.guard||{});
const drawSheathe=computed(()=>actor.value?.sprite?.drawSheathe||{});
const airCombo=computed(()=>actor.value?.sprite?.airCombo||{});
function setSpriteSetting(group:string,key:string,value:unknown){
  const sprite=actor.value.sprite;
  sprite[group]??={};
  sprite[group][key]=value;
  emit('changed');
}
function setInput(key:string,event:Event){
  const value=(event.target as HTMLInputElement).value;
  props.config.input??={};
  props.config.input[key]=value.split(',').map((token:string)=>token.trim().toUpperCase()).filter(Boolean);
  emit('changed');
}
function inputText(key:string){return (props.config.input?.[key]||[]).join(', ');}
</script>
<template><div class="studio-layout" v-if="actor&&dummy">
  <PanelShell title="夜鸦角色" eyebrow="只保留 E 盘角色" description="原始显示高度 168；动作素材请在动作工坊调整。">
    <div class="field-grid"><EditorField label="跑动速度" type="number" :model-value="actor.speed" min="1" @update="actor.speed=$event" @changed="emit('changed')"/><EditorField label="起步加速度" type="number" :model-value="actor.acceleration" min="1" @update="actor.acceleration=$event" @changed="emit('changed')"/><EditorField label="空中转向强度" type="number" :model-value="actor.airControl" min="0" max="1" step="0.05" @update="actor.airControl=$event" @changed="emit('changed')"/><EditorField label="跳跃力度" type="number" :model-value="actor.jumpSpeed" min="1" @update="actor.jumpSpeed=$event" @changed="emit('changed')"/><EditorField label="跳跃次数" type="number" :model-value="actor.maxJumps" min="1" max="6" @update="actor.maxJumps=$event" @changed="emit('changed')"/><EditorField label="上升时长（秒）" type="number" :model-value="actor.jumpTimeToPeak" min="0.05" step="0.01" @update="actor.jumpTimeToPeak=$event" @changed="emit('changed')"/><EditorField label="下落时长（秒）" type="number" :model-value="actor.jumpTimeToDescent" min="0.05" step="0.01" @update="actor.jumpTimeToDescent=$event" @changed="emit('changed')"/><EditorField label="素材显示倍率（1 = 168 高）" type="number" :model-value="actor.sprite.displayScale" min="0.25" max="3" step="0.05" @update="actor.sprite.displayScale=$event" @changed="emit('changed')"/><EditorField label="碰撞体世界缩放" type="number" :model-value="actor.sprite.worldScale??1" min="0.1" max="3" step="0.05" @update="actor.sprite.worldScale=$event" @changed="emit('changed')"/></div>
    <p class="notice">素材显示倍率只改变人物画面大小；碰撞体世界缩放单独控制角色的游戏尺寸。</p>
  </PanelShell>
  <PanelShell title="训练木桩" eyebrow="战斗测试">
    <div class="field-grid"><EditorField label="木桩血量" type="number" :model-value="dummy.maxHp" min="1" @update="dummy.maxHp=$event" @changed="emit('changed')"/><EditorField label="连段输入保留帧数（60 帧 = 1 秒）" type="number" :model-value="config.runtime.attackBufferFrames" min="1" max="64" @update="config.runtime.attackBufferFrames=$event" @changed="emit('changed')"/><EditorField label="长按多少帧认定蓄力" type="number" :model-value="config.runtime.holdToChargeFrames" min="3" max="60" @update="config.runtime.holdToChargeFrames=$event" @changed="emit('changed')"/><EditorField label="两次出招间的连段保留帧数" type="number" :model-value="config.runtime.comboKeepFrames" min="1" max="180" @update="config.runtime.comboKeepFrames=$event" @changed="emit('changed')"/></div>
    <p class="notice">木桩有击退、击飞、撞墙和血量反馈；不会还手。游戏按 R 可立即重置训练。</p>
  </PanelShell>
  <PanelShell title="转向与落地" eyebrow="基础移动动作">
    <p class="notice">反向跑动时播放一次转身；持续按住方向不会反复重播。起跳、下落和落地按实际接触地面衔接。</p>
    <EditorField label="启用转身与落地动作" type="checkbox" :model-value="movement.enabled??false" @update="setSpriteSetting('locomotion','enabled',$event)"/>
    <div class="field-grid">
      <label v-for="(label,key) in {turnRight:'向右转身动作',turnLeft:'向左转身动作'}" :key="key" class="editor-field"><span>{{label}}</span><select :value="movement[key]?.animation??''" @change="setSpriteSetting('locomotion',key,{...(movement[key]||{}),animation:($event.target as HTMLSelectElement).value})"><option value="">未设置</option><option v-for="(clip,name) in animations" :key="name" :value="name">{{clip.label||name}}</option></select>
        <template v-if="movement[key]?.animation"><span>开始转身的帧</span><input type="number" min="1" :value="Number(movement[key].flipFrame??0)+1" @change="setSpriteSetting('locomotion',key,{...movement[key],flipFrame:Math.max(0,Number(($event.target as HTMLInputElement).value)-1)})"><span>允许接入其他动作的帧</span><input type="number" min="1" :value="Number(movement[key].cancelFrame??0)+1" @change="setSpriteSetting('locomotion',key,{...movement[key],cancelFrame:Math.max(0,Number(($event.target as HTMLInputElement).value)-1)})"></template>
      </label>
      <EditorField label="落地后允许取消的帧" type="number" :model-value="movement.landingCancelFrame??0" min="0" @update="setSpriteSetting('locomotion','landingCancelFrame',$event)"/>
    </div>
  </PanelShell>
  <PanelShell title="蓄力时移动" eyebrow="走动与跳跃">
    <EditorField label="蓄力移动速度（正常=100%）" type="number" :model-value="(actor.chargeMovementScale??0.85)*100" min="0" max="100" step="1" @update="actor.chargeMovementScale=$event/100" @changed="emit('changed')"/>
    <p class="notice">蓄力时可以走动、转向和跳跃。松开攻击键释放蓄力，按格挡键转为防守。</p>
  </PanelShell>
  <PanelShell title="格挡与弹刀" eyebrow="按下立即防守">
    <p class="notice">按下 L 立即防守，举剑动作不影响判定；挡住或弹刀成功会立即换成对应动作。按住 L 可以移动、跳跃，但不能攻击。</p>
    <EditorField label="启用格挡防守" type="checkbox" :model-value="guard.enabled??false" @update="setSpriteSetting('guard','enabled',$event)"/>
    <div class="field-grid">
      <EditorField label="弹刀判定窗口（帧）" type="number" :model-value="guard.parryWindowFrames??8" min="1" max="60" @update="setSpriteSetting('guard','parryWindowFrames',$event)"/>
      <EditorField label="格挡时承受伤害倍率" type="number" :model-value="guard.damageMultiplier??0.2" min="0" max="1" step="0.05" @update="setSpriteSetting('guard','damageMultiplier',$event)"/>
      <EditorField label="格挡移动速度（正常=100%）" type="number" :model-value="(guard.movementScale??0.85)*100" min="0" max="100" step="1" @update="setSpriteSetting('guard','movementScale',$event/100)"/>
      <EditorField label="举剑动作播放速度" type="number" :model-value="guard.startupAnimationSpeed??1" min="0.05" max="20" step="0.5" @update="setSpriteSetting('guard','startupAnimationSpeed',$event)"/>
      <label v-for="(label,key) in {startupAnimation:'举起防守动作',holdAnimation:'持续防守动作',blockAnimation:'普通格挡受击动作'}" :key="key" class="editor-field"><span>{{label}}</span><select :value="guard[key]??''" @change="setSpriteSetting('guard',key,($event.target as HTMLSelectElement).value)"><option value="">未设置</option><option v-for="(clip,name) in animations" :key="name" :value="name">{{clip.label||name}}</option></select></label>
    </div>
    <div class="field-grid input-bindings"><label class="editor-field"><span>冲刺攻击按键</span><input :value="inputText('dashAttack')" placeholder="SHIFT+J" @change="setInput('dashAttack',$event)"></label><label class="editor-field"><span>按住防守按键</span><input :value="inputText('guard')" placeholder="L_HOLD" @change="setInput('guard',$event)"></label></div>
    <p class="notice">输入可用逗号分隔多个绑定。SHIFT+J 为冲刺攻击，L_HOLD 为持续防守。</p>
  </PanelShell>
  <PanelShell title="空中连段" eyebrow="三段空中攻击">
    <p class="notice">空中攻击分三次输入；每段只会在允许接招的窗口进入下一段。</p>
    <EditorField label="空中连段最长滞空帧数" type="number" :model-value="airCombo.maxSuspendFrames??180" min="0" max="600" @update="setSpriteSetting('airCombo','maxSuspendFrames',$event)"/>
  </PanelShell>
  <PanelShell title="拔刀与收刀" eyebrow="持剑状态">
    <p class="notice">出招可按允许接入的帧提前取消拔刀或收刀；空闲一段时间后自动收刀。</p>
    <EditorField label="启用拔刀与收刀" type="checkbox" :model-value="drawSheathe.enabled??false" @update="setSpriteSetting('drawSheathe','enabled',$event)"/>
    <div class="field-grid">
      <label v-for="(label,key) in {drawAnimation:'拔刀动作',sheatheAnimation:'收刀动作'}" :key="key" class="editor-field"><span>{{label}}</span><select :value="drawSheathe[key]??''" @change="setSpriteSetting('drawSheathe',key,($event.target as HTMLSelectElement).value)"><option value="">未设置</option><option v-for="(clip,name) in animations" :key="name" :value="name">{{clip.label||name}}</option></select></label>
      <EditorField label="空闲多久后收刀（秒）" type="number" :model-value="drawSheathe.idleDelay??4" min="0" max="60" step="0.1" @update="setSpriteSetting('drawSheathe','idleDelay',$event)"/>
      <EditorField label="拔刀动作允许取消帧" type="number" :model-value="drawSheathe.drawCancelFrame??0" min="0" @update="setSpriteSetting('drawSheathe','drawCancelFrame',$event)"/>
      <EditorField label="收刀动作允许取消帧" type="number" :model-value="drawSheathe.sheatheCancelFrame??0" min="0" @update="setSpriteSetting('drawSheathe','sheatheCancelFrame',$event)"/>
    </div>
  </PanelShell>
</div></template>
