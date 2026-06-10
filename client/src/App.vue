<script setup>
import AuthGuard from '@core/auth/AuthGuard.vue'
</script>

<template>
  <AuthGuard>
    <RouterView />
  </AuthGuard>
</template>
