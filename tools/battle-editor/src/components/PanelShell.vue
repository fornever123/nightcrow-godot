<script setup lang="ts">
withDefaults(defineProps<{title: string; eyebrow?: string; description?: string}>(), {eyebrow: 'EDITOR'});
</script>

<template>
  <section class="panel-shell">
    <div class="panel-heading">
      <div><div class="eyebrow">{{ eyebrow }}</div><h3>{{ title }}</h3><p v-if="description">{{ description }}</p></div>
      <slot name="actions" />
    </div>
    <slot />
  </section>
</template>
