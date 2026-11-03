<script setup>
import { onMounted, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { getSikpMapping, exportSikp, saveSikpMapping } from '@/services/superAdminService'

const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jakarta' })
const from = ref(today)
const to = ref(today)
const mappingJson = ref('')
const loading = ref(true)
const saving = ref(false)
const exporting = ref(false)
const error = ref('')
const notice = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    const mapping = await getSikpMapping()
    mappingJson.value = JSON.stringify(mapping.columns, null, 2)
  } catch (loadError) {
    error.value = loadError.message || 'Pemetaan ekspor tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function saveMapping() {
  saving.value = true
  error.value = ''
  notice.value = ''
  try {
    const columns = JSON.parse(mappingJson.value)
    if (!Array.isArray(columns)) throw new Error('Pemetaan harus berupa array JSON.')
    await saveSikpMapping(columns)
    notice.value = 'Pemetaan kolom disimpan.'
    await load()
  } catch (saveError) {
    error.value = saveError instanceof SyntaxError
      ? 'Format JSON tidak valid.'
      : saveError.message || 'Pemetaan tidak dapat disimpan.'
  } finally {
    saving.value = false
  }
}

async function downloadExport() {
  exporting.value = true
  error.value = ''
  notice.value = ''
  try {
    if (!from.value || !to.value || to.value < from.value) throw new Error('Rentang tanggal tidak valid.')
    const csv = await exportSikp(from.value, to.value)
    const url = URL.createObjectURL(new Blob(['\ufeff', csv], { type: 'text/csv;charset=utf-8' }))
    const link = Object.assign(document.createElement('a'), {
      href: url,
      download: `sikp-placeholder_${from.value}_${to.value}.csv`,
    })
    link.click()
    URL.revokeObjectURL(url)
    notice.value = 'Ekspor placeholder berhasil dibuat dan dicatat pada audit log.'
  } catch (exportError) {
    error.value = exportError.message || 'Ekspor tidak dapat dibuat.'
  } finally {
    exporting.value = false
  }
}
</script>

<template>
  <AdminPageHeader title="Ekspor SIKP" desc="Ekspor CSV sementara menggunakan pemetaan yang dapat disesuaikan." />
  <p class="mb-5 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm leading-6 text-amber-950" role="alert">
    Format resmi SIKP belum tersedia. Semua header bawaan bertanda PLACEHOLDER dan bukan klaim kesesuaian dengan templat resmi. Ganti pemetaan setelah spesifikasi resmi diterima.
  </p>
  <p v-if="error" class="mb-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
  <p v-if="notice" class="mb-4 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>

  <section class="card p-5">
    <h2 class="font-semibold">Pemetaan kolom CSV</h2>
    <p class="mt-1 text-sm text-muted">Sumber data dibatasi oleh server ke: <code>order_no</code>, <code>paid_date</code>, <code>order_total</code>, dan <code>umkm_names</code>. Tidak ada nama, telepon, alamat, atau identitas pelanggan yang diekspor.</p>
    <label for="sikp-mapping" class="sr-only">Konfigurasi pemetaan JSON</label>
    <textarea id="sikp-mapping" v-model="mappingJson" class="input mt-4 min-h-64 w-full font-mono text-xs" spellcheck="false" :disabled="loading || saving"></textarea>
    <button class="btn-outline mt-3" type="button" :disabled="loading || saving" @click="saveMapping">{{ saving ? 'Menyimpan…' : 'Simpan pemetaan' }}</button>
  </section>

  <section class="card mt-5 p-5">
    <h2 class="font-semibold">Buat ekspor</h2>
    <p class="mt-1 text-sm text-muted">Data pesanan dibayar dan tidak dibatalkan, difilter berdasarkan tanggal pembayaran WIB. Maksimal 367 hari per ekspor.</p>
    <form class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end" @submit.prevent="downloadExport">
      <label class="text-sm font-medium">Dari tanggal WIB<input v-model="from" class="input mt-1 block" type="date" required /></label>
      <label class="text-sm font-medium">Sampai tanggal WIB<input v-model="to" class="input mt-1 block" type="date" required /></label>
      <button class="btn-primary" type="submit" :disabled="exporting || loading">{{ exporting ? 'Membuat CSV…' : 'Ekspor CSV placeholder' }}</button>
    </form>
  </section>
</template>
