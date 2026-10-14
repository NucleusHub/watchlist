<script setup>
import { ref } from 'vue'
import TrailerModal from '@/components/TrailerModal.vue'
import DetailSection from '@/components/DetailSection.vue'
import { useI18n } from '@core/useI18n.js'
import { Icon } from '@core/icons'
import { videoThumb, videoWatchUrl } from '@/utils/trailers.js'

const MAX_VIDEOS = 10

defineProps({
  videos: { type: Array, required: true },
})

const { t } = useI18n()
const playing = ref(null)
</script>

<template>
  <DetailSection :title="t('watchlist.detail.trailers')">
    <div class="-m-1 flex gap-3 overflow-x-auto p-1">
      <div v-for="video in videos.slice(0, MAX_VIDEOS)" :key="video.key" class="group/video relative w-56 shrink-0">
        <button
          type="button"
          @click="playing = video"
          :aria-label="`${video.kind}: ${video.name}`"
          class="nuc-press cursor-pointer flex w-full flex-col gap-1.5 text-left"
        >
          <div class="relative aspect-video w-full overflow-hidden rounded-xl bg-slate-200 dark:bg-slate-700">
            <img :src="videoThumb(video.key)" :alt="video.name" loading="lazy" class="h-full w-full object-cover" />
            <span class="absolute inset-0 flex items-center justify-center">
              <span class="flex h-11 w-11 items-center justify-center rounded-full bg-black/55 text-white transition-transform group-hover/video:scale-110">
                <Icon name="play" class="h-5 w-5" />
              </span>
            </span>
          </div>
          <span class="line-clamp-2 text-sm font-medium text-slate-900 dark:text-white">{{ video.name }}</span>
          <span class="text-xs text-slate-400 dark:text-slate-500">{{ video.kind }}</span>
        </button>
        <a
          :href="videoWatchUrl(video.key)"
          target="_blank"
          rel="noopener noreferrer"
          :title="t('watchlist.detail.openYouTube')"
          class="absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-full bg-black/45 text-white/80 opacity-0 transition-opacity hover:bg-black/70 group-hover/video:opacity-100 focus-visible:opacity-100"
        >
          <Icon name="externalLink" class="h-3.5 w-3.5" />
        </a>
      </div>
    </div>
  </DetailSection>

  <TrailerModal :video="playing" @close="playing = null" />
</template>
