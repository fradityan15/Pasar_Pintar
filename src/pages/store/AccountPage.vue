<script setup>
import { onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import ModalDialog from '@/components/ModalDialog.vue'
import { useAuthStore } from '@/stores/auth'
import { listAddresses, saveAddress } from '@/services/orderService'
import { deleteAddress, setDefaultAddress, updateAddress, updatePassword, updateProfile } from '@/services/accountService'
import { applyAsUmkm, getMyUmkm } from '@/services/umkmPartnerService'

const auth = useAuthStore()
const myUmkm = ref(null)
const umkmLoading = ref(true)
const umkmError = ref('')
const umkmFormOpen = ref(false)
const umkmSaving = ref(false)
const umkmFormError = ref('')
const umkmForm = reactive({ name: '', description: '', address: '', phone: auth.profile?.phone ?? '' })

async function loadMyUmkm() {
  umkmLoading.value = true
  umkmError.value = ''
  try {
    myUmkm.value = await getMyUmkm()
  } catch (e) {
    umkmError.value = e.message
  } finally {
    umkmLoading.value = false
  }
}

async function daftarUmkm() {
  umkmSaving.value = true
  umkmFormError.value = ''
  try {
    myUmkm.value = await applyAsUmkm(umkmForm)
    umkmFormOpen.value = false
    Object.assign(umkmForm, { name: '', description: '', address: '', phone: auth.profile?.phone ?? '' })
  } catch (e) {
    umkmFormError.value = e.message
  } finally {
    umkmSaving.value = false
  }
}

// ───── Profil ─────
const profile = reactive({ full_name: auth.profile?.full_name ?? '', phone: auth.profile?.phone ?? '' })
const profMsg = ref('')
const profErr = ref('')
const profBusy = ref(false)

async function simpanProfil() {
  profBusy.value = true
  profMsg.value = ''
  profErr.value = ''
  try {
    await updateProfile(auth.user.id, { full_name: profile.full_name.trim(), phone: profile.phone.trim() })
    auth.profile = { ...auth.profile, full_name: profile.full_name.trim(), phone: profile.phone.trim() || null }
    profMsg.value = 'Profil disimpan.'
  } catch (e) {
    profErr.value = e.message
  } finally {
    profBusy.value = false
  }
}

// ───── Kata sandi ─────
const pwd = ref('')
const pwdMsg = ref('')
const pwdErr = ref('')
async function ubahSandi() {
  pwdMsg.value = ''
  pwdErr.value = ''
  try {
    await updatePassword(pwd.value)
    pwd.value = ''
    pwdMsg.value = 'Kata sandi diubah.'
  } catch (e) {
    pwdErr.value = e.message
  }
}

// ───── Alamat ─────
const addresses = ref([])
const loading = ref(true)
const addrErr = ref('')
const open = ref(false)
const editingId = ref(null)
const saving = ref(false)
const formErr = ref('')
const blank = () => ({ label: 'Rumah', recipient_name: auth.profile?.full_name ?? '', phone: auth.profile?.phone ?? '', province: '', city: '', street: '', postal_code: '' })
const form = reactive(blank())

async function load() {
  try { addresses.value = await listAddresses() }
  catch (e) { addrErr.value = e.message }
  finally { loading.value = false }
}
onMounted(() => {
  load()
  loadMyUmkm()
})

function bukaForm(a = null) {
  editingId.value = a?.id ?? null
  Object.assign(form, a
    ? { label: a.label, recipient_name: a.recipient_name, phone: a.phone, province: a.province, city: a.city, street: a.street, postal_code: a.postal_code ?? '' }
    : blank())
  formErr.value = ''
  open.value = true
}

async function simpanAlamat() {
  saving.value = true
  formErr.value = ''
  try {
    const fields = { ...form, postal_code: form.postal_code.trim() || null }
    if (editingId.value) await updateAddress(editingId.value, fields)
    else await saveAddress(auth.user.id, fields, addresses.value.length === 0)
    open.value = false
    await load()
  } catch (e) {
    formErr.value = e.message
  } finally {
    saving.value = false
  }
}

async function jadikanUtama(a) {
  addrErr.value = ''
  try { await setDefaultAddress(auth.user.id, a.id); await load() } catch (e) { addrErr.value = e.message }
}
async function hapus(a) {
  if (!confirm(`Hapus alamat "${a.label}"? Pesanan lama tidak terpengaruh.`)) return
  addrErr.value = ''
  try { await deleteAddress(a.id); await load() } catch (e) { addrErr.value = e.message }
}
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 pb-16 pt-8 md:px-6 lg:px-8">
    <h1 class="text-3xl font-bold">Akun saya</h1>

    <section class="card mt-6 p-5">
      <h2 class="text-base font-semibold">Profil</h2>
      <form class="mt-4 grid gap-4 sm:grid-cols-2" @submit.prevent="simpanProfil">
        <div class="sm:col-span-2">
          <p class="mb-1.5 text-sm font-medium">Email</p>
          <p class="flex min-h-[44px] items-center rounded-xl bg-surface px-3.5 text-sm">{{ auth.user?.email }}</p>
        </div>
        <div><label for="p-nama" class="mb-1.5 block text-sm font-medium">Nama lengkap</label><input id="p-nama" v-model="profile.full_name" class="input" autocomplete="name" required /></div>
        <div><label for="p-hp" class="mb-1.5 block text-sm font-medium">Nomor telepon</label><input id="p-hp" v-model="profile.phone" class="input" type="tel" autocomplete="tel" /></div>
        <div class="flex items-center gap-3 sm:col-span-2">
          <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md" type="submit" :disabled="profBusy">{{ profBusy ? 'Menyimpan…' : 'Simpan profil' }}</button>
          <p v-if="profMsg" class="text-sm text-ok-fg" role="status">{{ profMsg }}</p>
          <p v-if="profErr" class="text-sm text-bad-fg" role="alert">{{ profErr }}</p>
        </div>
      </form>
    </section>

    <section class="card mt-6 p-5">
      <h2 class="text-base font-semibold">Mitra UMKM</h2>
      <div v-if="umkmLoading" class="mt-4 h-20 animate-pulse rounded-xl bg-surface"></div>
      <p v-else-if="umkmError" class="mt-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">
        Data UMKM belum bisa dimuat: {{ umkmError }}
        <button class="ml-1 font-semibold underline" type="button" @click="loadMyUmkm">Coba lagi</button>
      </p>
      <div v-else-if="myUmkm?.status === 'pending'" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm leading-relaxed text-amber-900" role="status">
        <p class="font-semibold">Pendaftaran sedang ditinjau</p>
        <p class="mt-1">Pendaftaran UMKM Anda sedang ditinjau oleh Admin PasarPintar. Mohon tunggu proses verifikasi.</p>
      </div>
      <div v-else-if="myUmkm?.status === 'active' && myUmkm.is_active" class="mt-4 rounded-xl border border-ok-fg/15 bg-ok-bg p-4">
        <p class="font-semibold text-ok-fg">Selamat bergabung, {{ myUmkm.name }}!</p>
        <p class="mt-1 text-sm text-ok-fg">UMKM Anda sudah aktif. Mulai kelola produk toko Anda.</p>
        <RouterLink :to="{ name: 'umkm-products' }" class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-4">Masuk ke Dasbor UMKM</RouterLink>
      </div>
      <div v-else-if="myUmkm" class="mt-4 rounded-xl border border-line bg-surface p-4 text-sm text-muted" role="status">
        UMKM {{ myUmkm.name }} saat ini tidak aktif. Hubungi Admin PasarPintar untuk informasi lebih lanjut.
      </div>
      <div v-else-if="!umkmFormOpen" class="mt-4 rounded-xl bg-surface p-5">
        <p class="font-semibold">Punya usaha lokal?</p>
        <p class="mt-1 text-sm text-muted">Daftarkan UMKM Anda untuk bergabung dan menjual produk di PasarPintar.</p>
        <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md mt-4" type="button" @click="umkmFormOpen = true">Daftar sebagai Mitra UMKM</button>
      </div>
      <form v-else class="mt-4 flex flex-col gap-3" @submit.prevent="daftarUmkm">
        <div>
          <label for="umkm-name" class="mb-1.5 block text-sm font-medium">Nama UMKM</label>
          <input id="umkm-name" v-model="umkmForm.name" class="input" maxlength="120" required />
        </div>
        <div>
          <label for="umkm-description" class="mb-1.5 block text-sm font-medium">Deskripsi</label>
          <textarea id="umkm-description" v-model="umkmForm.description" class="input py-2" rows="3" maxlength="2000"></textarea>
        </div>
        <div>
          <label for="umkm-address" class="mb-1.5 block text-sm font-medium">Alamat</label>
          <input id="umkm-address" v-model="umkmForm.address" class="input" maxlength="500" />
        </div>
        <div>
          <label for="umkm-phone" class="mb-1.5 block text-sm font-medium">Nomor telepon</label>
          <input id="umkm-phone" v-model="umkmForm.phone" class="input" type="tel" autocomplete="tel" />
        </div>
        <p v-if="umkmFormError" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ umkmFormError }}</p>
        <div class="flex flex-wrap gap-2">
          <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md" type="submit" :disabled="umkmSaving">{{ umkmSaving ? 'Mengirim…' : 'Kirim pendaftaran' }}</button>
          <button class="btn-outline" type="button" :disabled="umkmSaving" @click="umkmFormOpen = false">Batal</button>
        </div>
      </form>
    </section>

    <section class="card mt-6 p-5">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-base font-semibold">Alamat pengiriman</h2>
        <button class="btn-outline" type="button" @click="bukaForm()">Tambah alamat</button>
      </div>
      <p v-if="addrErr" class="mt-3 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ addrErr }}</p>
      <div v-if="loading" class="mt-4 h-24 animate-pulse rounded-xl bg-surface"></div>
      <p v-else-if="!addresses.length" class="mt-4 rounded-xl bg-surface p-6 text-center text-sm text-muted">Belum ada alamat tersimpan.</p>
      <ul v-else class="mt-4 flex flex-col gap-3">
        <li v-for="a in addresses" :key="a.id" class="rounded-xl border border-line p-4 text-sm">
          <p class="font-semibold">{{ a.label }} <span v-if="a.is_default" class="badge ml-1 bg-ok-bg text-ok-fg">Utama</span></p>
          <p class="mt-1">{{ a.recipient_name }} ({{ a.phone }})</p>
          <p class="text-muted">{{ a.street }}, {{ a.city }}, {{ a.province }} {{ a.postal_code }}</p>
          <div class="mt-2 flex gap-4 font-semibold">
            <button type="button" class="underline" @click="bukaForm(a)">Ubah</button>
            <button v-if="!a.is_default" type="button" class="underline" @click="jadikanUtama(a)">Jadikan utama</button>
            <button type="button" class="text-gray-900 underline" @click="hapus(a)">Hapus</button>
          </div>
        </li>
      </ul>
    </section>

    <section class="card mt-6 p-5">
      <h2 class="text-base font-semibold">Ubah kata sandi</h2>
      <form class="mt-4 flex max-w-sm flex-col gap-3" @submit.prevent="ubahSandi">
        <div>
          <label for="p-sandi" class="mb-1.5 block text-sm font-medium">Kata sandi baru</label>
          <input id="p-sandi" v-model="pwd" class="input" type="password" autocomplete="new-password" minlength="8" required />
          <p class="mt-1 text-xs text-muted">Minimal 8 karakter.</p>
        </div>
        <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md w-fit" type="submit">Ubah kata sandi</button>
        <p v-if="pwdMsg" class="text-sm text-ok-fg" role="status">{{ pwdMsg }}</p>
        <p v-if="pwdErr" class="text-sm text-bad-fg" role="alert">{{ pwdErr }}</p>
      </form>
    </section>
  </div>

  <ModalDialog :open="open" :title="editingId ? 'Ubah alamat' : 'Tambah alamat'" @close="open = false">
    <form class="grid gap-3 sm:grid-cols-2" @submit.prevent="simpanAlamat">
      <div><label for="m-label" class="mb-1 block text-sm font-medium">Label</label><input id="m-label" v-model="form.label" class="input" required /></div>
      <div><label for="m-nama" class="mb-1 block text-sm font-medium">Nama penerima</label><input id="m-nama" v-model="form.recipient_name" class="input" required /></div>
      <div><label for="m-hp" class="mb-1 block text-sm font-medium">Nomor telepon</label><input id="m-hp" v-model="form.phone" class="input" type="tel" required /></div>
      <div><label for="m-prov" class="mb-1 block text-sm font-medium">Provinsi</label><input id="m-prov" v-model="form.province" class="input" required /></div>
      <div><label for="m-kota" class="mb-1 block text-sm font-medium">Kota/Kabupaten</label><input id="m-kota" v-model="form.city" class="input" required /></div>
      <div><label for="m-pos" class="mb-1 block text-sm font-medium">Kode pos</label><input id="m-pos" v-model="form.postal_code" class="input" inputmode="numeric" /></div>
      <div class="sm:col-span-2"><label for="m-jalan" class="mb-1 block text-sm font-medium">Alamat lengkap</label><input id="m-jalan" v-model="form.street" class="input" required /></div>
      <p v-if="formErr" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg sm:col-span-2" role="alert">{{ formErr }}</p>
      <div class="flex justify-end gap-2 sm:col-span-2">
        <button class="btn-outline" type="button" @click="open = false">Batal</button>
        <button class="btn bg-gray-900 text-white transition-colors hover:bg-black hover:shadow-md" type="submit" :disabled="saving">{{ saving ? 'Menyimpan…' : 'Simpan' }}</button>
      </div>
    </form>
  </ModalDialog>
</template>
