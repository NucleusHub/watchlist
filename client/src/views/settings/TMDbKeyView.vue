<script setup>
// The TMDb API key (iOS TMDbKeySheet): checked against TMDb before it's saved.
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from '@core/useI18n.js'
import { useOpenSettings } from '@/composables/useOpenSettings.js'
import { verifyTMDbKey } from '@/api/tmdb.js'
import { TMDB_KEY_URL } from '@/utils/about.js'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'

const { t } = useI18n()
const router = useRouter()
const { tmdbApiKey, setTmdbApiKey } = useOpenSettings()

const key = ref('')
const checking = ref(false)
const problem = ref('')
const current = computed(() => (tmdbApiKey.value ? `•••• ${tmdbApiKey.value.slice(-4)}` : t('watchlist.settings.keyNotSet')))

async function save() {
  const candidate = key.value.trim().slice(0, 256)
  if (!candidate || checking.value) return
  checking.value = true
  problem.value = ''
  try {
    if (!(await verifyTMDbKey(candidate))) { problem.value = t('watchlist.settings.keyRejected'); return }
  } catch {
    // Offline: keep it anyway, it gets used as soon as there's a connection.
  }
  try {
    await setTmdbApiKey(candidate)
    router.push('/settings')
  } catch {
    problem.value = t('watchlist.settings.keySaveFailed')
  } finally {
    checking.value = false
  }
}

async function remove() {
  problem.value = ''
  try { await setTmdbApiKey('') } catch { problem.value = t('watchlist.settings.keySaveFailed') }
}
</script>

<template>
  <PageShell :title="t('watchlist.settings.tmdbKey')" back="/settings">
    <WlSection :footer="problem || t('watchlist.settings.tmdbKeyDesc')">
      <WlRow :title="t('watchlist.settings.keyCurrent')">
        <template #trailing><span class="font-mono text-sm text-[var(--wl-text-2)]">{{ current }}</span></template>
      </WlRow>
      <form class="flex flex-col gap-3 p-4" @submit.prevent="save">
        <input
          v-model="key"
          type="text"
          autocomplete="off"
          spellcheck="false"
          :placeholder="t('watchlist.settings.keyPaste')"
          class="wl-field font-mono"
          @input="problem = ''"
        />
        <button type="submit" class="wl-btn wl-btn-primary" :disabled="!key.trim() || checking">
          {{ checking ? t('watchlist.settings.keyChecking') : t('watchlist.open.save') }}
        </button>
      </form>
    </WlSection>
    <WlSection>
      <WlRow :href="TMDB_KEY_URL" icon="globe" tint="blue" :title="t('watchlist.settings.keyGet')" />
      <WlRow v-if="tmdbApiKey" button danger :title="t('watchlist.settings.keyRemove')" @click="remove" />
    </WlSection>
  </PageShell>
</template>
