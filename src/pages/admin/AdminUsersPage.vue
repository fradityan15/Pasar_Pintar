<script setup>
import { ref, watch } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import PaginationBar from '@/components/PaginationBar.vue'
import { useQueryState } from '@/composables/useQueryState'
import { useAuthStore } from '@/stores/auth'
import { listUsers, setUserRole } from '@/services/adminUserService'
import { formatTanggal } from '@/lib/format'

const auth = useAuthStore()
const { route, str, num, set } = useQueryState()
const items = ref([])
const total = ref(0)
const loading = ref(true)
const error = ref('')
const notice = ref('')
const search = ref(str('q'))
const tabs = [['', 'Semua'], ['admin', 'Admin'], ['customer', 'Pelanggan']]
let req = 0

async function load() {
  const id = ++req
  loading.value = true
  error.value = ''
  try {
    const r = await listUsers({ q: str('q'), role: str('role'), page: num('page') })
    if (id !== req) return
    items.value = r.items
    total.value = r.total
  } catch (e) {
    if (id === req) error.value = e.message
  } finally {
    if (id === req) loading.value = false
  }
}
watch(() => route.query, () => { if (route.name === 'admin-pengguna') load() }, { immediate: true })

async function ubahPeran(u, role) {
  const label = role === 'admin' ? 'Admin' : 'Pelanggan'
  if (!confirm(`Ubah peran ${u.full_name || 'pengguna ini'} menjadi ${label}?`)) { await load(); return }
  notice.value = ''
  error.value = ''
  try {
    await setUserRole(u.id, role)
    notice.value = `Peran diubah menjadi ${label}.`
  } catch (e) {
    error.value = e.message
  }
  await load()
}
</script>

<template>
  <AdminPageHeader title="Pengguna" desc="Kelola peran akun. Admin memiliki akses penuh ke panel ini." />

  <div class="card p-4 md:p-6">
    <div class="flex flex-wrap gap-x-5 border-b border-line" role="tablist" aria-label="Filter peran">
      <button
        v-for="[val, label] in tabs" :key="val" type="button" role="tab" :aria-selected="str('role') === val"
        class="-mb-px border-b-2 px-1 py-3 text-sm"
        :class="str('role') === val ? 'border-ink font-semibold text-ink' : 'border-transparent text-muted'"
        @click="set({ role: val, page: 1 })"
      >{{ label }}</button>
    </div>

    <form class="flex gap-2 py-4" role="search" @submit.prevent="set({ q: search.trim(), page: 1 })">
      <label for="cari-user" class="sr-only">Cari nama</label>
      <input id="cari-user" v-model="search" class="input max-w-sm" type="search" placeholder="Cari nama pengguna" />
      <button class="btn-primary" type="submit">Cari</button>
    </form>

    <p v-if="notice" class="mb-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="mb-3 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <div v-if="loading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="!items.length" class="rounded-xl bg-surface p-8 text-center text-sm text-muted">Pengguna tidak ditemukan.</p>
    <div v-else class="w-full overflow-x-auto">
      <table class="w-full min-w-[560px] text-left text-sm">
        <thead class="text-xs text-muted"><tr><th class="p-3 font-medium">Nama</th><th class="p-3 font-medium">Telepon</th><th class="p-3 font-medium">Bergabung</th><th class="p-3 font-medium">Peran</th></tr></thead>
        <tbody>
          <tr v-for="u in items" :key="u.id" class="border-t border-line">
            <td class="p-3 font-semibold">{{ u.full_name || '(tanpa nama)' }}<span v-if="u.id === auth.user?.id" class="badge ml-2 bg-info-bg text-info-fg">Anda</span></td>
            <td class="p-3">{{ u.phone || '-' }}</td>
            <td class="p-3 text-muted">{{ formatTanggal(u.created_at) }}</td>
            <td class="p-3">
              <label :for="`peran-${u.id}`" class="sr-only">Peran {{ u.full_name }}</label>
              <select :id="`peran-${u.id}`" class="input !min-h-[36px] max-w-[160px]" :value="u.role" :disabled="u.id === auth.user?.id" @change="ubahPeran(u, $event.target.value)">
                <option value="customer">Pelanggan</option>
                <option value="admin">Admin</option>
              </select>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <PaginationBar :page="num('page')" :total="total" @change="(p) => set({ page: p })" />
    <p class="mt-3 text-xs text-muted">Email tidak ditampilkan karena tersimpan di sistem autentikasi Supabase, bukan di tabel profil.</p>
  </div>
</template>
