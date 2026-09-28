<script setup>
import { computed, provide, reactive } from 'vue'
import { RouterView, routeLocationKey, START_LOCATION } from 'vue-router'

// One page of the navigation stack (NavStack.vue). A page left underneath
// keeps seeing its own route through useRoute(), not the one on top — so the
// watchlist under Settings still knows which tab it was on.
const props = defineProps({
  route: { type: Object, required: true },
})

const fields = {}
for (const key of Object.keys(START_LOCATION)) fields[key] = computed(() => props.route[key])
provide(routeLocationKey, reactive(fields))
</script>

<template>
  <RouterView :route="route" />
</template>
