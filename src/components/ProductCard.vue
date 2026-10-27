<script setup>
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import { formatRupiah } from '@/lib/format'

const props = defineProps({
  product: { type: Object, required: true },
  adding: Boolean,
})
const emit = defineEmits(['add'])

const image = computed(() =>
  [...(props.product.product_images ?? [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url,
)
const origin = computed(() =>
  [props.product.umkm?.name, props.product.umkm?.regions?.name].filter(Boolean).join(' · '),
)
</script>

<template>
  <article class="relative flex flex-col gap-1 text-sm">
    <RouterLink :to="{ name: 'produk', params: { slug: product.slug } }" class="flex flex-col gap-1 hover:opacity-80">
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
    <button
      class="absolute right-2 top-2 flex h-10 w-10 items-center justify-center rounded-full bg-white text-emerald-800 shadow-md transition hover:bg-emerald-50 disabled:cursor-not-allowed disabled:opacity-50"
      type="button"
      :disabled="adding || product.stock < 1"
      :aria-label="`Tambah ${product.name} ke keranjang`"
      @click.stop="emit('add', product)"
    >
      <svg v-if="adding" class="h-5 w-5 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4Z" />
      </svg>
      <svg v-else viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
        <path stroke-linecap="round" stroke-linejoin="round" d="M3 3h2l2.4 12.2a2 2 0 0 0 2 1.6h8.8a2 2 0 0 0 2-1.6L22 8H6" />
        <circle cx="10" cy="21" r="1" /><circle cx="18" cy="21" r="1" />
      </svg>
    </button>
  </article>
</template>
