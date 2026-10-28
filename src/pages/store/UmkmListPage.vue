<script setup>
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { listUmkm } from '@/services/umkmService'

const items = ref([])
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try { items.value = await listUmkm() }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <h1 class="text-3xl font-bold">UMKM mitra</h1>
    <p class="mt-2 max-w-xl text-sm text-muted">Kenali pelaku usaha di balik produk yang Anda beli.</p>

    <p v-if="error" class="mt-6 rounded-xl bg-bad-bg p-4 text-sm text-bad-fg" role="alert">
      UMKM belum bisa dimuat: {{ error }}
      <button class="ml-2 font-semibold underline" type="button" @click="load">Coba lagi</button>
    </p>
    <div v-else-if="loading" class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <div v-for="n in 3" :key="n" class="h-36 animate-pulse rounded-xl bg-surface"></div>
    </div>
    <p v-else-if="!items.length" class="mt-6 rounded-xl bg-surface p-8 text-center text-sm text-muted">Belum ada UMKM terdaftar.</p>
    <ul v-else class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <li v-for="u in items" :key="u.id">
        <RouterLink :to="{ name: 'umkm-detail', params: { slug: u.slug } }" class="card block h-full p-5 hover:bg-gray-50">
          <p class="flex flex-wrap items-center gap-2 text-lg font-semibold">
            {{ u.name }}
            <span v-if="u.is_verified" class="badge bg-ok-bg text-ok-fg">Terverifikasi</span>
          </p>
          <p v-if="u.regions" class="mt-1 text-sm text-muted">{{ u.regions.name }}, {{ u.regions.province }}</p>
          <p v-if="u.description" class="mt-3 line-clamp-3 text-sm text-[#374151]">{{ u.description }}</p>
        </RouterLink>
      </li>
    </ul>
  </div>
</template>
