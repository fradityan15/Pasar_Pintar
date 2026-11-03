<script setup>
import { onMounted, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { formatTanggalJam } from '@/lib/format'
import { listAuditLogs } from '@/services/superAdminService'

const logs = ref([])
const loading = ref(true)
const error = ref('')
const action = ref('')
const entityType = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    logs.value = await listAuditLogs({ action: action.value, entityType: entityType.value })
  } catch (loadError) {
    error.value = loadError.message || 'Audit log tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <AdminPageHeader title="Audit Log" desc="Catatan append-only atas perubahan sensitif. Maksimal 500 entri terbaru." />
  <section class="card overflow-hidden">
    <form class="flex flex-col gap-3 border-b border-line p-4 sm:flex-row" @submit.prevent="load">
      <label class="sr-only" for="audit-action">Filter aksi</label>
      <input id="audit-action" v-model="action" class="input min-w-0 flex-1" placeholder="Cari aksi, mis. order.payment_confirmed" />
      <label class="sr-only" for="audit-entity">Filter entitas</label>
      <select id="audit-entity" v-model="entityType" class="input sm:max-w-56">
        <option value="">Semua entitas</option>
        <option value="profiles">Pengguna</option>
        <option value="orders">Pesanan</option>
        <option value="withdrawal_requests">Penarikan</option>
        <option value="vouchers">Voucher</option>
        <option value="umkm">UMKM</option>
        <option value="stock_movements">Penyesuaian stok</option>
        <option value="sikp_export">Ekspor SIKP</option>
      </select>
      <button class="btn-primary" type="submit" :disabled="loading">Terapkan</button>
    </form>

    <p v-if="error" class="m-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <p v-if="loading" class="p-6 text-sm text-muted">Memuat audit log…</p>
    <p v-else-if="!logs.length" class="p-6 text-sm text-muted">Tidak ada entri sesuai filter.</p>
    <div v-else class="overflow-x-auto">
      <table class="w-full min-w-[980px] text-left text-sm">
        <thead class="bg-surface text-xs text-muted">
          <tr>
            <th class="p-3 font-medium">Waktu</th><th class="p-3 font-medium">Aktor</th>
            <th class="p-3 font-medium">Aksi</th><th class="p-3 font-medium">Entitas</th>
            <th class="p-3 font-medium">Sebelum → Sesudah</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="entry in logs" :key="entry.id" class="border-t border-line align-top">
            <td class="whitespace-nowrap p-3">{{ formatTanggalJam(entry.created_at) }}</td>
            <td class="p-3"><span class="font-medium">{{ entry.actor_role }}</span><span class="mt-1 block font-mono text-[10px] text-muted">{{ entry.actor_id || 'system' }}</span></td>
            <td class="p-3 font-semibold">{{ entry.action }}</td>
            <td class="p-3"><span>{{ entry.entity_type }}</span><span class="mt-1 block font-mono text-[10px] text-muted">{{ entry.entity_id || '—' }}</span></td>
            <td class="max-w-[420px] p-3">
              <pre class="whitespace-pre-wrap break-all text-[11px] text-muted">{{ JSON.stringify({ before: entry.before, after: entry.after }, null, 2) }}</pre>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
