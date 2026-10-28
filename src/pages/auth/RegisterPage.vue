<script setup>
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()

const fullName = ref('')
const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')
const needsConfirmation = ref(false)

async function submit() {
  loading.value = true
  error.value = ''
  try {
    const res = await auth.signUp(fullName.value.trim(), email.value.trim(), password.value)
    if (res.needsConfirmation) needsConfirmation.value = true
    else router.push({ name: 'home' })
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <template v-if="needsConfirmation">
    <h1 class="text-2xl font-bold">Cek email Anda</h1>
    <p class="mt-2 text-sm text-muted">
      Kami mengirim tautan verifikasi ke {{ email }}. Buka tautan itu, lalu masuk.
    </p>
    <RouterLink :to="{ name: 'login' }" class="btn-primary mt-6 w-full">Ke halaman masuk</RouterLink>
  </template>

  <template v-else>
    <h1 class="text-2xl font-bold">Buat akun</h1>
    <p class="mt-1 text-sm text-muted">Daftar untuk mulai berbelanja produk UMKM.</p>

    <form class="mt-6 flex flex-col gap-4" @submit.prevent="submit">
      <div>
        <label for="nama" class="mb-1.5 block text-sm font-medium">Nama lengkap</label>
        <input id="nama" v-model="fullName" class="input" type="text" autocomplete="name" required />
      </div>
      <div>
        <label for="email" class="mb-1.5 block text-sm font-medium">Email</label>
        <input id="email" v-model="email" class="input" type="email" autocomplete="email" required />
      </div>
      <div>
        <label for="password" class="mb-1.5 block text-sm font-medium">Kata sandi</label>
        <input id="password" v-model="password" class="input" type="password" autocomplete="new-password" minlength="8" required />
        <p class="mt-1 text-xs text-muted">Minimal 8 karakter.</p>
      </div>
      <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
      <button class="btn-primary" type="submit" :disabled="loading">{{ loading ? 'Memproses…' : 'Daftar' }}</button>
    </form>

    <p class="mt-6 text-center text-sm text-muted">
      Sudah punya akun?
      <RouterLink :to="{ name: 'login' }" class="font-semibold text-gray-900">Masuk</RouterLink>
    </p>
  </template>
</template>
