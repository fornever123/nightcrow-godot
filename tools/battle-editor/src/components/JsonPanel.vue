<script setup lang="ts">
import {ref} from 'vue';
import PanelShell from './PanelShell.vue';
import type {JsonObject} from '../types';

const props = defineProps<{config: JsonObject}>();
const emit = defineEmits<{replaced: [config: JsonObject]; changed: []}>();
const text = ref('');
const message = ref('');

function sync() {
  text.value = JSON.stringify(props.config, null, 2);
  message.value = '已格式化当前配置';
}

function apply() {
  try {
    const parsed = JSON.parse(text.value);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('根对象必须是 JSON 对象');
    emit('replaced', parsed as JsonObject);
    message.value = 'JSON 已应用，记得保存';
  } catch (error) {
    message.value = error instanceof Error ? error.message : 'JSON 格式错误';
  }
}

function copy() {
  void navigator.clipboard?.writeText(text.value);
  message.value = '已复制到剪贴板';
}

sync();
</script>

<template>
  <PanelShell title="JSON 高级模式" eyebrow="ADVANCED DATA" description="可视化编辑器写入的仍是同一份 battle.json；这里用于批量修改或排查特殊字段。">
    <template #actions><button class="button ghost" @click="sync">重新格式化</button><button class="button ghost" @click="copy">复制</button><button class="button primary" @click="apply">应用 JSON</button></template>
    <textarea v-model="text" class="json-editor" spellcheck="false"></textarea>
    <div class="form-hint">{{ message }}</div>
  </PanelShell>
</template>
