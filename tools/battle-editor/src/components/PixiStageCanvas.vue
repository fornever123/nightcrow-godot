<script setup lang="ts">
import {onBeforeUnmount, onMounted, ref, watch} from 'vue';
import {Application, Assets, Container, Graphics, Rectangle, Sprite, Text, TextStyle, Texture} from 'pixi.js';
import type {AssetFile, JsonObject} from '../types';

type Selection = {kind: string; index: number};
type ResizeCorner = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';

const props = defineProps<{
  config: JsonObject;
  assets: AssetFile[];
  selection?: Selection | null;
  viewport?: JsonObject;
}>();
const emit = defineEmits<{changed: []; select: [selection: Selection]}>();
const host = ref<HTMLDivElement | null>(null);
let app: Application | null = null;
let world: Container | null = null;
let renderToken = 0;
let interactionActive = false;
let fitScale = 1;
let resizeObserver: ResizeObserver | null = null;
let panStart: {x: number; y: number; panX: number; panY: number} | null = null;

function clientToWorld(clientX: number, clientY: number) {
  if (!app || !world) return {x: 0, y: 0};
  const bounds = app.canvas.getBoundingClientRect();
  return world.toLocal({x: clientX - bounds.left, y: clientY - bounds.top});
}

function updateViewport() {
  if (!world || !host.value) return;
  const width = Number(props.config.settings?.designWidth || 1280);
  const height = Number(props.config.settings?.designHeight || 720);
  fitScale = Math.min((host.value.clientWidth - 32) / width, (host.value.clientHeight - 32) / height);
  const scale = fitScale * Number(props.viewport?.zoom || 1);
  world.scale.set(scale);
  world.position.set((host.value.clientWidth - width * scale) / 2 + Number(props.viewport?.panX || 0), (host.value.clientHeight - height * scale) / 2 + Number(props.viewport?.panY || 0));
}

function wheel(event: WheelEvent) {
  if (!props.viewport) return;
  event.preventDefault();
  const before = clientToWorld(event.clientX, event.clientY);
  props.viewport.zoom = Math.max(0.25, Math.min(6, Number(props.viewport.zoom || 1) * (event.deltaY < 0 ? 1.15 : 1 / 1.15)));
  updateViewport();
  const after = clientToWorld(event.clientX, event.clientY);
  props.viewport.panX = Number(props.viewport.panX || 0) + (after.x - before.x) * (world?.scale.x || 1);
  props.viewport.panY = Number(props.viewport.panY || 0) + (after.y - before.y) * (world?.scale.y || 1);
  updateViewport();
}

function beginPan(event: PointerEvent) {
  if (event.button !== 1 || !props.viewport) return;
  event.preventDefault();
  panStart = {x: event.clientX, y: event.clientY, panX: props.viewport.panX || 0, panY: props.viewport.panY || 0};
  host.value?.setPointerCapture(event.pointerId);
}

function movePan(event: PointerEvent) {
  if (!panStart || !props.viewport) return;
  props.viewport.panX = panStart.panX + event.clientX - panStart.x;
  props.viewport.panY = panStart.panY + event.clientY - panStart.y;
  updateViewport();
}

function worldToClient(x: number, y: number) {
  if (!host.value) return {x: 0, y: 0};
  const width = Number(props.config.settings?.designWidth || 1280);
  const height = Number(props.config.settings?.designHeight || 720);
  const fitScale = Math.min((host.value.clientWidth - 32) / width, (host.value.clientHeight - 32) / height);
  const scale = fitScale * Number(props.viewport?.zoom || 1);
  return {
    x: (host.value.clientWidth - width * scale) / 2 + Number(props.viewport?.panX || 0) + x * scale,
    y: (host.value.clientHeight - height * scale) / 2 + Number(props.viewport?.panY || 0) + y * scale,
  };
}

defineExpose({clientToWorld, worldToClient});

function stageData() {
  if (!props.config.stage || typeof props.config.stage !== 'object') props.config.stage = {};
  const stage = props.config.stage as JsonObject;
  if (!stage.bounds) stage.bounds = {left: 80, right: 1200, floorY: 560};
  if (!stage.spawn) stage.spawn = {player: {x: 340, y: 565}, enemies: []};
  if (!Array.isArray(stage.spawn.enemies)) stage.spawn.enemies = [];
  if (!Array.isArray(stage.decorations)) stage.decorations = [];
  return stage;
}

function assetUrl(path: string) {
  return props.assets.find((asset) => asset.path === path)?.url || '';
}

function label(text: string, x: number, y: number, color: string) {
  const view = new Text({text, style: new TextStyle({fontFamily: 'monospace', fontSize: 13, fill: color, fontWeight: '700'})});
  view.x = x;
  view.y = y;
  view.eventMode = 'none';
  return view;
}

function getWorldPoint(event: any) {
  return event.getLocalPosition(world);
}

function finishInteraction(view: any, move: (event: any) => void, end: () => void) {
  app?.stage.off('globalpointermove', move);
  app?.stage.off('pointerup', end);
  app?.stage.off('pointerupoutside', end);
  view.cursor = 'grab';
  interactionActive = false;
}

function enableDrag(view: any, kind: string, index: number, target: JsonObject) {
  view.eventMode = 'static';
  view.cursor = 'grab';
  view.on('pointerdown', (event: any) => {
    if (event.button !== 0 || target.locked) { if (event.button === 0) emit('select', {kind, index}); return; }
    if (interactionActive) return;
    if (kind === 'decoration' && props.selection?.kind === 'decoration' && props.selection.index === index) {
      const local = event.getLocalPosition(view);
      const width = Math.max(4, Number(target.width || 80));
      const height = Math.max(4, Number(target.height || 40));
      const threshold = 18;
      const nearLeft = local.x <= threshold;
      const nearRight = local.x >= width - threshold;
      const nearTop = local.y <= threshold;
      const nearBottom = local.y >= height - threshold;
      const corner = nearTop && nearLeft ? 'top-left' : nearTop && nearRight ? 'top-right' : nearBottom && nearLeft ? 'bottom-left' : nearBottom && nearRight ? 'bottom-right' : null;
      if (corner) {
        beginResize(event, view, target, corner);
        return;
      }
    }
    emit('select', {kind, index});
    interactionActive = true;
    view.cursor = 'grabbing';
    const start = getWorldPoint(event);
    const origin = {x: Number(target.x || 0), y: Number(target.y || 0)};
    const move = (moveEvent: any) => {
      const point = getWorldPoint(moveEvent);
      target.x = Math.round(origin.x + point.x - start.x);
      target.y = Math.round(origin.y + point.y - start.y);
      view.position.set(target.x, target.y);
    };
    const end = () => {
      finishInteraction(view, move, end);
      emit('changed');
      void renderScene();
    };
    app?.stage.on('globalpointermove', move);
    app?.stage.on('pointerup', end);
    app?.stage.on('pointerupoutside', end);
  });
}

function syncDecorationView(view: any, target: JsonObject) {
  const width = Math.max(4, Number(target.width || 80));
  const height = Math.max(4, Number(target.height || 40));
  const visual = view.__editableVisual as any;
  view.position.set(Number(target.x || 0), Number(target.y || 0));
  view.rotation = Number(target.rotation || 0) * Math.PI / 180;
  view.alpha = target.hidden ? 0.2 : 1;
  if (visual instanceof Sprite) {
    visual.width = width;
    visual.height = height;
    if (target.flipX) { visual.scale.x = -Math.abs(visual.scale.x); visual.x = width; }
    else { visual.scale.x = Math.abs(visual.scale.x); visual.x = 0; }
    if (target.flipY) { visual.scale.y = -Math.abs(visual.scale.y); visual.y = height; }
    else { visual.scale.y = Math.abs(visual.scale.y); visual.y = 0; }
  } else if (visual instanceof Graphics) {
    visual.clear().rect(0, 0, width, height).fill(target.color || 0x334155);
  }
  if (visual) visual.alpha = Number(target.opacity ?? 1);
  const title = view.__editableLabel as Text | undefined;
  if (title) title.position.set(8, Math.max(8, height / 2 - 7));
  const controls = view.__selectionControls as Container | undefined;
  if (controls) { controls.position.set(Number(target.x || 0), Number(target.y || 0)); controls.rotation = view.rotation; }
  const outline = view.__selectionOutline as Graphics | undefined;
  if (outline) {
    outline.clear().rect(0, 0, width, height).stroke({color: 0x21bdae, width: 2, alpha: 0.95});
    const handles = view.__resizeHandles as Graphics[] | undefined;
    handles?.forEach((handle, index) => {
      const positions = [[0, 0], [width, 0], [0, height], [width, height]][index];
      handle.position.set(positions[0], positions[1]);
    });
  }
  view.hitArea = new Rectangle(0, 0, width, height);
}

function resizeTarget(target: JsonObject, origin: JsonObject, corner: ResizeCorner, dx: number, dy: number) {
  const minimum = 4;
  let width = Number(origin.width || 80);
  let height = Number(origin.height || 40);
  let x = Number(origin.x || 0);
  let y = Number(origin.y || 0);
  if (corner.includes('right')) width = Math.max(minimum, Number(origin.width || 80) + dx);
  if (corner.includes('left')) {
    width = Math.max(minimum, Number(origin.width || 80) - dx);
    x = Number(origin.x || 0) + Number(origin.width || 80) - width;
  }
  if (corner.includes('bottom')) height = Math.max(minimum, Number(origin.height || 40) + dy);
  if (corner.includes('top')) {
    height = Math.max(minimum, Number(origin.height || 40) - dy);
    y = Number(origin.y || 0) + Number(origin.height || 40) - height;
  }
  target.x = Math.round(x);
  target.y = Math.round(y);
  target.width = Math.round(width);
  target.height = Math.round(height);
}

function beginResize(event: any, view: any, target: JsonObject, corner: ResizeCorner) {
  event.stopPropagation?.();
  if (interactionActive) return;
  interactionActive = true;
  view.cursor = corner === 'top-left' || corner === 'bottom-right' ? 'nwse-resize' : 'nesw-resize';
  const start = event.getLocalPosition(view);
  const origin = {x: Number(target.x || 0), y: Number(target.y || 0), width: Number(target.width || 80), height: Number(target.height || 40)};
  const move = (moveEvent: any) => {
    const point = moveEvent.getLocalPosition(view);
    resizeTarget(target, origin, corner, point.x - start.x, point.y - start.y);
    syncDecorationView(view, target);
  };
  const end = () => {
    finishInteraction(view, move, end);
    emit('changed');
    void renderScene();
  };
  app?.stage.on('globalpointermove', move);
  app?.stage.on('pointerup', end);
  app?.stage.on('pointerupoutside', end);
}

function addSelectionControls(parent: Container, view: any, target: JsonObject) {
  const controls = new Container();
  controls.eventMode = 'passive';
  view.__selectionControls = controls;
  const outline = new Graphics();
  outline.eventMode = 'none';
  view.__selectionOutline = outline;
  controls.addChild(outline);
  const handles: Graphics[] = [];
  const corners: ResizeCorner[] = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];
  corners.forEach((corner) => {
    const handle = new Graphics().rect(-5, -5, 10, 10).fill(0xf8fafc).stroke({color: 0x21bdae, width: 2});
    handle.eventMode = target.locked ? 'none' : 'static';
    handle.cursor = corner === 'top-left' || corner === 'bottom-right' ? 'nwse-resize' : 'nesw-resize';
    handle.on('pointerdown', (event: any) => beginResize(event, view, target, corner));
    controls.addChild(handle);
    handles.push(handle);
  });
  view.__resizeHandles = handles;
  parent.addChild(controls);
  syncDecorationView(view, target);
}

function addMarkerSelectionControls(parent: Container, marker: Container, radius: number) {
  const controls = new Container();
  controls.eventMode = 'passive';
  controls.position.set(marker.x, marker.y);
  const outline = new Graphics().circle(0, 0, radius).stroke({color: 0x21bdae, width: 2, alpha: 0.95});
  outline.eventMode = 'none';
  controls.addChild(outline);
  parent.addChild(controls);
}

function addBackgroundSelectionControls(parent: Container, width: number, height: number) {
  const controls = new Container();
  controls.eventMode = 'passive';
  const outline = new Graphics().rect(0, 0, width, height).stroke({color: 0x21bdae, width: 3, alpha: 0.95});
  outline.eventMode = 'none';
  controls.addChild(outline);
  parent.addChild(controls);
}

async function drawDecoration(parent: Container, decoration: JsonObject, index: number, token: number) {
  const container = new Container();
  const editable = container as any;
  container.eventMode = 'static';
  const image = typeof decoration.asset === 'string' ? assetUrl(decoration.asset) : '';
  let title: Text | undefined;
  if (image) {
    try {
      const texture = await Assets.load(image);
      texture.source.scaleMode = 'nearest';
      if (token !== renderToken) return;
      const sourceWidth = Number((texture as any).source?.width || texture.width || 1);
      const sourceHeight = Number((texture as any).source?.height || texture.height || 1);
      const crop = decoration.crop && typeof decoration.crop === 'object' ? decoration.crop as JsonObject : {};
      const cropX = Math.max(0, Math.min(0.99, Number(crop.x ?? 0)));
      const cropY = Math.max(0, Math.min(0.99, Number(crop.y ?? 0)));
      const cropWidth = Math.max(0.01, Math.min(1 - cropX, Number(crop.width ?? 1)));
      const cropHeight = Math.max(0.01, Math.min(1 - cropY, Number(crop.height ?? 1)));
      const croppedTexture = new Texture({source: (texture as any).source, frame: new Rectangle(sourceWidth * cropX, sourceHeight * cropY, sourceWidth * cropWidth, sourceHeight * cropHeight)});
      const sprite = new Sprite(croppedTexture);
      sprite.eventMode = 'none';
      editable.__editableVisual = sprite;
      container.addChild(sprite);
    } catch {
      const box = new Graphics();
      box.eventMode = 'none';
      editable.__editableVisual = box;
      container.addChild(box);
      title = label('图片预览失败', 8, 8, '#e2e8f0');
      container.addChild(title);
    }
  } else {
    const box = new Graphics();
    box.eventMode = 'none';
    editable.__editableVisual = box;
    container.addChild(box);
    title = label('装饰矩形', 8, 8, '#e2e8f0');
    container.addChild(title);
  }
  editable.__editableLabel = title;
  syncDecorationView(container, decoration);
  enableDrag(container, 'decoration', index, decoration);
  parent.addChild(container);
  if (props.selection?.kind === 'decoration' && props.selection.index === index) addSelectionControls(parent, container, decoration);
}

async function renderScene() {
  if (!world || !app || interactionActive) return;
  const token = ++renderToken;
  world.removeChildren().forEach((child) => child.destroy({children: true}));
  const stage = stageData();
  const width = Number(props.config.settings?.designWidth || 1280);
  const height = Number(props.config.settings?.designHeight || 720);
  const bounds = stage.bounds as JsonObject;
  const background = new Graphics().rect(0, 0, width, height).fill(props.config.art?.background || '#20212c');
  background.eventMode = 'none';
  const backgroundLayer = new Container();
  backgroundLayer.eventMode = 'static';
  backgroundLayer.hitArea = new Rectangle(0, 0, width, height);
  backgroundLayer.on('pointerdown', (event: any) => {
    if (event.button === 0) {
      event.stopPropagation?.();
      emit('select', {kind: 'background', index: 0});
    }
  });
  backgroundLayer.addChild(background);
  world.addChild(backgroundLayer);
  const backgroundAsset = assetUrl(props.config.art?.assets?.stage || '');
  if (backgroundAsset) {
    try {
      const texture = await Assets.load(backgroundAsset);
      if (token !== renderToken || !world) return;
      const sprite = new Sprite(texture);
      sprite.width = width; sprite.height = height; sprite.eventMode = 'none';
      backgroundLayer.addChild(sprite);
    } catch { }
  }
  const decorations = stage.decorations as JsonObject[];
  for (let index = 0; index < decorations.length; index += 1) {
    if (decorations[index].background === true) continue;
    await drawDecoration(world, decorations[index], index, token);
    if (token !== renderToken || !world) return;
  }
  world.addChild(new Graphics().rect(0, Number(bounds.floorY || 560), width, height).fill(props.config.art?.ground || '#273449'));
  const grid = new Graphics();
  for (let x = 0; x <= width; x += 40) grid.moveTo(x, 0).lineTo(x, height);
  for (let y = 0; y <= height; y += 40) grid.moveTo(0, y).lineTo(width, y);
  grid.stroke({color: 0x1e293b, width: 1, alpha: 0.75});
  grid.eventMode = 'none';
  world.addChild(grid);
  const floor = new Graphics().moveTo(Number(bounds.left || 0), Number(bounds.floorY || height - 120)).lineTo(Number(bounds.right || width), Number(bounds.floorY || height - 120)).stroke({color: 0x38bdf8, width: 4});
  floor.eventMode = 'none';
  world.addChild(floor);
  world.addChild(label(`${stage.name || '未命名场景'} · ${width}×${height}`, 18, 14, '#bae6fd'));
  world.addChild(label('拖动对象移动；选中素材后拖四角缩放', 18, 34, '#94a3b8'));

  const player = stage.spawn.player as JsonObject | null;
  if (player) {
    const actor=props.config.characters?.find((c:JsonObject)=>c.id==='player');
    const frame=actor?.sprite?.animations?.idle?.frames?.find((f:JsonObject)=>!f.blank);
    if(frame?.asset) {
      try {
        const texture=await Assets.load(assetUrl(frame.asset));
        if(token!==renderToken) return;
        const region=frame.region;
        const imageTexture=region?new Texture({source:texture.source,frame:new Rectangle(region.x,region.y,region.width,region.height)}):texture;
        imageTexture.source.scaleMode=actor.sprite.filter==='nearest'?'nearest':'linear';
        const sprite=new Sprite(imageTexture),scale=Number(actor.sprite.displayScale||1);
        sprite.width=frame.width*scale;sprite.height=frame.height*scale;
        sprite.position.set(player.x-frame.pivotX*scale,player.y-frame.pivotY*scale);
        sprite.eventMode='none';world.addChild(sprite);
      } catch { /* The asset validator reports missing images. */ }
    }
    const playerMarker = new Container();
    const playerCircle = new Graphics().circle(0, 0, 18).fill(0x38bdf8);
    playerCircle.eventMode = 'none';
    playerMarker.addChild(playerCircle);
    playerMarker.addChild(label('P', -5, -8, '#082f49'));
    playerMarker.eventMode = 'none';
    playerMarker.hitArea = new Rectangle(-22, -22, 44, 44);
    playerMarker.position.set(Number(player.x || 0), Number(player.y || 0) - 24);
    world.addChild(playerMarker);
    if (props.selection?.kind === 'player') addMarkerSelectionControls(world, playerMarker, 24);
  }

  const enemies = stage.spawn.enemies as JsonObject[];
  enemies.forEach((enemy, index) => {
    const wood=new Graphics().rect(-32,-136,64,136).fill('#705038').rect(-22,-127,6,118).fill('#946c47').rect(-32,-122,64,8).fill('#383039').rect(-32,-28,64,8).fill('#383039').circle(0,-83,22).fill('#af8254').circle(0,-83,12).stroke({color:'#433329',width:3});
    wood.position.set(Number(enemy.x),Number(enemy.y));wood.eventMode='none';world?.addChild(wood);
    const marker = new Container();
    const enemyCircle = new Graphics().circle(0, 0, 16).fill(0xfb7185);
    enemyCircle.eventMode = 'none';
    marker.addChild(enemyCircle);
    marker.addChild(label(`E${index + 1}`, -10, -7, '#4c0519'));
    marker.eventMode = 'none';
    marker.hitArea = new Rectangle(-20, -20, 40, 40);
    marker.position.set(Number(enemy.x || 0), Number(enemy.y || 0) - 24);
    world?.addChild(marker);
    if (props.selection?.kind === 'enemy' && props.selection.index === index) addMarkerSelectionControls(world as Container, marker, 22);
  });

  if (props.selection?.kind === 'background' && backgroundAsset) addBackgroundSelectionControls(world, width, height);

  updateViewport();
}

onMounted(async () => {
  if (!host.value) return;
  app = new Application();
  await app.init({background: 0x020617, antialias: true, resizeTo: host.value, autoDensity: true, resolution: Math.min(window.devicePixelRatio||1,2)});
  host.value.appendChild(app.canvas);
  world = new Container();
  app.stage.addChild(world);
  await renderScene();
  resizeObserver = new ResizeObserver(updateViewport);
  resizeObserver.observe(host.value);
});

watch(() => props.config.stage, () => { void renderScene(); }, {deep: true});
watch(() => props.assets, () => { void renderScene(); }, {deep: true});
watch(() => props.selection, () => { void renderScene(); }, {deep: true});
watch(() => props.config.settings, () => { void renderScene(); }, {deep: true});
watch(() => props.config.art, () => { void renderScene(); }, {deep: true});

onBeforeUnmount(() => {
  renderToken += 1;
  resizeObserver?.disconnect();
  app?.destroy(true, {children: true, texture: false});
  app = null;
  world = null;
});
</script>

<template><div ref="host" class="pixi-stage-host" @wheel="wheel" @pointerdown="beginPan" @pointermove="movePan" @pointerup="panStart = null" @pointercancel="panStart = null"></div></template>
