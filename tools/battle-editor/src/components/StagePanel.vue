<script setup lang="ts">
import {computed,ref} from 'vue';
import PixiStageCanvas from './PixiStageCanvas.vue';import PanelShell from './PanelShell.vue';import EditorField from './EditorField.vue';import type {AssetFile,JsonObject} from '../types';
const props=defineProps<{config:JsonObject;assets:AssetFile[];viewport?:JsonObject}>();
const emit=defineEmits<{changed:[];selectedAsset:[path:string];assetsReloaded:[assets:AssetFile[]]}>();
const canvas=ref<any>(null),selection=ref<{kind:string;index:number}|null>(null);
let drag:{target:JsonObject;x:number;y:number}|null=null;
const points=computed(()=>{
  void props.viewport?.zoom;void props.viewport?.panX;void props.viewport?.panY;
  if(!canvas.value) return [];
  return [{target:props.config.stage.spawn.player,label:'角色',kind:'player'},{target:props.config.stage.spawn.enemies[0],label:'木桩',kind:'enemy'}].map(p=>({...p,point:canvas.value.worldToClient(p.target.x,p.target.y-24)}));
});
function begin(e:PointerEvent,p:JsonObject){const world=canvas.value.clientToWorld(e.clientX,e.clientY);drag={target:p.target,x:p.target.x-world.x,y:p.target.y-world.y};selection.value={kind:p.kind,index:0};(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);}
function move(e:PointerEvent){if(!drag)return;const world=canvas.value.clientToWorld(e.clientX,e.clientY);drag.target.x=Math.round(world.x+drag.x);drag.target.y=Math.round(world.y+drag.y);}
function end(){if(drag){drag=null;emit('changed');}}
</script>
<template><div class="stage-layout" v-if="config.stage">
  <PanelShell title="木桩训练场画布" eyebrow="E 盘场景画布" description="拖动“角色”和“木桩”标签调整出生点。滚轮缩放，按住空格拖动画布。">
    <div class="stage-canvas-wrap"><PixiStageCanvas ref="canvas" :config="config" :assets="assets" :viewport="viewport" :selection="selection"/><div class="canvas-spawn-overlays"><button v-for="p in points" :key="p.kind" class="canvas-spawn-handle" :class="p.kind" :style="{left:p.point.x+'px',top:p.point.y+'px',width:'52px'}" @pointerdown="begin($event,p)" @pointermove="move" @pointerup="end" @pointercancel="end">{{p.label}}</button></div></div>
  </PanelShell>
  <PanelShell title="场地与出生点" eyebrow="清空场景 · 只剩木桩">
    <div class="field-grid"><EditorField v-for="(label,key) in {left:'左边界',right:'右边界',floorY:'地面高度'}" :key="key" :label="label" type="number" :model-value="config.stage.bounds[key]" @update="config.stage.bounds[key]=$event" @changed="emit('changed')"/><EditorField label="背景颜色" :model-value="config.art.background" @update="config.art.background=$event" @changed="emit('changed')"/><EditorField label="地面颜色" :model-value="config.art.ground" @update="config.art.ground=$event" @changed="emit('changed')"/></div>
    <div v-for="p in [{target:config.stage.spawn.player,name:'角色'},{target:config.stage.spawn.enemies[0],name:'木桩'}]" :key="p.name" class="sub-card"><h4>{{p.name}}出生位置（脚底）</h4><div class="field-grid"><EditorField label="X" type="number" :model-value="p.target.x" @update="p.target.x=$event" @changed="emit('changed')"/><EditorField label="Y" type="number" :model-value="p.target.y" @update="p.target.y=$event" @changed="emit('changed')"/></div></div>
    <p class="notice">修改后保存，游戏自动应用并重置训练。背景和其他旧美术没有放入这份工程。</p>
  </PanelShell>
</div></template>
