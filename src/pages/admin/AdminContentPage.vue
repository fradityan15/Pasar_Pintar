<script setup>
import AdminPageHeader from '@/components/AdminPageHeader.vue'
</script>

<template>
  <AdminPageHeader title="Manajemen Konten" desc="Kelola banner, promosi, dan materi visual yang tampil di marketplace." />

  <section class="card mt-4 px-6 py-12 text-center sm:px-10" aria-live="polite">
    <span class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-100 text-slate-500" aria-hidden="true">
      <svg viewBox="0 0 24 24" class="h-7 w-7" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="8.5" cy="9" r="1.5" /><path stroke-linecap="round" stroke-linejoin="round" d="m21 15-5-5L5 20" /></svg>
    </span>
    <h2 class="mt-4 text-lg font-semibold text-slate-900">Konten promosi belum tersedia</h2>
    <p class="mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-500">
      Database saat ini belum memiliki sumber data banner atau promosi. Konten contoh telah dihapus agar halaman tidak menampilkan materi yang belum diterbitkan dari Supabase.
    </p>
  </section>
</template>
