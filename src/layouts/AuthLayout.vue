<script setup>
import { RouterLink, RouterView } from 'vue-router'
</script>

<template>
  <div class="flex min-h-screen flex-col items-center justify-center bg-surface px-4 py-10">
    <RouterLink :to="{ name: 'home' }" class="mb-6 flex items-center gap-2 text-2xl font-bold">
      <img src="/logo-pasarpintar.png" alt="" class="h-10 w-10 rounded-lg object-cover" />
      PasarPintar
    </RouterLink>
    <div class="card w-full max-w-md p-6 sm:p-8"><RouterView /></div>
  </div>
</template>
