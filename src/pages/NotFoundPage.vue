<script setup>
import { RouterLink } from 'vue-router'
</script>

<template>
  <div class="flex min-h-screen flex-col items-center justify-center gap-3 px-4 text-center">
    <p class="text-5xl font-bold">404</p>
    <p class="text-muted">Halaman yang Anda cari tidak ditemukan.</p>
    <RouterLink :to="{ name: 'home' }" class="btn-primary mt-2">Kembali ke beranda</RouterLink>
  </div>
</template>
