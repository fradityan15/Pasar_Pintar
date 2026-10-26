<script setup>
import { onMounted, reactive, ref, watch } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import ModalDialog from '@/components/ModalDialog.vue'
import { listRegions, listUmkmAdmin, saveRegion, saveUmkm } from '@/services/adminCatalogService'
import { slugify } from '@/lib/slug'

const items = ref([])
const regions = ref([])
const loading = ref(true)
const error = ref('')
const notice = ref('')
const open = ref(false)
const regionOpen = ref(false)
const editingId = ref(null)
const saving = ref(false)
const formError = ref('')
const slugTouched = ref(false)
const form = reactive({ name: '', slug: '', description: '', region_id: '', address: '', phone: '', is_verified: false, is_active: true })
const region = reactive({ name: '', province: '' })

watch(() => form.name, (v) => { if (!slugTouched.value) form.slug = slugify(v) })

async function load() {
  loading.value = true
  error.value = ''
  try { ;[items.value, regions.value] = await Promise.all([listUmkmAdmin(), listRegions()]) }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)

function bukaForm(u = null) {
  editingId.value = u?.id ?? null
  Object.assign(form, {
    name: u?.name ?? '', slug: u?.slug ?? '', description: u?.description ?? '', region_id: u?.region_id ?? '',
    address: u?.address ?? '', phone: u?.phone ?? '', is_verified: u?.is_verified ?? false, is_active: u?.is_active ?? true,
  })
  slugTouched.value = !!u
  formError.value = ''
  open.value = true
}

async function simpan() {
  saving.value = true
  formError.value = ''
  try {
    await saveUmkm(editingId.value, {
      name: form.name.trim(), slug: form.slug.trim(), description: form.description.trim() || null,
      region_id: form.region_id || null, address: form.address.trim() || null, phone: form.phone.trim() || null,
      is_verified: form.is_verified, is_active: form.is_active,
    })
    open.value = false
    notice.value = 'UMKM disimpan.'
    await load()
  } catch (e) {
    formError.value = e.message
  } finally {
    saving.value = false
  }
}

async function simpanDaerah() {
  formError.value = ''
  try {
    const r = await saveRegion({ name: region.name.trim(), province: region.province.trim() })
    regions.value = [...regions.value, r].sort((a, b) => a.name.localeCompare(b.name))
    form.region_id = r.id
    Object.assign(region, { name: '', province: '' })
    regionOpen.value = false
  } catch (e) {
    formError.value = e.message
    regionOpen.value = false
  }
}

async function toggleVerif(u) {
  try { await saveUmkm(u.id, { is_verified: !u.is_verified }); await load() } catch (e) { error.value = e.message }
}

async function setujuiPendaftaran(u) {
  error.value = ''
  try {
    await saveUmkm(u.id, { status: 'active', is_active: true })
    notice.value = `Pendaftaran ${u.name} disetujui.`
    await load()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <AdminPageHeader title="UMKM" desc="Kelola profil toko UMKM dan verifikasinya.">
    <button class="btn-primary" type="button" @click="bukaForm()">Tambah UMKM</button>
  </AdminPageHeader>

  <div class="card p-5">
    <p v-if="notice" class="mb-3 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
    <p v-if="error" class="mb-3 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <div v-if="loading" class="h-40 animate-pulse rounded-xl bg-surface"></div>
    <p v-else-if="!items.length" class="rounded-xl bg-surface p-8 text-center text-sm text-muted">Belum ada UMKM.</p>
    <div v-else class="w-full overflow-x-auto">
      <table class="w-full min-w-[760px] text-left text-sm">
        <thead class="text-xs text-muted"><tr><th class="p-3 font-medium">Nama</th><th class="p-3 font-medium">Daerah</th><th class="p-3 font-medium">Telepon</th><th class="p-3 font-medium">Verifikasi</th><th class="p-3 font-medium">Pendaftaran</th><th class="p-3 font-medium">Toko</th><th class="p-3"></th></tr></thead>
        <tbody>
          <tr v-for="u in items" :key="u.id" class="border-t border-line">
            <td class="p-3 font-semibold">{{ u.name }}</td>
            <td class="p-3">{{ u.regions?.name || '-' }}</td>
            <td class="p-3">{{ u.phone || '-' }}</td>
            <td class="p-3"><span class="badge" :class="u.is_verified ? 'bg-ok-bg text-ok-fg' : 'bg-warn-bg text-warn-fg'">{{ u.is_verified ? 'Terverifikasi' : 'Belum' }}</span></td>
            <td class="p-3">
              <span class="badge" :class="u.status === 'active' ? 'bg-ok-bg text-ok-fg' : 'bg-warn-bg text-warn-fg'">{{ u.status === 'active' ? 'Disetujui' : 'Menunggu' }}</span>
            </td>
            <td class="p-3"><span class="badge" :class="u.is_active ? 'bg-ok-bg text-ok-fg' : 'bg-surface text-muted'">{{ u.is_active ? 'Aktif' : 'Nonaktif' }}</span></td>
            <td class="whitespace-nowrap p-3 text-right">
              <button v-if="u.status === 'pending'" class="font-semibold text-ok-fg underline" type="button" @click="setujuiPendaftaran(u)">Setujui</button>
              <button class="font-semibold underline" type="button" @click="bukaForm(u)">Ubah</button>
              <button class="ml-3 font-semibold underline" type="button" @click="toggleVerif(u)">{{ u.is_verified ? 'Cabut verifikasi' : 'Verifikasi' }}</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <ModalDialog :open="open" :title="editingId ? 'Ubah UMKM' : 'Tambah UMKM'" @close="open = false">
    <form class="flex flex-col gap-3" @submit.prevent="simpan">
      <div><label for="u-nama" class="mb-1.5 block text-sm font-medium">Nama usaha</label><input id="u-nama" v-model="form.name" class="input" required /></div>
      <div><label for="u-slug" class="mb-1.5 block text-sm font-medium">Slug</label><input id="u-slug" v-model="form.slug" class="input" pattern="[a-z0-9]+(-[a-z0-9]+)*" required @input="slugTouched = true" /></div>
      <div>
        <label for="u-daerah" class="mb-1.5 block text-sm font-medium">Daerah asal</label>
        <div class="flex gap-2">
          <select id="u-daerah" v-model="form.region_id" class="input">
            <option value="">Belum dipilih</option>
            <option v-for="r in regions" :key="r.id" :value="r.id">{{ r.name }}, {{ r.province }}</option>
          </select>
          <button class="btn-outline shrink-0" type="button" @click="regionOpen = true">Daerah baru</button>
        </div>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <div><label for="u-telp" class="mb-1.5 block text-sm font-medium">Telepon</label><input id="u-telp" v-model="form.phone" class="input" type="tel" /></div>
        <div><label for="u-alamat" class="mb-1.5 block text-sm font-medium">Alamat</label><input id="u-alamat" v-model="form.address" class="input" /></div>
      </div>
      <div><label for="u-desk" class="mb-1.5 block text-sm font-medium">Deskripsi</label><textarea id="u-desk" v-model="form.description" class="input py-2" rows="3"></textarea></div>
      <div class="flex gap-5 text-sm">
        <label class="flex items-center gap-2"><input v-model="form.is_verified" type="checkbox" /> Terverifikasi</label>
        <label class="flex items-center gap-2"><input v-model="form.is_active" type="checkbox" /> Aktif</label>
      </div>
      <p v-if="formError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ formError }}</p>
      <div class="flex justify-end gap-2">
        <button class="btn-outline" type="button" @click="open = false">Batal</button>
        <button class="btn-primary" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan' }}</button>
      </div>
    </form>
  </ModalDialog>

  <ModalDialog :open="regionOpen" title="Tambah daerah" @close="regionOpen = false">
    <form class="flex flex-col gap-3" @submit.prevent="simpanDaerah">
      <div><label for="r-nama" class="mb-1.5 block text-sm font-medium">Nama daerah/sentra</label><input id="r-nama" v-model="region.name" class="input" required /></div>
      <div><label for="r-prov" class="mb-1.5 block text-sm font-medium">Provinsi</label><input id="r-prov" v-model="region.province" class="input" required /></div>
      <div class="flex justify-end gap-2">
        <button class="btn-outline" type="button" @click="regionOpen = false">Batal</button>
        <button class="btn-primary" type="submit">Simpan daerah</button>
      </div>
    </form>
  </ModalDialog>
</template>
