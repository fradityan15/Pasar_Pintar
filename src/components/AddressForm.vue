<script setup>
import { reactive, ref } from 'vue'
import { createAddress } from '@/services/addressService'
import { useAuthStore } from '@/stores/auth'

const props = defineProps({ isFirst: Boolean })
const emit = defineEmits(['saved', 'cancel'])

const auth = useAuthStore()
const form = reactive({
  label: 'Rumah',
  recipient_name: auth.profile?.full_name ?? '',
  phone: auth.profile?.phone ?? '',
  province: '',
  city: '',
  street: '',
  postal_code: '',
})
const loading = ref(false)
const error = ref('')

async function submit() {
  loading.value = true
  error.value = ''
  try {
    const row = await createAddress(auth.user.id, { ...form, postal_code: form.postal_code || null }, props.isFirst)
    emit('saved', row.id)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <form class="grid gap-4 sm:grid-cols-2" @submit.prevent="submit">
    <div>
      <label for="a-label" class="mb-1.5 block text-sm font-medium">Label alamat</label>
      <input id="a-label" v-model="form.label" class="input" required />
    </div>
    <div>
      <label for="a-nama" class="mb-1.5 block text-sm font-medium">Nama penerima</label>
      <input id="a-nama" v-model="form.recipient_name" class="input" autocomplete="name" required />
    </div>
    <div>
      <label for="a-hp" class="mb-1.5 block text-sm font-medium">Nomor telepon</label>
      <input id="a-hp" v-model="form.phone" class="input" type="tel" autocomplete="tel" required />
    </div>
    <div>
      <label for="a-pos" class="mb-1.5 block text-sm font-medium">Kode pos (opsional)</label>
      <input id="a-pos" v-model="form.postal_code" class="input" inputmode="numeric" />
    </div>
    <div>
      <label for="a-prov" class="mb-1.5 block text-sm font-medium">Provinsi</label>
      <input id="a-prov" v-model="form.province" class="input" required />
    </div>
    <div>
      <label for="a-kota" class="mb-1.5 block text-sm font-medium">Kota / kabupaten</label>
      <input id="a-kota" v-model="form.city" class="input" required />
    </div>
    <div class="sm:col-span-2">
      <label for="a-jalan" class="mb-1.5 block text-sm font-medium">Alamat lengkap</label>
      <textarea id="a-jalan" v-model="form.street" class="input min-h-[88px] py-2.5" required></textarea>
    </div>
    <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg sm:col-span-2" role="alert">{{ error }}</p>
    <div class="flex gap-3 sm:col-span-2">
      <button class="btn-primary" type="submit" :disabled="loading">{{ loading ? 'Menyimpan…' : 'Simpan alamat' }}</button>
      <button v-if="!isFirst" class="btn-outline" type="button" @click="emit('cancel')">Batal</button>
    </div>
  </form>
</template>
