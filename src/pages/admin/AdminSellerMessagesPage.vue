<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import AdminPageHeader from '@/components/AdminPageHeader.vue'
import { formatTanggalJam } from '@/lib/format'
import {
  listAdminSellerMessages,
  listAdminSellerMessageThreads,
  sendAdminSellerMessage,
} from '@/services/sellerAdminChatService'

const threads = ref([])
const selectedUmkmId = ref('')
const messages = ref([])
const body = ref('')
const loading = ref(true)
const sending = ref(false)
const error = ref('')
const notice = ref('')
let refreshTimer

const selectedThread = computed(() => threads.value.find((thread) => thread.thread_umkm_id === selectedUmkmId.value))
const unreadTotal = computed(() => threads.value.reduce((sum, thread) => sum + Number(thread.unread_count || 0), 0))

async function loadThreads() {
  threads.value = await listAdminSellerMessageThreads() ?? []
  if (!selectedUmkmId.value && threads.value.length) selectedUmkmId.value = threads.value[0].thread_umkm_id
  if (selectedUmkmId.value && !threads.value.some((thread) => thread.thread_umkm_id === selectedUmkmId.value)) {
    selectedUmkmId.value = threads.value[0]?.thread_umkm_id ?? ''
  }
}

async function loadMessages() {
  if (!selectedUmkmId.value) {
    messages.value = []
    return
  }
  messages.value = await listAdminSellerMessages(selectedUmkmId.value) ?? []
}

async function load() {
  try {
    await loadThreads()
    await loadMessages()
    error.value = ''
  } catch (loadError) {
    notice.value = ''
    error.value = loadError.message || 'Pesan penjual tidak dapat dimuat.'
  } finally {
    loading.value = false
  }
}

async function selectThread(thread) {
  selectedUmkmId.value = thread.thread_umkm_id
  error.value = ''
  try {
    await loadMessages()
    await loadThreads()
  } catch (loadError) {
    error.value = loadError.message || 'Percakapan tidak dapat dibuka.'
  }
}

async function send() {
  const message = body.value.trim()
  if (!message || !selectedUmkmId.value || sending.value) return
  sending.value = true
  error.value = ''
  notice.value = ''
  try {
    await sendAdminSellerMessage(selectedUmkmId.value, message)
    body.value = ''
    await loadThreads()
    await loadMessages()
    error.value = ''
    notice.value = 'Balasan berhasil dikirim.'
  } catch (sendError) {
    notice.value = ''
    error.value = sendError.message || 'Balasan tidak dapat dikirim.'
  } finally {
    sending.value = false
  }
}

function refreshWhenVisible() {
  if (!document.hidden) load()
}

onMounted(() => {
  load()
  refreshTimer = window.setInterval(() => {
    if (!document.hidden) load()
  }, 8000)
  document.addEventListener('visibilitychange', refreshWhenVisible)
})

onBeforeUnmount(() => {
  window.clearInterval(refreshTimer)
  document.removeEventListener('visibilitychange', refreshWhenVisible)
})
</script>

<template>
  <AdminPageHeader title="Pesan Penjual" desc="Terima laporan kendala dan balas pesan dari toko penjual." />

  <p v-if="error" class="mb-4 rounded-xl bg-bad-bg p-3 text-sm text-bad-fg" role="alert">{{ error }}</p>
  <p v-if="notice" class="mb-4 rounded-xl bg-ok-bg p-3 text-sm text-ok-fg" role="status">{{ notice }}</p>
  <div class="mb-4 flex items-center justify-between rounded-xl bg-white px-4 py-3 text-sm ring-1 ring-slate-200">
    <span class="font-medium text-slate-700">Pesan belum dibaca</span>
    <span class="rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-bold text-emerald-800">{{ unreadTotal }}</span>
  </div>

  <section class="grid min-h-[32rem] overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200 lg:grid-cols-[18rem_minmax(0,1fr)]" aria-label="Kotak masuk penjual">
    <aside class="border-b border-slate-200 lg:border-b-0 lg:border-r">
      <div class="border-b border-slate-100 px-4 py-3">
        <h2 class="font-semibold text-slate-900">Percakapan</h2>
      </div>
      <p v-if="loading && !threads.length" class="p-4 text-sm text-slate-500">Memuat pesan…</p>
      <p v-else-if="!threads.length" class="p-4 text-sm text-slate-500">Belum ada pesan dari penjual.</p>
      <div v-else class="max-h-64 divide-y divide-slate-100 overflow-y-auto lg:max-h-[38rem]">
        <button
          v-for="thread in threads"
          :key="thread.thread_umkm_id"
          class="block w-full px-4 py-3 text-left hover:bg-slate-50"
          :class="selectedUmkmId === thread.thread_umkm_id ? 'bg-emerald-50' : ''"
          type="button"
          @click="selectThread(thread)"
        >
          <span class="flex items-center justify-between gap-2">
            <span class="truncate text-sm font-semibold text-slate-900">{{ thread.thread_umkm_name }}</span>
            <span v-if="thread.unread_count" class="rounded-full bg-emerald-700 px-2 py-0.5 text-[10px] font-bold text-white">{{ thread.unread_count }}</span>
          </span>
          <span class="mt-1 block truncate text-xs text-slate-500">{{ thread.last_sender_type === 'admin' ? 'Admin: ' : '' }}{{ thread.last_message }}</span>
          <time class="mt-1 block text-[10px] text-slate-400" :datetime="thread.last_message_at">{{ formatTanggalJam(thread.last_message_at) }}</time>
        </button>
      </div>
    </aside>

    <div class="flex min-h-[32rem] min-w-0 flex-col">
      <div class="border-b border-slate-100 px-5 py-3">
        <h2 class="font-semibold text-slate-900">{{ selectedThread?.thread_umkm_name || 'Pilih percakapan' }}</h2>
      </div>
      <div class="flex-1 space-y-3 overflow-y-auto bg-slate-50 p-4 sm:p-6">
        <p v-if="!selectedThread" class="py-16 text-center text-sm text-slate-500">Pilih percakapan di sebelah kiri.</p>
        <article
          v-for="message in messages"
          :key="message.id"
          class="max-w-[85%] rounded-2xl px-4 py-3"
          :class="message.sender_type === 'admin' ? 'ml-auto rounded-br-sm bg-gray-900 text-white' : 'rounded-bl-sm bg-white text-slate-800 ring-1 ring-slate-200'"
        >
          <p class="mb-1 text-[11px] font-semibold opacity-75">{{ message.sender_type === 'admin' ? 'Admin' : 'Penjual' }}</p>
          <p class="whitespace-pre-wrap break-words text-sm">{{ message.body }}</p>
          <time class="mt-2 block text-right text-[10px] opacity-70" :datetime="message.created_at">{{ formatTanggalJam(message.created_at) }}</time>
        </article>
      </div>
      <form class="border-t border-slate-100 p-4 sm:p-5" @submit.prevent="send">
        <label for="admin-seller-message" class="sr-only">Balas pesan penjual</label>
        <textarea
          id="admin-seller-message"
          v-model="body"
          class="input min-h-20 w-full resize-y"
          maxlength="2000"
          placeholder="Tulis balasan…"
          :disabled="!selectedThread"
        />
        <div class="mt-3 flex justify-end">
          <button class="btn-primary" type="submit" :disabled="sending || !selectedThread || !body.trim()">
            {{ sending ? 'Mengirim…' : 'Kirim balasan' }}
          </button>
        </div>
      </form>
    </div>
  </section>
</template>
