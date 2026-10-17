<script setup lang="ts">
import {onMounted, ref} from 'vue';
import PanelShell from './PanelShell.vue';
import {api} from '../services/api';
import type {AssetFile, JsonObject} from '../types';

const emit = defineEmits<{restore: [value: JsonObject]; assetsReloaded: [assets: AssetFile[]]}>();
const backups = ref<{name: string; modifiedAt: string}[]>([]);
const trash = ref<{id: string; path: string; deletedAt: string}[]>([]);
const status = ref('');

async function load() {
  try {
    backups.value = (await api.backups()).backups;
    trash.value = (await api.trash()).entries;
  } catch (error) { status.value = String(error); }
}

async function restoreBackup(name: string) {
  try {
    const result = await api.loadBackup(name);
    emit('restore', name.startsWith('editor-project-') ? {project: result.value} : result.value.config ? result.value : {config: result.value});
    status.value = '备份已载入，检查后请保存';
  } catch (error) { status.value = String(error); }
}

async function restoreAsset(id: string) {
  try {
    const result = await api.restoreAsset(id);
    emit('assetsReloaded', (await api.loadAssets()).assets);
    status.value = `已恢复 ${result.path}`;
    await load();
  } catch (error) { status.value = String(error); }
}

onMounted(load);
</script>

<template>
  <div class="workspace-grid">
    <PanelShell title="版本备份" eyebrow="PROJECT RECOVERY" description="保存前自动备份。恢复先进入编辑器，不直接覆盖当前游戏。">
      <template #actions><button class="button ghost" @click="load">刷新</button></template>
      <div class="entity-list"><button v-for="backup in backups" :key="backup.name" class="entity-card" @click="restoreBackup(backup.name)"><b>{{ backup.name }}</b><span>{{ new Date(backup.modifiedAt).toLocaleString() }}</span></button></div>
      <div v-if="!backups.length" class="empty-state">还没有备份。</div>
    </PanelShell>
    <PanelShell title="素材回收站" eyebrow="ASSET RECOVERY" description="恢复原路径。若同名素材已存在，会拒绝覆盖。">
      <div v-for="entry in trash" :key="entry.id" class="sub-card"><b>{{ entry.path }}</b><p>{{ entry.deletedAt }}</p><button class="button secondary" @click="restoreAsset(entry.id)">恢复素材</button></div>
      <div v-if="!trash.length" class="empty-state">回收站为空。</div>
      <div class="form-hint">{{ status }}</div>
    </PanelShell>
  </div>
</template>
