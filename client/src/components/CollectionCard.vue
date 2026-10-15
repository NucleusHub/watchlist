<script setup>
// A collection as one big poster: its cover with the name and count on it (iOS CollectionCard).
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import ContextMenu from '@core/ContextMenu.vue'
import CollectionCover from '@/components/CollectionCover.vue'
import { ICONS } from '@core/icons'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()
const router = useRouter()

const props = defineProps({
  collection: { type: Object, required: true },
})
const emit = defineEmits(['rename', 'delete'])

const coverPosters = computed(() => {
  const c = props.collection
  if (c.coverPosters?.length) return c.coverPosters
  return (c.previewPosters || []).slice(0, c.coverCount || 4)
})

const to = computed(() => `/collections/${props.collection._id}`)
const menu = ref({ show: false, x: 0, y: 0 })
const menuItems = computed(() => [
  { label: t('watchlist.collections.rename'), icon: ICONS.pencil, action: () => emit('rename', props.collection) },
  { label: t('watchlist.collections.addItems'), icon: ICONS.plus, action: () => router.push({ path: to.value, query: { add: '1' } }) },
  { divider: true },
  { label: t('watchlist.collections.delete'), iconTrash: true, danger: true, action: () => emit('delete', props.collection) },
])
const openMenu = (e) => (menu.value = { show: true, x: e.clientX, y: e.clientY })
</script>

<template>
  <RouterLink
    :to="to"
    class="group relative block aspect-[16/10] rounded-[26px] shadow-[0_14px_30px_-12px_rgb(0_0_0/0.45)] no-underline nuc-press transition-transform duration-300 hover:-translate-y-1"
    @contextmenu.prevent="openMenu"
  >
    <div v-squircle class="absolute inset-0 rounded-[26px] overflow-hidden">
      <CollectionCover :image="collection.coverUrl" :posters="coverPosters" class="transition-transform duration-500 group-hover:scale-[1.03]" />
      <div class="absolute inset-x-0 bottom-0 px-[18px] pt-10 pb-4 bg-gradient-to-b from-transparent to-black/65 text-white">
        <h3 class="text-[22px] leading-tight font-bold tracking-[-0.01em] line-clamp-2 [text-shadow:0_2px_6px_rgb(0_0_0/0.4)]">{{ collection.name }}</h3>
        <p class="text-[13px] font-medium opacity-80">{{ t('watchlist.collections.itemCount', { count: collection.itemCount || 0 }) }}</p>
      </div>
    </div>
    <button
      type="button"
      :title="t('watchlist.collections.options')"
      class="absolute top-3 right-3 w-8 h-8 rounded-full grid place-items-center bg-black/35 backdrop-blur-md text-white/90 cursor-pointer opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity"
      @click.prevent.stop="openMenu"
    >
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" /></svg>
    </button>
  </RouterLink>
  <ContextMenu :show="menu.show" :x="menu.x" :y="menu.y" :items="menuItems" @close="menu.show = false" />
</template>
