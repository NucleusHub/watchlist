<script setup>
// Plugin sections on a title's page, as on iOS (PluginItemSections).
// `item` is a library item, or { type, tmdbId, title } for a TMDb title that isn't added yet.
import { ref, computed, onMounted } from 'vue'
import { useRegistry } from '@core/useRegistry.js'
import { getItems } from '@/api/watchlist.js'
import { itemSections } from '@/utils/pluginSurfaces.js'
import { pluginCredits } from '@/utils/credits.js'
import { useWatchlistHost } from '@/composables/useWatchlistHost.js'

const props = defineProps({
  item: { type: Object, required: true },
  canNavigate: { type: Boolean, default: true },
})

const { isPluginEnabled } = useRegistry()
const library = ref([])
const load = async () => { library.value = await getItems().catch(() => []) }
const host = useWatchlistHost({ items: () => library.value, changed: load })
onMounted(load)

const sections = computed(() => itemSections.filter((s) => isPluginEnabled(s.pluginId)))
const tmdbID = computed(() => props.item.tmdbId ?? null)
const credits = computed(() => (tmdbID.value ? null : pluginCredits(props.item.customCredits)))
</script>

<template>
  <div data-plugin-slot="item-sections" class="contents">
    <component
      :is="s.component"
      v-for="s in sections"
      :key="s.pluginId"
      v-bind="{ kind: item.type, tmdbID, title: item.title, canNavigate, credits, host }"
    />
  </div>
</template>
