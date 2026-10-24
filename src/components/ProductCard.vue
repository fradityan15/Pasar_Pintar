<script setup>
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import { formatRupiah } from '@/lib/format'

const props = defineProps({ product: { type: Object, required: true } })

const image = computed(() =>
  [...(props.product.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url,
)
const origin = computed(() =>
  [props.product.umkm?.name, props.product.umkm?.regions?.name].filter(Boolean).join(' · '),
)
</script>

<template>
  <RouterLink :to="{ name: 'produk', params: { slug: product.slug } }" class="flex flex-col gap-1 text-sm hover:opacity-80">
    <div class="mb-2 aspect-square overflow-hidden rounded-[14px] bg-[#EDEDF0]">
      <img v-if="image" :src="image" :alt="product.name" loading="lazy" class="h-full w-full object-cover" />
      <div v-else class="flex h-full items-center justify-center text-xs text-[#4B5563]">Foto produk</div>
    </div>
    <h3 class="font-semibold">{{ product.name }}</h3>
    <p class="text-xs text-muted">{{ origin }}</p>
    <p class="flex items-center gap-2 font-semibold">
      {{ formatRupiah(product.price) }}
      <span v-if="product.stock === 0" class="badge bg-bad-bg text-bad-fg">Habis</span>
    </p>
  </RouterLink>
</template>
