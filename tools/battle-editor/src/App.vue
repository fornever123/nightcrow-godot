<script setup lang="ts">
import {computed, onMounted, onUnmounted, ref, watch} from 'vue';
import OverviewPanel from './components/OverviewPanel.vue';
import AnimationStudio from './components/AnimationStudio.vue';
import CombatMatrix from './components/CombatMatrix.vue';
import {syncTimings} from './core/timing';
import CharactersPanel from './components/CharactersPanel.vue';
import FeedbackPanel from './components/FeedbackPanel.vue';
import StagePanel from './components/StagePanel.vue';
import AssetsPanel from './components/AssetsPanel.vue';
import JsonPanel from './components/JsonPanel.vue';
import RecoveryPanel from './components/RecoveryPanel.vue';
import {api} from './services/api';
import {History} from './core/history';
import {clone, defaultEditorProject, mergeEditorProject} from './core/project';
import type {AssetFile, EditorProject, JsonObject, ValidationResult} from './types';

const sections = [
  {id: 'overview', label: '总览', icon: '◈'},
  {id: 'animations', label: '动作工坊', icon: '▷'},
  {id: 'stage', label: '场景画布', icon: '▦'},
  {id: 'assets', label: '素材工坊', icon: '▧'},
  {id: 'characters', label: '角色', icon: '♙'},
  {id: 'moves', label: '战斗参数', icon: '✦'},
  {id: 'feedback', label: '打击感', icon: '✹'},
  {id: 'recovery', label: '备份与回收站', icon: '↺'},
  {id: 'json', label: 'JSON', icon: '{}' }
];
const config = ref<JsonObject>({});
const assets = ref<AssetFile[]>([]);
const project = ref<EditorProject>(defaultEditorProject());
const validation = ref<ValidationResult | null>(null);
const gameStatus = ref<JsonObject>({running: false});
const status = ref('正在加载编辑器…');
const busy = ref(false);
const reloadConfirm = ref(false);
const draftCandidate = ref<JsonObject|null>(null);
const savedSnapshot = ref('');
const savedProjectSnapshot = ref('');
const history = new History<JsonObject>({config: {}, project: defaultEditorProject()});
const LOCAL_SESSION_KEY = 'nightcrow-godot-modifier-v1';
let draftTimer: ReturnType<typeof setTimeout> | undefined;
let loaded = false;

const activeSection = computed(() => project.value.workspace.activeSection || 'overview');
const currentCharacter = computed(() => config.value.characters?.[project.value.workspace.selectedCharacter || 0]);
const currentMove = computed(() => config.value.moves?.[project.value.workspace.selectedMove || 0]);
const dirty = computed(() => JSON.stringify(config.value) !== savedSnapshot.value || JSON.stringify(project.value) !== savedProjectSnapshot.value);
const running = computed(() => gameStatus.value.process_alive === true);

function snapshot() {
  return clone({config: config.value, project: project.value});
}

function cacheDraft() {
  if (!loaded) return;
  try {
    localStorage.setItem(LOCAL_SESSION_KEY, JSON.stringify({...snapshot(), dirty: dirty.value}));
  } catch {
    status.value = '本地草稿缓存失败，请及时保存';
  }
}

function setSection(id: string) {
  project.value.workspace.activeSection = id;
}

function changed() {
  syncTimings(config.value);
  history.push(snapshot());
  status.value = '有未保存修改';
}

function selectAsset(path: string) {
  project.value.workspace.selectedAssetPath = path;
}

async function loadAll(restoreDraft = false, confirmed = false) {
  if (busy.value) return;
  if (loaded && dirty.value && !confirmed) {reloadConfirm.value=true;return;}
  busy.value = true;
  loaded = false;
  try {
    const [configPayload, assetPayload, projectPayload] = await Promise.all([api.loadConfig(), api.loadAssets(), api.loadEditorProject()]);
    config.value = configPayload.config;
    validation.value = configPayload.validation;
    assets.value = assetPayload.assets;
    const restoredProject = mergeEditorProject(projectPayload.project);
    savedSnapshot.value = JSON.stringify(config.value);
    savedProjectSnapshot.value = JSON.stringify(restoredProject);
    project.value = restoredProject;
    try {
      const cached = JSON.parse(localStorage.getItem(LOCAL_SESSION_KEY) || 'null');
      if (restoreDraft && cached?.dirty && cached.config && cached.project) {
        draftCandidate.value=cached;
      } else if (restoreDraft && cached?.project?.workspace) {
        project.value.workspace = {...project.value.workspace, ...cached.project.workspace};
      }
    } catch {
      localStorage.removeItem(LOCAL_SESSION_KEY);
    }
    history.reset(snapshot());
    status.value = dirty.value ? '已恢复草稿，尚未保存到游戏' : '已加载项目';
    loaded = true;
    cacheDraft();
    void refreshStatus();
  } catch (error) {
    status.value = error instanceof Error ? error.message : '加载失败';
  } finally {
    busy.value = false;
  }
}

async function validate() {
  busy.value = true;
  try {
    const result = await api.validate(config.value);
    validation.value = result.validation;
    status.value = result.validation.ok ? '配置校验通过' : `发现 ${result.validation.errors.length} 个配置错误`;
  } catch (error) {
    status.value = error instanceof Error ? error.message : '校验失败';
  } finally {
    busy.value = false;
  }
}

async function save(): Promise<boolean> {
  if (busy.value || !loaded) return false;
  busy.value = true;
  syncTimings(config.value);
  const captured = snapshot();
  try {
    const result = await api.saveProject(captured.config, captured.project);
    validation.value = result.validation;
    savedSnapshot.value = JSON.stringify(captured.config);
    savedProjectSnapshot.value = JSON.stringify(captured.project);
    status.value = dirty.value ? '保存完成，仍有新修改待保存' : '已保存配置与工作区，原版本已备份';
    cacheDraft();
    return true;
  } catch (error) {
    if ((error as any)?.payload?.validation) validation.value = (error as any).payload.validation;
    status.value = error instanceof Error ? error.message : '保存失败';
    return false;
  } finally {
    busy.value = false;
  }
}

async function startGame() {
  if (busy.value) return;
  if (dirty.value && !await save()) return;
  busy.value = true;
  try {
    const result = await api.startGame();
    gameStatus.value = result.status;
    status.value = result.message;
  } catch (error) { status.value = error instanceof Error ? error.message : '启动游戏失败'; }
  finally { busy.value = false; }
}

async function stopGame() {
  if (busy.value) return;
  busy.value = true;
  try {
    const result = await api.stopGame();
    gameStatus.value = result.status;
    status.value = result.message;
  } catch (error) { status.value = error instanceof Error ? error.message : '停止游戏失败'; }
  finally { busy.value = false; }
}

async function refreshStatus() {
  try { gameStatus.value = (await api.gameStatus()).status; }
  catch { gameStatus.value = {process_alive: false, message: '无法确认游戏状态'}; }
}

function undo() {
  const value = history.undo();
  if (value) { config.value = value.config; project.value = mergeEditorProject(value.project); status.value = '已撤销'; }
}

function redo() {
  const value = history.redo();
  if (value) { config.value = value.config; project.value = mergeEditorProject(value.project); status.value = '已重做'; }
}

function handleKeydown(event: KeyboardEvent) {
  if (busy.value) return;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); void save(); }
  else if ((event.target as HTMLElement)?.closest('input, textarea, select, [contenteditable="true"], .media-canvas')) return;
  else if ((event.ctrlKey || event.metaKey) && event.shiftKey && event.key.toLowerCase() === 'z') { event.preventDefault(); redo(); }
  else if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') { event.preventDefault(); undo(); }
  else if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'y') { event.preventDefault(); redo(); }
}

function replaceConfig(value: JsonObject) {
  config.value = value;
  history.push(snapshot());
  status.value = 'JSON 已替换';
}

function beforeUnload(event: BeforeUnloadEvent) {
  cacheDraft();
  if (dirty.value) { event.preventDefault(); event.returnValue = ''; }
}

function restore(value: JsonObject) {
  if (value.config) config.value = value.config;
  if (value.project) project.value = mergeEditorProject(value.project);
  changed();
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown);
  window.addEventListener('beforeunload', beforeUnload);
  void loadAll(true);
});
onUnmounted(() => {
  window.removeEventListener('keydown', handleKeydown);
  window.removeEventListener('beforeunload', beforeUnload);
  clearTimeout(draftTimer);
});
watch([config, project], () => {
  clearTimeout(draftTimer);
  draftTimer = setTimeout(cacheDraft, 250);
}, {deep: true});
</script>

<template>
  <div class="editor-app">
    <div v-if="reloadConfirm" class="local-confirm"><div><p>重新加载会丢弃当前未保存的修改。</p><button class="button ghost" @click="reloadConfirm=false">保留修改</button><button class="button primary" @click="reloadConfirm=false;loadAll(false,true)">丢弃并加载</button></div></div>
    <div v-if="draftCandidate" class="draft-banner">发现上次的未保存草稿。<button class="button primary" @click="restore(draftCandidate);draftCandidate=null">恢复草稿</button><button class="button ghost" @click="draftCandidate=null">使用已保存版本</button></div>
    <header class="topbar">
      <div class="brand"><div class="brand-mark">羽</div><div><strong>夜鸦修改器</strong><span>GODOT · 动作 / 战斗 / 素材</span></div></div>
      <div class="top-status"><span class="status-dot" :class="{live: running}"></span>{{ running ? '游戏运行中' : '游戏未运行' }} · {{ status }}</div>
      <div class="top-actions"><button class="button ghost" :disabled="busy" @click="undo">撤销</button><button class="button ghost" :disabled="busy" @click="redo">重做</button><button class="button ghost" :disabled="busy" @click="validate">校验</button><button class="button primary" :disabled="busy" @click="save">{{ dirty ? '保存修改' : '已保存' }}</button><button class="button secondary" :disabled="busy" @click="startGame">{{ running ? '保存并刷新游戏' : '保存并打开游戏' }}</button><button v-if="running" class="button ghost" :disabled="busy" @click="stopGame">停止</button><button class="button ghost" @click="refreshStatus">状态</button></div>
    </header>
    <div class="editor-body">
      <aside class="sidebar"><div class="sidebar-caption">WORKSPACES</div><button v-for="section in sections" :key="section.id" class="nav-item" :class="{active: activeSection === section.id}" @click="setSection(section.id)"><span>{{ section.icon }}</span>{{ section.label }}<i v-if="section.id === 'json'">ADV</i></button><div class="sidebar-footer"><div class="save-state" :class="{dirty}"><span></span>{{ dirty ? '未保存' : '已同步' }}</div><button class="button wide ghost" :disabled="busy" @click="loadAll(false)">重新加载</button></div></aside>
      <main class="content" v-if="config.settings">
        <OverviewPanel v-if="activeSection === 'overview'" :config="config" :validation="validation" :asset-count="assets.length" @changed="changed" />
        <AnimationStudio v-else-if="activeSection === 'animations'" :config="config" :assets="assets" :workspace="project.documents" :selected-move="currentMove" @changed="changed" @assets-reloaded="assets=$event" />
        <StagePanel v-else-if="activeSection === 'stage'" :config="config" :assets="assets" :viewport="project.workspace" @changed="changed" @selected-asset="selectAsset" @assets-reloaded="assets = $event" />
        <AssetsPanel v-else-if="activeSection === 'assets'" :config="config" :assets="assets" :current-character="currentCharacter" :current-move="currentMove" :workspace="project.documents" @changed="changed" @assets-reloaded="assets = $event" @selected="selectAsset" />
        <CharactersPanel v-else-if="activeSection === 'characters'" :config="config" :assets="assets" :selected-index="project.workspace.selectedCharacter" @selected="project.workspace.selectedCharacter = $event" @changed="changed" />
        <CombatMatrix v-else-if="activeSection === 'moves'" :config="config" :selected-index="project.workspace.selectedMove" @selected="project.workspace.selectedMove = $event" @changed="changed" />
        <FeedbackPanel v-else-if="activeSection === 'feedback'" :config="config" :assets="assets" @changed="changed" />
        <RecoveryPanel v-else-if="activeSection === 'recovery'" @restore="restore" @assets-reloaded="assets = $event" />
        <JsonPanel v-else :config="config" @replaced="replaceConfig" />
      </main>
    </div>
  </div>
</template>
