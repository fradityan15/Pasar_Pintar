<script setup>
import { ORDER_STATUS } from '@/lib/status'
defineProps({ status: String })
</script>

<template>
  <span class="badge" :class="ORDER_STATUS[status]?.cls">{{ ORDER_STATUS[status]?.label ?? status }}</span>
</template>
