<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import LoadingBar from '@/components/LoadingBar.vue'
import { useTmdbKey } from '@/composables/useTmdbKey.js'

const router = useRouter()
useTmdbKey()
const pageTransition = ref('')
router.beforeEach((to, from) => {
  const a = from.meta.depth
  const b = to.meta.depth
  pageTransition.value = a === undefined || b === undefined || a === b ? '' : b > a ? 'page-push' : 'page-pop'
})
</script>

<template>
  <LoadingBar />
  <RouterView v-slot="{ Component, route }">
    <Transition :name="pageTransition" mode="out-in">
      <component :is="Component" :key="route.matched[0]?.path" />
    </Transition>
  </RouterView>
</template>

<style>
.page-push-enter-active,
.page-pop-enter-active {
  transition: transform 0.32s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.32s ease;
}
.page-push-leave-active,
.page-pop-leave-active {
  transition: transform 0.14s ease-in, opacity 0.14s ease-in;
}
.page-push-enter-from { transform: translateX(28%); opacity: 0; }
.page-push-leave-to { transform: translateX(-8%); opacity: 0; }
.page-pop-enter-from { transform: translateX(-8%); opacity: 0; }
.page-pop-leave-to { transform: translateX(28%); opacity: 0; }
@media (prefers-reduced-motion: reduce) {
  .page-push-enter-from, .page-push-leave-to, .page-pop-enter-from, .page-pop-leave-to { transform: none; }
}
</style>
