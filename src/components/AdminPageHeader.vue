<script setup>
defineProps({ title: String, desc: String })
</script>

<template>
  <div class="mb-5 flex flex-wrap items-end justify-between gap-3">
    <div>
      <h1 class="text-2xl font-bold">{{ title }}</h1>
      <p v-if="desc" class="mt-1 text-sm text-muted">{{ desc }}</p>
    </div>
    <div class="flex flex-wrap gap-2"><slot /></div>
  </div>
</template>
