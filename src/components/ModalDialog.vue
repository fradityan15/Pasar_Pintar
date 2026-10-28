<script setup>
import { nextTick, ref, watch } from 'vue'

const props = defineProps({ open: Boolean, title: String })
const emit = defineEmits(['close'])
const el = ref(null)

watch(() => props.open, async (v) => {
  await nextTick()
  if (!el.value) return
  if (v && !el.value.open) el.value.showModal()
  if (!v && el.value.open) el.value.close()
}, { immediate: true })
</script>

<template>
  <dialog ref="el" class="w-full max-w-lg rounded-2xl p-0 text-ink backdrop:bg-black/40" @close="emit('close')" @click.self="emit('close')">
    <div class="p-6">
      <div class="flex items-start justify-between gap-4">
        <h2 class="text-lg font-semibold">{{ title }}</h2>
        <button type="button" class="h-8 w-8 rounded-lg border border-gray-900 text-xl leading-none text-gray-900 hover:bg-gray-50" aria-label="Tutup" @click="emit('close')">×</button>
      </div>
      <div class="mt-4"><slot /></div>
    </div>
  </dialog>
</template>
