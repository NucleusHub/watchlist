<script setup>
// Where clicking a poster's "Open" goes for movies and shows (iOS OpenDefaultsView). Saves as you pick.
import { ref, computed } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { OPEN_OPTIONS, TITLE_FORMATS, buildOpenUrl } from '@/utils/openTarget.js'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import SegmentPills from '@/ui/SegmentPills.vue'
import Glyph from '@/ui/Glyph.vue'

const { t } = useI18n()
const { defaults, setDefault } = useOpenSettings()

const kind = ref('movie')
const KINDS = computed(() => [
  { key: 'movie', label: t('watchlist.open.movies') },
  { key: 'show', label: t('watchlist.open.shows') },
])
const LOOK = { tmdb: ['film', 'teal'], csfd: ['star', 'rose'], google: ['magnifier', 'blue'], custom: ['link', 'slate'] }

const target = computed(() => defaults[kind.value])
const update = (patch) => setDefault(kind.value, { ...target.value, ...patch })
const preview = computed(() => buildOpenUrl(target.value, { title: 'The Matrix', year: 1999 }))
</script>

<template>
  <PageShell :title="t('watchlist.settings.openOnClick')" back="/settings">
    <SegmentPills v-model="kind" :items="KINDS" fill class="mb-5" />

    <WlSection :footer="t('watchlist.settings.openFoot')">
      <WlRow
        v-for="opt in OPEN_OPTIONS"
        :key="opt.type"
        button
        :icon="LOOK[opt.type][0]"
        :tint="LOOK[opt.type][1]"
        :title="t(opt.i18n)"
        @click="update({ type: opt.type })"
      >
        <template #trailing>
          <Glyph v-if="target.type === opt.type" name="checkBold" :sw="2.75" class="w-4 h-4 text-[var(--wl-accent)]" />
        </template>
      </WlRow>
    </WlSection>

    <WlSection v-if="target.type === 'custom'" :title="t('watchlist.open.custom')" :footer="preview ? `${t('watchlist.open.customHint')} ${t('watchlist.open.preview')}${preview}` : t('watchlist.open.customHint')">
      <div class="p-3">
        <input
          :value="target.customUrl"
          type="url"
          spellcheck="false"
          :placeholder="t('watchlist.open.customPlaceholder')"
          class="wl-field font-mono !text-sm"
          @input="update({ customUrl: $event.target.value })"
        />
      </div>
      <label class="wl-row">
        <span class="flex-1">{{ t('watchlist.open.titleFormat') }}</span>
        <select
          :value="target.titleFormat"
          class="cursor-pointer bg-transparent text-right text-[var(--wl-text-2)] outline-none"
          @change="update({ titleFormat: $event.target.value })"
        >
          <option v-for="fmt in TITLE_FORMATS" :key="fmt.value" :value="fmt.value">{{ fmt.example }}</option>
        </select>
      </label>
    </WlSection>
  </PageShell>
</template>
