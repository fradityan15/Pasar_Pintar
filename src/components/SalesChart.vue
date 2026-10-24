<script setup>
import { computed } from 'vue'
import { formatRupiah } from '@/lib/format'

const props = defineProps({ data: { type: Array, default: () => [] } })
const W = 640, H = 220, L = 8, R = 8, T = 12, B = 28

const short = (s) => `${s.slice(8, 10)}/${s.slice(5, 7)}`
const max = computed(() => Math.max(1, ...props.data.map((d) => Number(d.omzet))))
const bars = computed(() => {
  const n = props.data.length || 1
  const bw = (W - L - R) / n
  return props.data.map((d, i) => {
    const h = (Number(d.omzet) / max.value) * (H - T - B)
    return {
      key: d.tanggal, x: L + i * bw + bw * 0.15, y: H - B - h, w: bw * 0.7, h,
      title: `${short(d.tanggal)}: ${formatRupiah(d.omzet)} (${d.jumlah_pesanan} pesanan)`,
    }
  })
})
</script>

<template>
  <svg :viewBox="`0 0 ${W} ${H}`" role="img" aria-label="Grafik batang omzet harian" class="h-56 w-full">
    <line :x1="L" :x2="W - R" :y1="H - B" :y2="H - B" stroke="#E8E8EC" />
    <rect v-for="b in bars" :key="b.key" :x="b.x" :y="b.y" :width="b.w" :height="Math.max(b.h, 1)" rx="3" fill="#6B9BD2">
      <title>{{ b.title }}</title>
    </rect>
    <text v-if="data.length" :x="L" :y="H - 8" font-size="12" fill="#5B6270">{{ short(data[0].tanggal) }}</text>
    <text v-if="data.length > 1" :x="W - R" :y="H - 8" font-size="12" fill="#5B6270" text-anchor="end">{{ short(data[data.length - 1].tanggal) }}</text>
  </svg>
</template>
