<script setup>
import AdminPageHeader from '@/components/AdminPageHeader.vue'
</script>

<template>
  <AdminPageHeader title="Keuangan" desc="Pantau saldo dan permintaan pencairan dana mitra UMKM." />

  <section class="card mt-4 px-6 py-12 text-center sm:px-10" aria-live="polite">
    <span class="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-100 text-slate-500" aria-hidden="true">
      <svg viewBox="0 0 24 24" class="h-7 w-7" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="5" width="18" height="14" rx="2" /><path stroke-linecap="round" d="M3 10h18M7 15h3" /></svg>
    </span>
    <h2 class="mt-4 text-lg font-semibold text-slate-900">Data pencairan belum tersedia</h2>
    <p class="mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-500">
      Database saat ini belum memiliki tabel permintaan pencairan maupun ledger saldo mitra. Angka dan transaksi tidak ditampilkan sampai sumber data keuangan tersedia.
    </p>
  </section>
</template>
