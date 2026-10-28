<script setup>
defineProps({ label: String, value: [String, Number] })
</script>

<template>
  <div class="rounded-xl bg-white p-4 shadow-sm ring-1 ring-line">
    <p class="text-[13px] text-muted">{{ label }}</p>
    <p class="mt-1 text-[26px] font-bold leading-tight text-gray-900">{{ value }}</p>
  </div>
</template>
