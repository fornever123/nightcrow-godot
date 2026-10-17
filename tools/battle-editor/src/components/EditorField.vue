<script setup lang="ts">
const props = withDefaults(defineProps<{
  label: string;
  modelValue?: any;
  type?: 'text' | 'number' | 'checkbox' | 'textarea';
  step?: string | number;
  min?: string | number;
  max?: string | number;
  hint?: string;
}>(), {type: 'text'});

const emit = defineEmits<{update: [value: any]; changed: []}>();

function update(event: Event) {
  const target = event.target as HTMLInputElement | HTMLTextAreaElement;
  let value: any = target.value;
  if (props.type === 'checkbox') value = (target as HTMLInputElement).checked;
  if (props.type === 'number') value = value.trim() === '' ? null : Number(value);
  emit('update', value);
  emit('changed');
}
</script>

<template>
  <label class="editor-field" :class="{checkbox: type === 'checkbox'}">
    <span v-if="type === 'checkbox'" class="checkbox-line"><input type="checkbox" :checked="Boolean(modelValue)" @change="update"><b>{{ label }}</b></span>
    <template v-else>
      <span>{{ label }}</span>
      <textarea v-if="type === 'textarea'" :value="modelValue ?? ''" @change="update"></textarea>
      <input v-else :type="type" :value="modelValue ?? ''" :step="step" :min="min" :max="max" @change="update">
    </template>
    <small v-if="hint">{{ hint }}</small>
  </label>
</template>
