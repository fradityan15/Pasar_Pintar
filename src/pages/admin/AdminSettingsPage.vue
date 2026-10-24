<script setup>
import AdminPageHeader from '@/components/AdminPageHeader.vue'
</script>

<template>
  <AdminPageHeader title="Pengaturan" desc="Preferensi umum dan konfigurasi marketplace PasarPintar." />

  <section class="card mt-4 px-6 py-12 text-center sm:px-10" aria-live="polite">
    <span class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-100 text-slate-500" aria-hidden="true">
      <svg viewBox="0 0 24 24" class="h-7 w-7" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3" /><path stroke-linecap="round" stroke-linejoin="round" d="m19.4 15 .1.1a1.7 1.7 0 1 1-2.4 2.4l-.1-.1a1.7 1.7 0 0 0-2.9 1.2v.2a1.7 1.7 0 1 1-3.4 0v-.2a1.7 1.7 0 0 0-2.9-1.2l-.1.1a1.7 1.7 0 1 1-2.4-2.4l.1-.1a1.7 1.7 0 0 0-1.2-2.9H4a1.7 1.7 0 1 1 0-3.4h.2a1.7 1.7 0 0 0 1.2-2.9l-.1-.1a1.7 1.7 0 1 1 2.4-2.4l.1.1a1.7 1.7 0 0 0 2.9-1.2V2a1.7 1.7 0 1 1 3.4 0v.2a1.7 1.7 0 0 0 2.9 1.2l.1-.1a1.7 1.7 0 1 1 2.4 2.4l-.1.1a1.7 1.7 0 0 0 1.2 2.9h.2a1.7 1.7 0 1 1 0 3.4h-.2a1.7 1.7 0 0 0-1.2 2.9Z" /></svg>
    </span>
    <h2 class="mt-4 text-lg font-semibold text-slate-900">Pengaturan tersimpan belum tersedia</h2>
    <p class="mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-500">
      Belum ada tabel konfigurasi platform di Supabase. Nilai pengaturan contoh dan kontrol yang belum tersimpan telah dihapus supaya halaman tidak mengesankan konfigurasi sudah aktif.
    </p>
  </section>
</template>
