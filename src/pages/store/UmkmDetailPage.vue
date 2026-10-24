<script setup>
import { ref, watch } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import ProductCard from '@/components/ProductCard.vue'
import { getUmkmBySlug, listUmkmProducts } from '@/services/umkmService'

const route = useRoute()
const umkm = ref(null)
const products = ref([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  umkm.value = null
  try {
    umkm.value = await getUmkmBySlug(route.params.slug)
    products.value = umkm.value ? await listUmkmProducts(umkm.value.id) : []
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
watch(() => route.params.slug, load, { immediate: true })
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-6 sm:px-10">
    <RouterLink :to="{ name: 'umkm' }" class="text-sm font-medium text-muted">← Semua UMKM</RouterLink>

    <div v-if="loading" class="mt-6 h-40 animate-pulse rounded-2xl bg-surface"></div>
    <p v-else-if="error" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      {{ error }} <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <p v-else-if="!umkm" class="mt-6 rounded-xl bg-surface p-8 text-center font-semibold">UMKM tidak ditemukan</p>

    <template v-else>
      <section class="mt-4 rounded-2xl bg-surface p-6 sm:p-8">
        <h1 class="flex flex-wrap items-center gap-3 text-3xl font-bold">
          {{ umkm.name }}
          <span v-if="umkm.is_verified" class="badge bg-ok-bg text-ok-fg">Terverifikasi</span>
        </h1>
        <p v-if="umkm.regions" class="mt-2 text-sm text-muted">{{ umkm.regions.name }}, {{ umkm.regions.province }}</p>
        <p v-if="umkm.description" class="mt-4 max-w-2xl text-[15px] leading-relaxed text-[#374151]">{{ umkm.description }}</p>
        <p v-if="umkm.address" class="mt-3 text-sm text-muted">Alamat: {{ umkm.address }}</p>
      </section>

      <h2 class="mb-4 mt-8 text-xl font-semibold">Produk dari {{ umkm.name }}</h2>
      <p v-if="!products.length" class="rounded-xl bg-surface p-6 text-sm text-muted">Belum ada produk aktif dari UMKM ini.</p>
      <div v-else class="grid grid-cols-2 gap-4 md:grid-cols-4">
        <ProductCard v-for="p in products" :key="p.id" :product="p" />
      </div>
    </template>
  </div>
</template>
