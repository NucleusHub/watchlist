<script setup>
import TemplateModal from '@core/TemplateModal.vue'
import { videoEmbedUrl } from '@/utils/trailers.js'

// `video` is { key, name, kind }; null closes it.
defineProps({ video: { type: Object, default: null } })
defineEmits(['close'])
</script>

<template>
  <TemplateModal
    :show="!!video"
    header
    size="xl"
    z="z-[250]"
    :title="video?.name || ''"
    :description="video?.kind || ''"
    body-class="p-0"
    @cancel="$emit('close')"
  >
    <iframe
      v-if="video"
      :src="videoEmbedUrl(video.key)"
      :title="video.name"
      allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
      allowfullscreen
      referrerpolicy="strict-origin-when-cross-origin"
      class="aspect-video w-full bg-black"
    />
  </TemplateModal>
</template>
