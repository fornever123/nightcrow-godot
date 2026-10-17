<script setup lang="ts">
import {computed, onMounted, onUnmounted, ref, watch} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import {api} from '../services/api';
import {animationDuration, frameIndexAtTime, frameTimeInCycle, frameStartTime, clampMoveFrames, clipLabels, syncTimings} from '../core/timing';
import type {AssetFile, JsonObject} from '../types';
const props=defineProps<{config:JsonObject; assets:AssetFile[]; workspace:JsonObject; selectedMove?:JsonObject}>();
const emit=defineEmits<{changed:[]; assetsReloaded:[assets:AssetFile[]]}>();
const actor=computed(()=>props.config.characters?.find((c:JsonObject)=>c.id==='player'));
const effectMode=ref(false);
const name=ref(props.workspace.animationName||'attack_3');
const group=computed(()=>effectMode.value?actor.value?.sprite?.effects:actor.value?.sprite?.animations);
const clip=computed<JsonObject>(()=>group.value?.[name.value]||{frames:[],fps:36});
const index=ref(0), playing=ref(true), zoom=ref(1.5), ghosts=ref(false), showEffect=ref(true), boxes=ref(false), allFrames=ref(false);
const canvas=ref<HTMLCanvasElement|null>(null), status=ref('拖动角色图片，可移动当前帧；勾选“整段一起移动”可移动整段。');
const sheetWidth=ref(128), sheetHeight=ref(128), sheetCount=ref(16);
const frameBakerBusy=ref(false), frameBakerMode=ref('new'), frameBakerLabel=ref(''), frameBakerBaked=ref(true);
const current=computed<JsonObject>(()=>clip.value.frames[index.value]||{});
const previewSpeed=computed(()=>effectMode.value?1:Number((props.selectedMove?.animation===name.value?props.selectedMove:props.config.moves?.find((m:JsonObject)=>m.animation===name.value))?.animationSpeed||1));
const images=new Map<string,HTMLImageElement>();
const urls=computed(()=>props.assets.filter(a=>a.kind==='image'));
let raf=0,last=0,phase=0,drag:{x:number;y:number;pivots:number[][]}|null=null;
let resizeObserver:ResizeObserver|null=null, pixelRatio=0;
function resizeCanvas() {
  const view=canvas.value;if(!view)return;
  const rect=view.getBoundingClientRect(),style=getComputedStyle(view);
  const width=rect.width-parseFloat(style.borderLeftWidth)-parseFloat(style.borderRightWidth);
  const height=rect.height-parseFloat(style.borderTopWidth)-parseFloat(style.borderBottomWidth);
  pixelRatio=window.devicePixelRatio||1;
  const bufferWidth=Math.max(1,Math.round(width*pixelRatio)),bufferHeight=Math.max(1,Math.round(height*pixelRatio));
  if(view.width!==bufferWidth)view.width=bufferWidth;
  if(view.height!==bufferHeight)view.height=bufferHeight;
}
function url(path:string) {return '/project-assets/'+path.split('/').map(encodeURIComponent).join('/');}
function imageFor(path:string) {
  if(!path) return null;
  if(!images.has(path)) {const im=new Image();im.src=url(path);im.onload=draw;images.set(path,im);}
  return images.get(path)!;
}
function drawFrame(ctx:CanvasRenderingContext2D,f:JsonObject,alpha=1) {
  if(!f||f.blank) return;
  const im=imageFor(f.asset);if(!im?.complete||!im.naturalWidth) return;
  const scale=zoom.value*Number(actor.value?.sprite?.displayScale||1);
  const r=f.region||{x:0,y:0,width:im.naturalWidth,height:im.naturalHeight};
  ctx.globalAlpha=alpha;ctx.imageSmoothingEnabled=effectMode.value||String(f.asset).startsWith('image/vfx/')||actor.value.sprite.filter!=='nearest';
  ctx.drawImage(im,r.x,r.y,r.width,r.height,430-Number(f.pivotX)*scale,355-Number(f.pivotY)*scale,Number(f.width)*scale,Number(f.height)*scale);
  ctx.globalAlpha=1;
}
function draw() {
  const view=canvas.value,ctx=view?.getContext('2d');if(!view||!ctx) return;
  ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,view.width,view.height);
  ctx.setTransform(view.width/900,0,0,view.height/460,0,0);
  ctx.strokeStyle='#857498';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(0,355);ctx.lineTo(900,355);ctx.stroke();
  ctx.fillStyle='#c4b5fd';ctx.font='13px sans-serif';ctx.fillText('脚底固定点 · 游戏原比例 '+Math.round(168*Number(actor.value?.sprite?.displayScale||1))+' 高',20,440);
  if(ghosts.value&&index.value>0) drawFrame(ctx,clip.value.frames[index.value-1],0.20);
  drawFrame(ctx,current.value);
  if(showEffect.value&&!effectMode.value&&!clip.value.effectsBaked) {
    const fx=actor.value.sprite.effects?.[clip.value.overlayEffect||(name.value==='attack_3'?'feather_slash':'')];
    if(fx?.frames?.length) {
      const time=playing.value?frameTimeInCycle(clip.value,phase):frameStartTime(clip.value,index.value);
      if(clip.value.overlayEffect) {
        if(time<animationDuration(fx))drawFrame(ctx,fx.frames[frameIndexAtTime(fx,time,1,false)]);
      } else drawFrame(ctx,fx.frames[Math.min(fx.frames.length-1,Math.floor(index.value/Number(clip.value.fps)*fx.fps))]);
    }
  }
  if(boxes.value&&!effectMode.value) {
    const m=props.config.moves?.find((m:JsonObject)=>m.animation===name.value),h=m?.hitbox;
    if(h){ctx.strokeStyle='#fb7185';ctx.strokeRect(430+(h.x-h.width/2)*zoom.value,355+(h.y-h.height/2)*zoom.value,h.width*zoom.value,h.height*zoom.value);}
  }
  ctx.strokeStyle='#67e8f9';ctx.beginPath();ctx.moveTo(421,355);ctx.lineTo(439,355);ctx.moveTo(430,346);ctx.lineTo(430,364);ctx.stroke();
}
function tick(t:number) {
  if(pixelRatio!==(window.devicePixelRatio||1))resizeCanvas();
  const dt=Math.min((t-last)/1000,0.1);last=t;
  if(playing.value&&clip.value.frames.length) {phase+=dt*previewSpeed.value;index.value=frameIndexAtTime(clip.value,phase);}
  draw();raf=requestAnimationFrame(tick);
}
function scrub(value:number) {playing.value=false;index.value=Math.max(0,Math.min(clip.value.frames.length-1,value));phase=frameStartTime(clip.value,index.value);}
function togglePlay(){playing.value=!playing.value;phase=frameStartTime(clip.value,index.value);}
function changed() {syncTimings(props.config);emit('changed');draw();}
function setPivot(key:string,value:number) {
  const delta=Number(value)-Number(current.value[key]||0);
  for(const frame of allFrames.value?clip.value.frames:[current.value]) frame[key]=Number(frame[key]||0)+delta;
  changed();
}
function beginDrag(e:PointerEvent) {
  if(e.button!==0) return;playing.value=false;
  drag={x:e.clientX,y:e.clientY,pivots:(allFrames.value?clip.value.frames:[current.value]).map((f:JsonObject)=>[f.pivotX,f.pivotY])};
  (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
}
function moveDrag(e:PointerEvent) {
  if(!drag||!canvas.value) return;
  const scale=canvas.value.getBoundingClientRect().width/900*zoom.value*Number(actor.value.sprite.displayScale||1);
  (allFrames.value?clip.value.frames:[current.value]).forEach((f:JsonObject,i:number)=>{f.pivotX=+(drag!.pivots[i]![0]!-(e.clientX-drag!.x)/scale).toFixed(2);f.pivotY=+(drag!.pivots[i]![1]!-(e.clientY-drag!.y)/scale).toFixed(2);});
  draw();
}
function endDrag(){if(drag){drag=null;changed();}}
function read(file:File){return new Promise<string>((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result));r.onerror=()=>reject(r.error);r.readAsDataURL(file);});}
async function uploadImage(file:File,batch:string) {
  const data=await read(file),im=new Image();im.src=data;await im.decode();
  const result=await api.upload({category:'image',filename:`imports/${batch}/${file.name}`,contentBase64:data});
  return {im,path:result.path};
}
function replaceClip(frames:JsonObject[]) {
  clip.value.frames=frames;
  const n=frames.length;
  for(const m of props.config.moves||[]) if(m.animation===name.value&&m.syncAnimation) {
    clampMoveFrames(m,clip.value);
  }
  scrub(0);changed();
}
async function importFolder(event:Event) {
  const input=event.target as HTMLInputElement, files=Array.from(input.files||[]).filter(f=>/\.(png|jpe?g)$/i.test(f.name)).sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true}));
  if(!files.length) return;
  playing.value=false;const frames:JsonObject[]=[],batch=Date.now().toString();status.value='正在导入，完成后替换当前动作…';
  try {
    for(const [i,file] of files.entries()) {
      const {im,path}=await uploadImage(file,batch);
      frames.push({asset:path,width:im.naturalWidth,height:im.naturalHeight,pivotX:im.naturalWidth/2,pivotY:im.naturalHeight});
      status.value=`导入 ${i+1} / ${files.length}`;
    }
    replaceClip(frames);emit('assetsReloaded',(await api.loadAssets()).assets);status.value='已替换当前动作；可逐帧调整脚底固定点，再保存到游戏。';
  } catch(e){status.value=String(e);} finally {input.value='';}
}
async function importSheet(event:Event) {
  const input=event.target as HTMLInputElement,file=input.files?.[0];if(!file) return;
  try {
    const {im,path}=await uploadImage(file,Date.now().toString());
    const w=Math.floor(sheetWidth.value),h=Math.floor(sheetHeight.value),cols=Math.floor(im.naturalWidth/w),rows=Math.floor(im.naturalHeight/h);
    if(w<1||h<1||cols<1||rows<1||sheetCount.value>cols*rows) throw new Error('图集格子尺寸或帧数超出图片范围');
    const frames=Array.from({length:sheetCount.value},(_,i)=>({asset:path,width:w,height:h,pivotX:w/2,pivotY:h,region:{x:(i%cols)*w,y:Math.floor(i/cols)*h,width:w,height:h}}));
    replaceClip(frames);emit('assetsReloaded',(await api.loadAssets()).assets);status.value='图集已按格子拆分，无须重新压缩图片。';
  } catch(e){status.value=String(e);} finally{input.value='';}
}
async function replaceFrame(path:string) {
  const im=imageFor(path);if(!im)return;await im.decode();
  current.value.asset=path;delete current.value.region;changed();
}
async function importFrameBaker(event:Event,folder=false) {
  const input=event.target as HTMLInputElement,files=Array.from(input.files||[]);
  if(!files.length||frameBakerBusy.value)return;
  frameBakerBusy.value=true;playing.value=false;
  const targetName=name.value,targetEffect=effectMode.value,mode=frameBakerMode.value;
  const targetActor=actor.value;
  status.value='正在读取 FrameBaker 的图片、原点和逐帧时长…';
  try {
    let result:{ok:true;clip:JsonObject;importId:string;warnings:string[]};
    if(folder) {
      const metadataFiles=files.filter(f=>/\.frames\.json$/i.test(f.name));
      if(metadataFiles.length!==1)throw new Error('请选择只含一个动作的导出文件夹，其中应有一个 .frames.json 文件。');
      const metadata=JSON.parse(await metadataFiles[0]!.text());
      const images=[];
      for(const file of files.filter(f=>/\.png$/i.test(f.name))) {
        const relative=file.webkitRelativePath.split('/').slice(1).join('/')||file.name;
        images.push({name:relative,contentBase64:(await read(file)).split(',')[1]});
      }
      const metadataFile=metadataFiles[0]!.webkitRelativePath.split('/').slice(1).join('/')||metadataFiles[0]!.name;
      result=await api.importFrameBaker({metadata,metadataFile,files:images});
    } else result=await api.importFrameBakerZip(files[0]!);
    const targetGroup=targetEffect?(targetActor.sprite.effects??={}):(targetActor.sprite.animations??={});
    const key=mode==='new'?'fb_'+crypto.randomUUID().replaceAll('-','').slice(0,12):targetName;
    const previous=targetGroup[key]||{};
    const label=frameBakerLabel.value.trim()||result.clip.frameBaker?.axisName||result.clip.frameBaker?.name||'FrameBaker 动作';
    targetGroup[key]={...previous,...result.clip,label,loop:mode==='new'?false:!!previous.loop};
    if(!targetEffect)targetGroup[key].effectsBaked=frameBakerBaked.value;
    const n=result.clip.frames.length;
    for(const m of props.config.moves||[])if(!targetEffect&&m.animation===key&&m.syncAnimation){
      clampMoveFrames(m,targetGroup[key]);
    }
    name.value=key;scrub(0);changed();
    emit('assetsReloaded',(await api.loadAssets()).assets);
    status.value=`已导入「${label}」${n} 帧，${animationDuration(result.clip).toFixed(3)} 秒。位置和停留时间已保留；对齐脚底后保存${mode==='new'&&!targetEffect?'，再到战斗参数选择这个动作':''}。`;
  } catch(error){status.value=error instanceof Error?error.message:String(error);}
  finally{frameBakerBusy.value=false;input.value='';}
}
watch([name,effectMode],()=>{if(!group.value?.[name.value])name.value=Object.keys(group.value||{})[0]||'idle';scrub(0);props.workspace.animationName=name.value;props.workspace.effectMode=effectMode.value;});
watch(index,()=>{if(!playing.value) props.workspace.animationFrame=index.value;});
watch(()=>props.assets,()=>{images.clear();draw();});
onMounted(()=>{resizeCanvas();resizeObserver=new ResizeObserver(resizeCanvas);if(canvas.value)resizeObserver.observe(canvas.value);raf=requestAnimationFrame(tick);});
onUnmounted(()=>{cancelAnimationFrame(raf);resizeObserver?.disconnect();});
</script>
<template>
  <div class="studio-layout" v-if="actor">
    <PanelShell title="动作与素材工坊" eyebrow="E 盘画布 · GODOT 动作" description="原图直接使用。播放看整段，暂停拖动看单帧，保存后应用到游戏。">
      <div class="studio-toolbar"><select v-model="effectMode" :disabled="frameBakerBusy"><option :value="false">角色动作</option><option :value="true">刀光特效</option></select><select v-model="name" :disabled="frameBakerBusy"><option v-for="(item,key) in group" :key="key" :value="key">{{item.label||clipLabels[key]||key}}</option></select><button class="button primary" @click="togglePlay">{{playing?'暂停':'播放'}}</button><button class="button ghost" @click="scrub(index-1)">上一帧</button><button class="button ghost" @click="scrub(index+1)">下一帧</button></div>
      <canvas ref="canvas" class="studio-canvas" width="900" height="460" @pointerdown="beginDrag" @pointermove="moveDrag" @pointerup="endDrag" @pointercancel="endDrag"></canvas>
      <div class="studio-toolbar"><input type="range" :value="index" min="0" :max="Math.max(0,clip.frames.length-1)" @input="scrub(Number(($event.target as HTMLInputElement).value))"><span>第 {{index+1}} / {{clip.frames.length}} 帧</span><label>缩放 <input type="number" v-model.number="zoom" min="0.25" max="4" step="0.25"></label></div>
      <div class="studio-toolbar"><label><input type="checkbox" v-model="ghosts"> 前一帧参考</label><label><input type="checkbox" v-model="showEffect"> 刀光对照</label><label><input type="checkbox" v-model="boxes"> 攻击框</label><label><input type="checkbox" v-model="allFrames"> 整段一起移动</label></div>
      <p class="notice">{{status}}</p>
      <div class="filmstrip"><button v-for="(f,i) in clip.frames" :key="i" :class="{active:i===index}" @click="scrub(Number(i))"><img v-if="!f.blank" :src="url(f.asset)"><span>{{Number(i)+1}}</span></button></div>
    </PanelShell>
    <div @focusin="playing=false">
      <PanelShell title="当前帧与播放" eyebrow="逐帧调整">
        <p class="notice">预览采用招式速度 {{previewSpeed}} 倍；点击输入框时自动暂停，避免改错帧。</p>
        <p class="notice">整段 {{animationDuration(clip,previewSpeed).toFixed(3)}} 秒；当前帧停留 {{((Number(current.durationTicks??1)/Number(clip.fps||24)/previewSpeed)*1000).toFixed(1)}} 毫秒。</p>
        <EditorField label="当前帧停留（1 = 原速一帧，2 = 停留两倍）" type="number" :model-value="current.durationTicks??1" min="0.001" max="1000" step="0.1" @update="current.durationTicks=$event" @changed="changed"/>
        <EditorField label="循环播放（待机、跑步使用）" type="checkbox" :model-value="clip.loop??false" @update="clip.loop=$event" @changed="changed"/>
        <div class="field-grid"><EditorField label="播放帧率 FPS" type="number" :model-value="clip.fps" :min="1" :max="180" @update="clip.fps=$event" @changed="changed"/><EditorField label="角色显示倍率（1 = E 盘原大小）" type="number" :model-value="actor.sprite.displayScale" min="0.25" max="3" step="0.05" @update="actor.sprite.displayScale=$event" @changed="changed"/><EditorField label="固定点 X（向大改，图片向左）" type="number" :model-value="current.pivotX" @update="setPivot('pivotX',$event)"/><EditorField label="固定点 Y（向大改，图片向上）" type="number" :model-value="current.pivotY" @update="setPivot('pivotY',$event)"/><EditorField label="当前帧宽度" type="number" :model-value="current.width" min="1" @update="current.width=$event" @changed="changed"/><EditorField label="当前帧高度" type="number" :model-value="current.height" min="1" @update="current.height=$event" @changed="changed"/></div>
        <label class="editor-field"><span>替换当前帧图片（可选择素材工坊的修改结果）</span><select :value="current.asset" @change="replaceFrame(($event.target as HTMLSelectElement).value)"><option v-for="a in urls" :value="a.path" :key="a.path">{{a.path}}</option></select></label>
        <label class="editor-field"><span>图片显示方式</span><select v-model="actor.sprite.filter" @change="changed"><option value="linear">原画平滑</option><option value="nearest">像素硬边</option></select></label>
        <EditorField v-if="effectMode" label="尾部消散速度（越小越慢）" type="number" :model-value="clip.erosionSpeed??0.8" min="0.1" max="3" step="0.1" @update="clip.erosionSpeed=$event" @changed="changed"/>
        <template v-else>
          <EditorField label="动作图片已包含刀光（避免重复叠加）" type="checkbox" :model-value="clip.effectsBaked??false" @update="clip.effectsBaked=$event" @changed="changed"/>
          <label class="editor-field"><span>同步附加特效层</span><select v-model="clip.overlayEffect" :disabled="clip.effectsBaked" @change="changed"><option value="">不使用额外特效层</option><option v-for="(fx,key) in actor.sprite.effects" :key="key" :value="key">{{fx.label||key}}</option></select></label>
        </template>
      </PanelShell>
      <PanelShell title="导入 FrameBaker 手调结果" eyebrow="图片 + 节奏 + 原点">
        <p class="notice">在 FrameBaker 导出当前动作的 PNG 序列或图集 ZIP，直接在这里导入。每帧停留和共同原点会一起保留。</p>
        <div class="field-grid">
          <label class="editor-field"><span>导入方式</span><select v-model="frameBakerMode" :disabled="frameBakerBusy"><option value="new">新增独立动作，保留现有动作</option><option value="current">替换上方当前动作</option></select></label>
          <label class="editor-field"><span>显示名称（留空使用导出名称）</span><input v-model="frameBakerLabel" :disabled="frameBakerBusy"></label>
        </div>
        <label v-if="!effectMode" class="editor-field"><span><input type="checkbox" v-model="frameBakerBaked" :disabled="frameBakerBusy"> 导出图片已经包含刀光</span></label>
        <div class="binding-actions">
          <label class="button secondary upload-label">{{frameBakerBusy?'正在导入…':'导入 FrameBaker ZIP'}}<input type="file" accept=".zip,application/zip" :disabled="frameBakerBusy" @change="importFrameBaker($event)"></label>
          <label class="button ghost upload-label">导入解压后的文件夹<input type="file" webkitdirectory multiple accept="image/png,.json" :disabled="frameBakerBusy" @change="importFrameBaker($event,true)"></label>
          <a class="button ghost" href="http://127.0.0.1:3210/" target="_blank" rel="noopener">打开 FrameBaker</a>
        </div>
        <p class="notice">画布十字代表游戏脚底。需要调整时，勾选“整段一起移动”，以参考帧统一校准。角色与特效分开导出时，先切到“刀光特效”导入，再选“同步附加特效层”。</p>
      </PanelShell>
      <PanelShell title="导入与替换整段素材" eyebrow="C 盘工坊能力">
        <p class="notice">先选上面的动作，再导入。图片按文件名中的数字排序，替换该动作；原文件保留，保存时有备份。</p>
        <label class="button secondary upload-label">导入 PNG 文件夹<input type="file" webkitdirectory multiple accept="image/png,image/jpeg" @change="importFolder"></label>
        <div class="sub-card"><h4>导入精灵图集</h4><div class="field-grid"><EditorField label="一格宽度" type="number" :model-value="sheetWidth" min="1" @update="sheetWidth=$event"/><EditorField label="一格高度" type="number" :model-value="sheetHeight" min="1" @update="sheetHeight=$event"/><EditorField label="总帧数" type="number" :model-value="sheetCount" min="1" @update="sheetCount=$event"/></div><label class="button ghost upload-label">选择图集 PNG<input type="file" accept="image/png" @change="importSheet"></label></div>
      </PanelShell>
    </div>
  </div>
</template>
