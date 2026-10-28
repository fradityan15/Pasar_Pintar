<script setup>
import { ref } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

// Hanya terima redirect ke path internal.
function safeRedirect() {
  const r = String(route.query.redirect ?? '')
  return r.startsWith('/') && !r.startsWith('//') ? r : null
}

async function submit() {
  loading.value = true
  error.value = ''
  try {
    await auth.signIn(email.value.trim(), password.value)
    router.push(safeRedirect() ?? { name: auth.isAdmin ? 'admin-dashboard' : 'home' })
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <h1 class="text-2xl font-bold">Masuk</h1>
  <p class="mt-1 text-sm text-muted">Masuk untuk berbelanja atau mengelola toko.</p>

  <form class="mt-6 flex flex-col gap-4" @submit.prevent="submit">
    <div>
      <label for="email" class="mb-1.5 block text-sm font-medium">Email</label>
      <input id="email" v-model="email" class="input" type="email" autocomplete="email" required />
    </div>
    <div>
      <label for="password" class="mb-1.5 block text-sm font-medium">Kata sandi</label>
      <input id="password" v-model="password" class="input" type="password" autocomplete="current-password" required />
    </div>
    <p v-if="error" class="rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
    <button class="btn-primary" type="submit" :disabled="loading">{{ loading ? 'Memproses…' : 'Masuk' }}</button>
  </form>

  <p class="mt-6 text-center text-sm text-muted">
    Belum punya akun?
    <RouterLink :to="{ name: 'register' }" class="font-semibold text-gray-900">Daftar</RouterLink>
  </p>
</template>
