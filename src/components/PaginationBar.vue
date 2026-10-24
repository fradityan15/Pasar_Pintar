<script setup>
import { computed } from 'vue'

const props = defineProps({ page: Number, total: Number, pageSize: { type: Number, default: 15 } })
const emit = defineEmits(['change'])
const pages = computed(() => Math.max(1, Math.ceil(props.total / props.pageSize)))
</script>

<template>
  <nav v-if="pages > 1" class="flex items-center justify-between gap-3 pt-4 text-sm" aria-label="Halaman">
    <span class="text-muted">{{ total }} data</span>
    <div class="flex items-center gap-3">
      <button class="btn-outline" type="button" :disabled="page <= 1" @click="emit('change', page - 1)">Sebelumnya</button>
      <span>{{ page }} / {{ pages }}</span>
      <button class="btn-outline" type="button" :disabled="page >= pages" @click="emit('change', page + 1)">Berikutnya</button>
    </div>
  </nav>
</template>
