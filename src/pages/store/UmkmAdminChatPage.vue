<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import SellerDashboardSidebar from '@/components/SellerDashboardSidebar.vue'
import { formatTanggalJam } from '@/lib/format'
import { getMyUmkm } from '@/services/umkmPartnerService'
import { listSellerAdminMessages, sendSellerAdminMessage } from '@/services/sellerAdminChatService'

const umkm = ref(null)
const messages = ref([])
const body = ref('')
const loading = ref(true)
const sending = ref(false)
const error = ref('')
const notice = ref('')
let refreshTimer

async function loadMessages() {
  if (!umkm.value?.id) return
  try {
    messages.value = await listSellerAdminMessages(umkm.value.id) ?? []
    error.value = ''
  } catch (loadError) {
    error.value = loadError.message || 'Pesan tidak dapat dimuat.'
  }
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    umkm.value = await getMyUmkm()
    if (!umkm.value?.id) throw new Error('Data toko tidak ditemukan.')
    await loadMessages()
  } catch (loadError) {
    error.value = loadError.message || 'Chat admin tidak dapat dibuka.'
  } finally {
    loading.value = false
  }
}

async function send() {
  const message = body.value.trim()
  if (!message || sending.value) return
  sending.value = true
  error.value = ''
  notice.value = ''
  try {
    await sendSellerAdminMessage(umkm.value.id, message)
    body.value = ''
    await loadMessages()
    notice.value = 'Pesan berhasil dikirim ke admin.'
  } catch (sendError) {
    error.value = sendError.message || 'Pesan tidak dapat dikirim.'
  } finally {
    sending.value = false
  }
}

function refreshWhenVisible() {
  if (!document.hidden) loadMessages()
}

onMounted(() => {
  load()
  refreshTimer = window.setInterval(() => {
    if (!document.hidden) loadMessages()
  }, 8000)
  document.addEventListener('visibilitychange', refreshWhenVisible)
})

onBeforeUnmount(() => {
  window.clearInterval(refreshTimer)
  document.removeEventListener('visibilitychange', refreshWhenVisible)
})
</script>

<template>
  <div class="min-h-full bg-slate-50 lg:flex">
    <SellerDashboardSidebar :umkm="umkm" />
    <main class="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div class="mx-auto max-w-4xl">
        <header>
          <p class="text-sm font-medium text-emerald-700">Bantuan penjual</p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">Chat Admin</h1>
          <p class="mt-1.5 text-sm text-slate-500">Laporkan kendala toko atau pesanan. Balasan admin akan muncul di percakapan ini.</p>
        </header>

        <p v-if="error" class="mt-5 rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</p>
        <p v-if="notice" class="mt-5 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-sm text-emerald-800" role="status">{{ notice }}</p>

        <section class="mt-6 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200" aria-label="Percakapan dengan admin">
          <div class="border-b border-slate-100 px-5 py-4">
            <h2 class="font-semibold text-slate-900">{{ umkm?.name || 'Toko Anda' }} · Admin PasarPintar</h2>
            <p class="mt-1 text-xs text-slate-500">Pesan diperbarui otomatis setiap beberapa detik.</p>
          </div>
          <div v-if="loading" class="h-64 animate-pulse bg-slate-50" />
          <div v-else class="max-h-[55vh] min-h-64 space-y-3 overflow-y-auto bg-slate-50 p-4 sm:p-6">
            <p v-if="!messages.length" class="py-12 text-center text-sm text-slate-500">Belum ada pesan. Kirim laporan atau pertanyaan untuk memulai percakapan.</p>
            <article
              v-for="message in messages"
              :key="message.id"
              class="ml-auto max-w-[85%] rounded-2xl rounded-br-sm bg-emerald-700 px-4 py-3 text-white"
              :class="message.sender_type === 'seller' ? 'ml-auto' : '!ml-0 bg-white !text-slate-800 ring-1 ring-slate-200'"
            >
              <p class="mb-1 text-[11px] font-semibold opacity-75">{{ message.sender_type === 'seller' ? 'Anda' : 'Admin' }}</p>
              <p class="whitespace-pre-wrap break-words text-sm">{{ message.body }}</p>
              <time class="mt-2 block text-right text-[10px] opacity-70" :datetime="message.created_at">{{ formatTanggalJam(message.created_at) }}</time>
            </article>
          </div>
          <form class="border-t border-slate-100 p-4 sm:p-5" @submit.prevent="send">
            <label for="seller-admin-message" class="sr-only">Tulis pesan untuk admin</label>
            <textarea
              id="seller-admin-message"
              v-model="body"
              class="input min-h-24 w-full resize-y"
              maxlength="2000"
              placeholder="Jelaskan masalah yang Anda alami…"
              required
            />
            <div class="mt-3 flex items-center justify-between gap-3">
              <span class="text-xs text-slate-500">{{ body.length }}/2000 karakter</span>
              <button class="btn min-h-10 bg-gray-900 px-5 text-white hover:bg-black" type="submit" :disabled="sending || !body.trim()">
                {{ sending ? 'Mengirim…' : 'Kirim ke admin' }}
              </button>
            </div>
          </form>
        </section>
      </div>
    </main>
  </div>
</template>
