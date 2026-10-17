<script setup lang="ts">
import {computed, nextTick, onUnmounted, ref, watch} from 'vue';
import PanelShell from './PanelShell.vue';
import EditorField from './EditorField.vue';
import {api} from '../services/api';
import type {AssetFile, JsonObject} from '../types';

const props = defineProps<{config: JsonObject; assets: AssetFile[]; currentCharacter?: JsonObject; currentMove?: JsonObject; workspace?:JsonObject}>();
const emit = defineEmits<{changed: []; assetsReloaded: [assets: AssetFile[]]; selected: [path: string]}>();
const filter = ref('');
const category = ref<'image' | 'audio' | 'video' | 'misc'>('image');
const status = ref('');
const selectedPath = ref('');
const selected = computed(() => props.assets.find((asset) => asset.path === selectedPath.value) || null);
const visibleAssets = computed(() => props.assets.filter((asset) => !filter.value || asset.path.toLowerCase().includes(filter.value.toLowerCase())));
const canvas = ref<HTMLCanvasElement | null>(null);
const imageTool = ref<'brush' | 'erase' | 'crop' | 'picker'>('brush');
const brushColor = ref('#fbbf24');
const brushSize = ref(8);
const drawing = ref(false);
const cropDragging = ref(false);
const cropStart = ref({x: 0, y: 0});
const cropX = ref(0);
const cropY = ref(0);
const cropWidth = ref(1);
const cropHeight = ref(1);
const audioElement = ref<HTMLAudioElement | null>(null);
const waveformCanvas = ref<HTMLCanvasElement | null>(null);
const audioStart = ref(0);
const audioEnd = ref(0);
const editingStatus = ref('');
const previewZoom = ref(1);
const audioGain = ref(1);
const fadeIn = ref(0);
const fadeOut = ref(0);
const normalize = ref(false);
const imageUndo = ref<ImageData[]>([]);
const imageRedo = ref<ImageData[]>([]);
let previousPaintPoint: {x: number; y: number} | null = null;
let decodedAudio: AudioBuffer | null = null;
let mediaToken = 0;

function rememberImage() {
  const element = canvas.value;
  const context = element?.getContext('2d');
  if (!context || !element) return;
  imageUndo.value.push(context.getImageData(0, 0, element.width, element.height));
  const limit = Math.max(1, Math.min(20, Math.floor(32_000_000 / (element.width * element.height * 4))));
  while (imageUndo.value.length > limit) imageUndo.value.shift();
  imageRedo.value = [];
}

function undoImage(redo = false) {
  const source = redo ? imageRedo : imageUndo;
  const destination = redo ? imageUndo : imageRedo;
  const frame = source.value.pop();
  const element = canvas.value;
  const context = element?.getContext('2d');
  if (!frame || !element || !context) return;
  destination.value.push(context.getImageData(0, 0, element.width, element.height));
  element.width = frame.width; element.height = frame.height;
  context.putImageData(frame, 0, 0);
}

function transformImage(operation: 'flip' | 'rotate') {
  const source = canvas.value;
  if (!source) return;
  rememberImage();
  const copy = document.createElement('canvas');
  copy.width = source.width; copy.height = source.height;
  copy.getContext('2d')?.drawImage(source, 0, 0);
  if (operation === 'rotate') { source.width = copy.height; source.height = copy.width; }
  const context = source.getContext('2d')!;
  context.clearRect(0, 0, source.width, source.height);
  context.save();
  if (operation === 'flip') { context.translate(source.width, 0); context.scale(-1, 1); }
  else { context.translate(source.width, 0); context.rotate(Math.PI / 2); }
  context.drawImage(copy, 0, 0);
  context.restore();
}

function selectAsset(asset: AssetFile) {
  selectedPath.value = asset.path;
  emit('selected', asset.path);
}

function rewriteAssetReferences(value: any, from: string, to: string) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => {
      if (item === from) value[index] = to;
      else rewriteAssetReferences(item, from, to);
    });
  } else if (value && typeof value === 'object') {
    Object.keys(value).forEach((key) => {
      if (value[key] === from) value[key] = to;
      else rewriteAssetReferences(value[key], from, to);
    });
  }
}

function countAssetReferences(value: any, path: string): number {
  if (value === path) return 1;
  if (Array.isArray(value)) return value.reduce((count, item) => count + countAssetReferences(item, path), 0);
  if (value && typeof value === 'object') {
    const values = Object.values(value) as any[];
    return values.reduce((count: number, item: any) => count + countAssetReferences(item, path), 0);
  }
  return 0;
}

async function reloadAssetList() {
  const payload = await api.loadAssets();
  emit('assetsReloaded', payload.assets);
}

async function renameSelected() {
  if (!selected.value) return;
  const currentName = selected.value.path.split('/').pop() || '';
  const name = window.prompt('输入新的文件名（保留扩展名）', currentName);
  if (!name || name === currentName) return;
  try {
    const oldPath = selected.value.path;
    const result = await api.renameAsset(oldPath, name.trim());
    rewriteAssetReferences(props.config, oldPath, result.path);
    await reloadAssetList();
    selectedPath.value = result.path;
    emit('selected', result.path);
    emit('changed');
    editingStatus.value = `已重命名素材：${result.path}`;
  } catch (error) {
    editingStatus.value = error instanceof Error ? error.message : '重命名失败';
  }
}

async function deleteSelected() {
  if (!selected.value) return;
  const path = selected.value.path;
  const references = countAssetReferences(props.config, path);
  const message = references > 0
    ? `该素材仍被 ${references} 处配置引用。请先在动作工坊替换它并保存，再移入回收站。`
    : '确定把当前素材移入项目回收站吗？';
  if (!window.confirm(message)) return;
  try {
    const result = await api.deleteAsset(path);
    await reloadAssetList();
    selectedPath.value = '';
    editingStatus.value = `已移入回收站：${result.trashPath}`;
  } catch (error) {
    editingStatus.value = error instanceof Error ? error.message : '删除素材失败';
  }
}

function canvasPoint(event: PointerEvent) {
  const element = canvas.value;
  if (!element) return {x: 0, y: 0};
  const rect = element.getBoundingClientRect();
  return {x: (event.clientX - rect.left) * element.width / rect.width, y: (event.clientY - rect.top) * element.height / rect.height};
}

function paint(event: PointerEvent) {
  if (!drawing.value || !canvas.value) return;
  const context = canvas.value.getContext('2d');
  if (!context) return;
  const point = canvasPoint(event);
  if (imageTool.value === 'picker') return;
  context.globalCompositeOperation = imageTool.value === 'erase' ? 'destination-out' : 'source-over';
  context.fillStyle = brushColor.value;
  const start = previousPaintPoint || point;
  const steps = Math.max(1, Math.ceil(Math.hypot(point.x - start.x, point.y - start.y)));
  const size = Math.max(1, Math.round(brushSize.value));
  for (let index = 0; index <= steps; index += 1) {
    context.fillRect(Math.round(start.x + (point.x - start.x) * index / steps - size / 2), Math.round(start.y + (point.y - start.y) * index / steps - size / 2), size, size);
  }
  previousPaintPoint = point;
  context.globalCompositeOperation = 'source-over';
}

function beginPaint(event: PointerEvent) {
  if (event.button !== 0 || !canvas.value) return;
  if (imageTool.value === 'picker') {
    const point = canvasPoint(event);
    const pixel = canvas.value.getContext('2d')?.getImageData(Math.min(canvas.value.width - 1, Math.max(0, Math.floor(point.x))), Math.min(canvas.value.height - 1, Math.max(0, Math.floor(point.y))), 1, 1).data;
    if (pixel) brushColor.value = '#' + Array.from(pixel.slice(0, 3)).map((value) => value.toString(16).padStart(2, '0')).join('');
    return;
  }
  rememberImage();
  previousPaintPoint = null;
  drawing.value = true;
  canvas.value?.setPointerCapture(event.pointerId);
  paint(event);
}

function endPaint() {
  drawing.value = false;
  previousPaintPoint = null;
}

function clamp(value: number) {
  return Math.max(0, Math.min(1, value));
}

function beginCrop(event: PointerEvent) {
  if (!canvas.value) return;
  const point = canvasPoint(event);
  cropStart.value = {x: clamp(point.x / canvas.value.width), y: clamp(point.y / canvas.value.height)};
  cropX.value = cropStart.value.x;
  cropY.value = cropStart.value.y;
  cropWidth.value = 0.01;
  cropHeight.value = 0.01;
  cropDragging.value = true;
  (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
}

function moveCrop(event: PointerEvent) {
  if (!cropDragging.value || !canvas.value) return;
  const point = canvasPoint(event);
  const current = {x: clamp(point.x / canvas.value.width), y: clamp(point.y / canvas.value.height)};
  cropX.value = Math.min(cropStart.value.x, current.x);
  cropY.value = Math.min(cropStart.value.y, current.y);
  cropWidth.value = Math.max(0.01, Math.abs(current.x - cropStart.value.x));
  cropHeight.value = Math.max(0.01, Math.abs(current.y - cropStart.value.y));
}

function endCrop() {
  cropDragging.value = false;
}

function loadImageEditor() {
  if (!selected.value || selected.value.kind !== 'image' || !canvas.value) return;
  const path = selected.value.path;
  const token = ++mediaToken;
  const image = new Image();
  image.onload = () => {
    if (!canvas.value || token !== mediaToken || selected.value?.path !== path) return;
    if (image.width * image.height > 4_000_000) { editingStatus.value = '图片超过 400 万像素，请先缩小原图'; return; }
    canvas.value.width = image.width;
    canvas.value.height = image.height;
    previewZoom.value = Math.min(4, 640 / image.width, 420 / image.height);
    imageUndo.value = []; imageRedo.value = [];
    cropX.value = 0; cropY.value = 0; cropWidth.value = 1; cropHeight.value = 1;
    canvas.value.getContext('2d')!.imageSmoothingEnabled = false;
    canvas.value.getContext('2d')?.drawImage(image, 0, 0, canvas.value.width, canvas.value.height);
  };
  image.src = selected.value.url;
}

async function exportEditedImage() {
  if (!canvas.value || !selected.value || selected.value.kind !== 'image') return;
  try {
  const source = canvas.value;
  const sx = Math.min(source.width - 1, Math.max(0, Math.round(source.width * cropX.value)));
  const sy = Math.min(source.height - 1, Math.max(0, Math.round(source.height * cropY.value)));
  const sw = Math.max(1, Math.min(source.width - sx, Math.round(source.width * cropWidth.value)));
  const sh = Math.max(1, Math.min(source.height - sy, Math.round(source.height * cropHeight.value)));
  const output = document.createElement('canvas');
  output.width = sw;
  output.height = sh;
  output.getContext('2d')?.drawImage(source, sx, sy, sw, sh, 0, 0, sw, sh);
  const name = (selected.value.path.split('/').pop() || 'image').replace(/\.[^.]+$/, '');
  editingStatus.value = '正在导出 PNG…';
  const result = await api.upload({category: 'image', filename: `edited/${name}.png`, contentBase64: output.toDataURL('image/png')});
  const payload = await api.loadAssets();
  emit('assetsReloaded', payload.assets);
  selectedPath.value = result.path;
  emit('selected', result.path);
  editingStatus.value = `已保存新素材：${result.path}`;
  } catch (error) { editingStatus.value = String(error); }
}

function writeString(view: DataView, offset: number, value: string) {
  for (let index = 0; index < value.length; index += 1) view.setUint8(offset + index, value.charCodeAt(index));
}

function audioToWav(buffer: AudioBuffer, start: number, end: number) {
  const sampleRate = buffer.sampleRate;
  const first = Math.max(0, Math.floor(start * sampleRate));
  const last = Math.min(buffer.length, Math.ceil(end * sampleRate));
  const length = Math.max(1, last - first);
  const channels = buffer.numberOfChannels;
  if (last <= first) throw new Error('裁剪结束时间必须大于开始时间');
  let peak = 0;
  if (normalize.value) {
    for (let channel = 0; channel < channels; channel += 1) {
      const data = buffer.getChannelData(channel);
      for (let sample = first; sample < last; sample += 1) peak = Math.max(peak, Math.abs(data[sample] || 0));
    }
  }
  const gain = Math.max(0, audioGain.value) * (normalize.value && peak > 0 ? 0.95 / peak : 1);
  const output = new ArrayBuffer(44 + length * channels * 2);
  const view = new DataView(output);
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + length * channels * 2, true);
  writeString(view, 8, 'WAVE');
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * channels * 2, true);
  view.setUint16(32, channels * 2, true);
  view.setUint16(34, 16, true);
  writeString(view, 36, 'data');
  view.setUint32(40, length * channels * 2, true);
  let offset = 44;
  for (let sample = 0; sample < length; sample += 1) {
    for (let channel = 0; channel < channels; channel += 1) {
      const time = sample / sampleRate;
      const envelope = Math.min(fadeIn.value > 0 ? Math.min(1, time / fadeIn.value) : 1, fadeOut.value > 0 ? Math.min(1, (length / sampleRate - time) / fadeOut.value) : 1);
      const value = Math.max(-1, Math.min(1, (buffer.getChannelData(channel)[first + sample] || 0) * gain * envelope));
      view.setInt16(offset, value < 0 ? value * 0x8000 : value * 0x7fff, true);
      offset += 2;
    }
  }
  return new Blob([output], {type: 'audio/wav'});
}

async function exportTrimmedAudio() {
  if (!selected.value || selected.value.kind !== 'audio') return;
  try {
  editingStatus.value = '正在解码音频…';
  const response = await fetch(selected.value.url);
  const source = await response.arrayBuffer();
  const context = new AudioContext();
  try {
    const buffer = await context.decodeAudioData(source);
    const end = Math.max(audioStart.value, Math.min(audioEnd.value || buffer.duration, buffer.duration));
    const blob = audioToWav(buffer, Math.max(0, audioStart.value), end);
    const data = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ''));
      reader.onerror = () => reject(reader.error || new Error('音频导出失败'));
      reader.readAsDataURL(blob);
    });
    const name = (selected.value.path.split('/').pop() || 'audio').replace(/\.[^.]+$/, '');
    const result = await api.upload({category: 'audio', filename: `edited/${name}_trim.wav`, contentBase64: data});
    const payload = await api.loadAssets();
    emit('assetsReloaded', payload.assets);
    selectedPath.value = result.path;
    emit('selected', result.path);
    editingStatus.value = `已保存裁剪音频：${result.path}`;
  } finally {
    await context.close();
  }
  } catch (error) { editingStatus.value = String(error); }
}

function updateAudioEnd() {
  if (audioElement.value && audioEnd.value <= 0) audioEnd.value = audioElement.value.duration || 0;
}

function drawWaveform(buffer: AudioBuffer) {
  const view = waveformCanvas.value;
  if (!view) return;
  const width = 720;
  const height = 110;
  view.width = width;
  view.height = height;
  const context = view.getContext('2d');
  if (!context) return;
  context.clearRect(0, 0, width, height);
  context.fillStyle = '#0f0f23';
  context.fillRect(0, 0, width, height);
  const data = buffer.getChannelData(0);
  const step = Math.max(1, Math.floor(data.length / width));
  context.strokeStyle = '#21bdae';
  context.lineWidth = 1;
  context.beginPath();
  for (let x = 0; x < width; x += 1) {
    const start = x * step;
    const end = Math.min(data.length, start + step);
    let peak = 0;
    for (let index = start; index < end; index += 1) peak = Math.max(peak, Math.abs(data[index] || 0));
    const y = height / 2 - peak * (height * 0.42);
    context.moveTo(x, height / 2 - (height / 2 - y));
    context.lineTo(x, height / 2 + (height / 2 - y));
  }
  context.stroke();
  context.strokeStyle = '#6c5ce7';
  context.setLineDash([4, 4]);
  const startX = buffer.duration ? audioStart.value / buffer.duration * width : 0;
  const endX = buffer.duration ? audioEnd.value / buffer.duration * width : width;
  context.beginPath();
  context.moveTo(startX, 0); context.lineTo(startX, height);
  context.moveTo(endX, 0); context.lineTo(endX, height);
  context.stroke();
  context.setLineDash([]);
}

async function loadAudioWaveform() {
  if (!selected.value || selected.value.kind !== 'audio') return;
  const token = ++mediaToken;
  try {
    const response = await fetch(selected.value.url);
    const source = await response.arrayBuffer();
    const context = new AudioContext();
    try {
      const buffer = await context.decodeAudioData(source);
      if (token !== mediaToken) return;
      decodedAudio = buffer;
      if (audioEnd.value <= 0) audioEnd.value = buffer.duration;
      drawWaveform(buffer);
    } finally {
      await context.close();
    }
  } catch {
    editingStatus.value = '音频波形读取失败，但仍可直接播放和裁剪。';
  }
}

function seekAudio(event: MouseEvent) {
  if (!audioElement.value || !audioElement.value.duration) return;
  const rect = (event.currentTarget as HTMLCanvasElement).getBoundingClientRect();
  audioElement.value.currentTime = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)) * audioElement.value.duration;
}

watch(selectedPath, async () => {
  mediaToken += 1;
  decodedAudio = null;
  editingStatus.value = '';
  await nextTick();
  loadImageEditor();
  audioStart.value = 0;
  audioEnd.value = 0;
  if (selected.value?.kind === 'audio') void loadAudioWaveform();
});
watch([audioStart, audioEnd], () => { if (decodedAudio) drawWaveform(decodedAudio); });
onUnmounted(() => { mediaToken += 1; audioElement.value?.pause(); });

function readDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(reader.error || new Error('读取文件失败'));
    reader.readAsDataURL(file);
  });
}

async function uploadFiles(fileList: FileList | null) {
  if (!fileList?.length) return;
  status.value = `正在导入 ${fileList.length} 个文件…`;
  try {
    for (const file of Array.from(fileList)) {
      const dataUrl = await readDataUrl(file);
      const inferredCategory = file.type.startsWith('image/') ? 'image' : file.type.startsWith('audio/') ? 'audio' : file.type.startsWith('video/') ? 'video' : category.value;
      await api.upload({category: inferredCategory, filename: file.name, contentBase64: dataUrl});
    }
    const payload = await api.loadAssets();
    emit('assetsReloaded', payload.assets);
    status.value = `已导入 ${fileList.length} 个文件`;
  } catch (error) {
    status.value = error instanceof Error ? error.message : '导入失败';
  }
}

function bindAsset(_binding: string) {
  if(!selected.value || selected.value.kind!=='image') return;
  const actor=props.config.characters.find((c:JsonObject)=>c.id==='player');
  const group=props.workspace?.effectMode?actor.sprite.effects:actor.sprite.animations;
  const name=props.workspace?.animationName||'idle';
  const clip=group?.[name];
  if(!clip?.frames?.length) {editingStatus.value='先在动作工坊选择要替换的动作和帧';return;}
  const index=Math.min(clip.frames.length-1,Number(props.workspace?.animationFrame||0));
  clip.frames[index].asset=selected.value.path;
  delete clip.frames[index].region;delete clip.frames[index].blank;
  emit('changed');editingStatus.value=`已替换 ${name} 第 ${index+1} 帧，保存后在游戏中生效`;
}

function dropFiles(event: DragEvent) {
  event.preventDefault();
  void uploadFiles(event.dataTransfer?.files || null);
}
</script>

<template>
  <div class="assets-layout" @dragover.prevent @drop="dropFiles">
    <PanelShell title="素材工坊" eyebrow="ASSET BROWSER" description="图片、音频和视频都从项目 assets 目录管理；原始文件不会被裁剪或绘画覆盖。">
      <template #actions><select v-model="category" class="compact-select"><option value="image">图片</option><option value="audio">音频</option><option value="video">视频</option><option value="misc">其他</option></select><label class="button primary upload-button">导入文件<input type="file" multiple :accept="category === 'image' ? 'image/*' : category === 'audio' ? 'audio/*' : category === 'video' ? 'video/*' : '*/*'" @change="uploadFiles(($event.target as HTMLInputElement).files)" /></label></template>
      <div class="asset-toolbar"><input v-model="filter" class="search-input" placeholder="搜索资源路径…" /><span class="muted">{{ visibleAssets.length }} / {{ assets.length }}</span></div>
      <div class="asset-grid"><button v-for="asset in visibleAssets" :key="asset.path" class="asset-card" :class="{active: selectedPath === asset.path}" draggable="true" @click="selectAsset(asset)" @dragstart="(event) => event.dataTransfer?.setData('asset-path', asset.path)"><img v-if="asset.kind === 'image'" :src="asset.url" :alt="asset.path" /><div v-else class="asset-icon">{{ asset.kind === 'audio' ? '♪' : asset.kind === 'video' ? '▶' : '▦' }}</div><b>{{ asset.path.split('/').pop() }}</b><small>{{ asset.kind }} · {{ Math.ceil(asset.size / 1024) }} KB</small></button><div v-if="!visibleAssets.length" class="empty-state">拖入文件或点击右上角导入。</div></div>
      <div class="drop-zone">也可以直接从 Windows 文件管理器拖入这里批量导入</div>
      <div v-if="status" class="form-hint">{{ status }}</div>
    </PanelShell>
    <PanelShell title="资源工作台" eyebrow="VISUAL WORKBENCH" :description="selected?.path || '选择一个资源开始预览和绑定。'">
      <template v-if="selected">
        <div class="workbench-preview"><div v-if="selected.kind === 'image'" class="image-workbench"><canvas ref="canvas" class="media-canvas" :style="{width: `${(canvas?.width || 320) * previewZoom}px`, height: `${(canvas?.height || 200) * previewZoom}px`}" @pointerdown="imageTool === 'crop' ? undefined : beginPaint" @pointermove="imageTool === 'crop' ? undefined : paint" @pointerup="endPaint" @pointerleave="endPaint"></canvas><div v-if="imageTool === 'crop'" class="crop-layer" @pointerdown="beginCrop" @pointermove="moveCrop" @pointerup="endCrop" @pointerleave="endCrop"><div class="crop-box" :style="{left: `${cropX * 100}%`, top: `${cropY * 100}%`, width: `${cropWidth * 100}%`, height: `${cropHeight * 100}%`}"></div></div></div><div v-else-if="selected.kind === 'audio'" class="audio-workbench"><canvas ref="waveformCanvas" class="audio-waveform" @click="seekAudio"></canvas><audio ref="audioElement" controls :src="selected.url" @loadedmetadata="updateAudioEnd"></audio></div><video v-else-if="selected.kind === 'video'" controls :src="selected.url"></video><div v-else class="empty-state">此文件类型暂无预览。</div></div>
        <div v-if="selected.kind === 'image'" class="media-tools"><div class="tool-row"><button class="button" :class="{active: imageTool === 'brush'}" @click="imageTool = 'brush'">画笔</button><button class="button" :class="{active: imageTool === 'erase'}" @click="imageTool = 'erase'">橡皮</button><button class="button" :class="{active: imageTool === 'crop'}" @click="imageTool = 'crop'">拖动裁剪</button><label>颜色 <input v-model="brushColor" type="color" /></label><label>笔刷 <input v-model.number="brushSize" type="number" min="1" max="80" /></label><button class="button ghost" @click="loadImageEditor">重置</button></div><div class="field-grid"><EditorField label="裁剪 X（比例）" type="number" :model-value="cropX" min="0" max="1" step="0.01" @update="cropX = $event" /><EditorField label="裁剪 Y（比例）" type="number" :model-value="cropY" min="0" max="1" step="0.01" @update="cropY = $event" /><EditorField label="裁剪宽度（比例）" type="number" :model-value="cropWidth" min="0.01" max="1" step="0.01" @update="cropWidth = $event" /><EditorField label="裁剪高度（比例）" type="number" :model-value="cropHeight" min="0.01" max="1" step="0.01" @update="cropHeight = $event" /></div><div class="form-hint">选择“拖动裁剪”后，在图片上拖出选区；裁剪结果会导出到 edited，不覆盖原图。</div><button class="button primary" @click="exportEditedImage">导出透明 PNG 到 edited</button></div>
        <div v-if="selected.kind === 'audio'" class="media-tools"><div class="field-grid"><EditorField label="裁剪开始（秒）" type="number" :model-value="audioStart" min="0" step="0.01" @update="audioStart = $event" /><EditorField label="裁剪结束（秒）" type="number" :model-value="audioEnd" min="0" step="0.01" @update="audioEnd = $event" /><EditorField label="音量倍率" type="number" :model-value="audioGain" min="0" max="4" step="0.05" @update="audioGain = $event" /><EditorField label="淡入（秒）" type="number" :model-value="fadeIn" min="0" step="0.01" @update="fadeIn = $event" /><EditorField label="淡出（秒）" type="number" :model-value="fadeOut" min="0" step="0.01" @update="fadeOut = $event" /><EditorField label="标准化音量" type="checkbox" :model-value="normalize" @update="normalize = $event" /></div><button class="button primary" @click="exportTrimmedAudio">导出裁剪 WAV 到 edited</button></div>
        <div class="binding-actions"><button class="button ghost" @click="renameSelected">重命名</button><button class="button danger" @click="deleteSelected">移入回收站</button><button v-if="selected.kind==='image'" class="button secondary" @click="bindAsset('frame')">替换动作工坊当前帧</button></div>
        <div v-if="selected.kind === 'image'" class="tool-row"><EditorField label="预览缩放（不改原图）" type="number" :model-value="previewZoom" min="0.1" max="16" step="0.1" @update="previewZoom = $event" /><button class="button ghost" @click="imageTool = 'picker'">取色</button><button class="button ghost" :disabled="!imageUndo.length" @click="undoImage()">撤销画笔</button><button class="button ghost" :disabled="!imageRedo.length" @click="undoImage(true)">重做画笔</button><button class="button ghost" @click="transformImage('flip')">水平翻转</button><button class="button ghost" @click="transformImage('rotate')">旋转 90°</button></div>
        <div v-if="editingStatus" class="form-hint">{{ editingStatus }}</div>
      </template>
      <div v-else class="empty-state">从左侧选择图片、音频或视频。</div>
    </PanelShell>
  </div>
</template>
