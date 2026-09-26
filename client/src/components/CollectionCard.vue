<script setup>
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import TrashIcon from '@core/TrashIcon.vue'
import CollectionCover from '@/components/CollectionCover.vue'
import { Icon } from '@core/icons'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  collection: { type: Object, required: true },
})
const emit = defineEmits(['rename', 'delete'])

const coverPosters = computed(() => {
  const c = props.collection
  if (c.coverPosters?.length) return c.coverPosters
  return (c.previewPosters || []).slice(0, c.coverCount || 4)
})
</script>

<template>
  <div class="relative group">
    <RouterLink
      :to="`/collections/${collection._id}`"
      class="block rounded-2xl overflow-hidden bg-white/70 dark:bg-slate-800/60 border border-white/60 dark:border-white/8 shadow-sm hover:shadow-xl hover:shadow-indigo-500/10 hover:-translate-y-1 transition-all duration-300 ease-out no-underline"
    >
      <div class="relative aspect-[16/10] overflow-hidden">
        <CollectionCover :image="collection.coverUrl" :posters="coverPosters" class="transition-transform duration-500 group-hover:scale-[1.03]" />

        <div class="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/45 to-transparent pointer-events-none" />
        <span class="absolute bottom-2 left-2 inline-flex items-center gap-1 rounded-full bg-black/45 backdrop-blur-md px-2.5 py-1 text-[11px] font-medium text-white/95">
          <Icon name="folder" class="w-3 h-3" :sw="2" />
          {{ t('watchlist.collections.itemCount', { count: collection.itemCount || 0 }) }}
        </span>
      </div>

      <div class="px-3.5 py-3">
        <h3 class="text-sm font-semibold text-slate-900 dark:text-white truncate">{{ collection.name }}</h3>
        <p
          v-if="collection.description"
          class="mt-0.5 text-xs text-slate-500 dark:text-slate-400 leading-relaxed line-clamp-1"
        >
          {{ collection.description }}
        </p>
      </div>
    </RouterLink>

    <div class="absolute top-2 right-2 flex items-center gap-1 opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
      <button
        type="button"
        :title="t('watchlist.collections.rename')"
        class="nuc-press cursor-pointer w-8 h-8 rounded-lg flex items-center justify-center text-white/90 bg-black/35 backdrop-blur-md hover:bg-black/55 transition-colors"
        @click.prevent.stop="emit('rename', collection)"
      >
        <Icon name="edit" class="w-4 h-4" />
      </button>
      <button
        type="button"
        :title="t('watchlist.collections.delete')"
        class="nuc-trash nuc-press cursor-pointer w-8 h-8 rounded-lg flex items-center justify-center text-white/90 bg-black/35 backdrop-blur-md hover:bg-red-600/70 transition-colors"
        @click.prevent.stop="emit('delete', collection)"
      >
        <TrashIcon class="w-4 h-4" stroke-width="2" />
      </button>
    </div>
  </div>
</template>
