<script setup>
// What MovieDNA has learned, with a switch to turn it off and ways to tune it by hand (iOS MovieDNAView).
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { pageRoute } from '@/utils/routes.js'
import { getItems } from '@/api/watchlist.js'
import { searchMulti, hasTMDbKey } from '@/api/tmdb.js'
import { movieDNAUses, pages } from '@/utils/pluginSurfaces.js'
import { useMovieDNA } from '@/composables/useMovieDNA.js'
import { profile, traitsOf, genreKey, itemKey, titleKey } from '@/movieDNA/engine.js'
import { INTEREST } from '@/ui/palette.js'
import PageShell from '@/ui/PageShell.vue'
import WlSection from '@/ui/WlSection.vue'
import WlRow from '@/ui/WlRow.vue'
import WlToggle from '@/ui/WlToggle.vue'
import IconTile from '@/ui/IconTile.vue'
import DnaGlyph from '@/ui/DnaGlyph.vue'
import Glyph from '@/ui/Glyph.vue'
import EmptyState from '@/ui/EmptyState.vue'
import SegmentPills from '@/ui/SegmentPills.vue'

const { t } = useI18n()
const router = useRouter()
const { isPluginEnabled } = useRegistry()
const dna = useMovieDNA()

const items = ref([])
onMounted(async () => { items.value = await getItems().catch(() => []) })

const settings = dna.settings
const enabled = computed(() => settings.value.enabled)
const learned = computed(() => profile(items.value, settings.value))
const personPage = computed(() => pages.find((p) => p.id === 'person' && isPluginEnabled(p.pluginId)))
const uses = computed(() => movieDNAUses.filter((u) => isPluginEnabled(u.pluginId)))
const hidden = computed(() => Object.entries(settings.value.notInterested).sort((a, b) => b[1].at.localeCompare(a[1].at)))

const TITLE_LIMIT = 15
const showAllTitles = ref(false)
const titles = computed(() => traitsOf(learned.value, 'title'))
const sections = computed(() => [
  { key: 'genres', label: t('watchlist.dna.genres'), traits: traitsOf(learned.value, 'genre') },
  { key: 'titles', label: t('watchlist.dna.titles'), traits: showAllTitles.value ? titles.value : titles.value.slice(0, TITLE_LIMIT), more: titles.value.length - TITLE_LIMIT },
  { key: 'people', label: t('watchlist.dna.people'), traits: traitsOf(learned.value, 'person') },
].filter((s) => s.traits.length))

const HOW = [['star', 'how1'], ['heart', 'how2'], ['flame', 'how3'], ['listBullet', 'how4'], ['person', 'how5']]

const note = (trait) => {
  if (trait.isManual) return t('watchlist.dna.setByYou')
  if (trait.followed) return t('watchlist.dna.following')
  if (trait.boosts > 0) return t('watchlist.dna.boosted', { count: trait.boosts })
  return ''
}
const personId = (trait) => (trait.kind === 'person' ? trait.key.slice('person:'.length) : null)

// People open their page when Cast & Crew is on; everything else opens the editor.
function open(trait) {
  if (personId(trait) && personPage.value) router.push(pageRoute(personPage.value.pluginId, 'person', personId(trait)))
  else edit(trait)
}

const editing = ref(null)
const strength = ref(0)
function edit(trait) {
  editing.value = trait
  strength.value = trait.strength
}
function saveStrength() {
  dna.setStrength(editing.value, strength.value)
  editing.value = null
}
function useLearned() {
  dna.setStrength(editing.value, null)
  editing.value = null
}
function remove() {
  dna.removeFromDNA(editing.value)
  editing.value = null
}

const askingRebuild = ref(false)
function rebuild() {
  dna.rebuild()
  askingRebuild.value = false
}

// Add a genre or title by hand.
const COMMON_GENRES = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family', 'Fantasy', 'History',
  'Horror', 'Music', 'Mystery', 'Romance', 'Science Fiction', 'Thriller', 'War', 'Western', 'Sci-Fi & Fantasy',
  'Action & Adventure', 'Kids', 'Reality', 'Soap', 'Talk', 'War & Politics',
]
const adding = ref(false)
const addKind = ref('genre')
const query = ref('')
const picked = ref(null)
const addStrength = ref(60)
const remote = ref([])
const KINDS = computed(() => ['genre', 'title'].map((key) => ({ key, label: t(`watchlist.dna.kind.${key}`) })))

function startAdd() {
  addKind.value = 'genre'
  query.value = ''
  picked.value = null
  addStrength.value = 60
  remote.value = []
  adding.value = true
}
watch(addKind, () => { picked.value = null; query.value = ''; remote.value = [] })

const needle = computed(() => query.value.trim())
const existing = computed(() => new Set(learned.value.traits.map((x) => x.key)))
const candidates = computed(() => {
  const q = needle.value.toLowerCase()
  const match = (name) => !q || name.toLowerCase().includes(q)
  if (addKind.value === 'genre') {
    const seen = new Set()
    const names = [...items.value.flatMap((i) => i.genres ?? []), ...COMMON_GENRES].filter((g) => !seen.has(genreKey(g)) && seen.add(genreKey(g)))
    const out = names.filter(match).map((name) => ({ key: genreKey(name), kind: 'genre', name }))
    if (q && !seen.has(genreKey(needle.value))) out.unshift({ key: genreKey(needle.value), kind: 'genre', name: needle.value })
    return out.filter((c) => !existing.value.has(c.key)).slice(0, 30)
  }
  if (!q) return []
  const library = items.value
    .filter((i) => match(i.title))
    .map((i) => ({ key: itemKey(i), kind: 'title', name: i.title, detail: t('watchlist.dna.inWatchlist'), poster: i.posterUrl }))
  const keys = new Set(library.map((c) => c.key))
  return [...library, ...remote.value.filter((c) => !keys.has(c.key))].filter((c) => !existing.value.has(c.key)).slice(0, 20)
})

let searchTimer = null
watch([query, addKind], () => {
  clearTimeout(searchTimer)
  remote.value = []
  if (addKind.value !== 'title' || needle.value.length < 2 || !hasTMDbKey.value) return
  const q = needle.value
  searchTimer = setTimeout(async () => {
    const results = await searchMulti(q).catch(() => [])
    if (q !== needle.value) return
    remote.value = results.map((r) => ({
      key: titleKey(r.media_type === 'movie' ? 'movie' : 'show', r.id),
      kind: 'title',
      name: r.title || r.name,
      detail: [(r.release_date || r.first_air_date || '').slice(0, 4), 'TMDb'].filter(Boolean).join(' · '),
      poster: r.poster_path ? `https://image.tmdb.org/t/p/w92${r.poster_path}` : null,
    }))
  }, 350)
})

function add() {
  const c = picked.value
  dna.addToDNA({ kind: c.kind, key: c.key, name: c.name, poster: c.poster, strength: addStrength.value })
  adding.value = false
}

const barStyle = (s) => ({
  left: s >= 0 ? '50%' : `${50 - Math.abs(s) / 2}%`,
  width: `${Math.max(2, Math.abs(s) / 2)}%`,
  background: s >= 0 ? INTEREST : '#64748B',
})
</script>

<template>
  <PageShell :title="t('watchlist.dna.title')" back="/settings">
    <WlSection v-if="enabled && !uses.length">
      <WlRow to="/settings/plugins" icon="info" tint="amber" :title="t('watchlist.dna.nothingUses')" :subtitle="t('watchlist.dna.nothingUsesDesc')" chevron />
    </WlSection>

    <WlSection :footer="t(enabled ? 'watchlist.dna.footerOn' : 'watchlist.dna.footerOff')">
      <WlRow :title="t('watchlist.dna.toggle')">
        <template #icon>
          <IconTile tint="rose"><template #default="{ size }"><DnaGlyph :style="{ width: size, height: size }" /></template></IconTile>
        </template>
        <template #trailing>
          <WlToggle :model-value="enabled" :label="t('watchlist.dna.toggle')" @update:model-value="dna.setEnabled($event)" />
        </template>
      </WlRow>
    </WlSection>

    <template v-if="enabled">
      <WlSection v-if="uses.length" :title="t('watchlist.dna.usedBy')">
        <div v-for="u in uses" :key="u.pluginId" class="wl-row !min-h-12">
          <Glyph name="sparkles" class="w-4 h-4 shrink-0" :style="{ color: INTEREST }" />
          <span class="text-[15px]">{{ u.purpose }}</span>
        </div>
      </WlSection>

      <WlSection :title="t('watchlist.dna.how')" padded>
        <div class="flex flex-col gap-2.5">
          <p v-for="[icon, key] in HOW" :key="key" class="flex items-baseline gap-2.5 text-sm text-[var(--wl-glyph)]">
            <Glyph :name="icon" :sw="2" class="w-[14px] h-[14px] shrink-0 translate-y-0.5 text-[var(--wl-text-2)]" />
            {{ t(`watchlist.dna.${key}`) }}
          </p>
        </div>
      </WlSection>

      <EmptyState v-if="!learned.traits.length" :title="t('watchlist.dna.empty')" :message="t('watchlist.dna.emptyDesc')">
        <template #icon><DnaGlyph class="w-8 h-8" /></template>
      </EmptyState>

      <WlSection v-for="s in sections" :key="s.key" :title="s.label">
        <button v-for="trait in s.traits" :key="trait.key" type="button" class="wl-row" :class="trait.kind === 'title' ? '!py-2' : '!py-3'" @click="open(trait)" @contextmenu.prevent="edit(trait)">
          <img v-if="trait.kind === 'title'" v-squircle :src="trait.poster || undefined" alt="" class="w-[34px] h-[51px] rounded-[6px] object-cover bg-[var(--wl-well)] shrink-0" />
          <img v-else-if="trait.kind === 'person'" :src="trait.poster || undefined" alt="" class="w-11 h-11 rounded-full object-cover bg-[var(--wl-well)] shrink-0" />
          <span class="min-w-0 flex-1 flex flex-col gap-1.5 pr-3">
            <span class="truncate">{{ trait.name }}</span>
            <span class="relative block h-1.5 rounded-full bg-[var(--wl-well)]">
              <span class="absolute top-0 h-full rounded-full" :style="barStyle(trait.strength)" />
              <span class="absolute left-1/2 -top-[2px] h-2.5 w-0.5 -ml-px rounded-full bg-[var(--wl-text-2)] opacity-60" />
            </span>
          </span>
          <span class="min-w-11 text-right">
            <span class="block text-[15px] font-semibold tabular-nums">{{ Math.round(trait.strength) }}</span>
            <span v-if="note(trait)" class="block text-xs text-[var(--wl-text-2)]">{{ note(trait) }}</span>
          </span>
        </button>
        <WlRow v-if="s.more > 0" button accent :title="showAllTitles ? t('watchlist.dna.showFewer') : t('watchlist.dna.showAll', { count: s.more + TITLE_LIMIT })" @click="showAllTitles = !showAllTitles" />
      </WlSection>

      <WlSection v-if="hidden.length" :title="t('watchlist.dna.notInterested')" :footer="t('watchlist.dna.notInterestedDesc')">
        <div v-for="[key, title] in hidden" :key="key" class="wl-row">
          <span class="flex-1 truncate">{{ title.name }}</span>
          <button type="button" class="cursor-pointer text-sm font-semibold text-[var(--wl-accent)]" @click="dna.clearNotInterested(key)">{{ t('watchlist.dna.showAgain') }}</button>
        </div>
      </WlSection>

      <WlSection :footer="t('watchlist.dna.rebuildFoot')">
        <WlRow button icon="plus" tint="indigo" :title="t('watchlist.dna.addOpen')" @click="startAdd" />
        <WlRow button icon="startOver" tint="amber" :title="t('watchlist.dna.rebuild')" @click="askingRebuild = true" />
      </WlSection>
    </template>
  </PageShell>

  <TemplateModal
    :show="!!editing"
    header
    footer
    size="xs"
    :title="editing?.name || ''"
    :confirm-label="t('watchlist.open.save')"
    :cancel-label="t('watchlist.open.cancel')"
    body-class="px-5 pt-4 pb-5"
    @confirm="saveStrength"
    @cancel="editing = null"
  >
    <div v-if="editing" class="flex flex-col gap-4">
      <div class="flex flex-col gap-2">
        <div class="flex justify-between text-[15px]">
          <span>{{ t('watchlist.dna.strength') }}</span>
          <span class="font-semibold tabular-nums">{{ strength }}</span>
        </div>
        <input v-model.number="strength" type="range" min="-100" max="100" step="5" class="w-full" :style="{ accentColor: INTEREST }" />
        <p class="text-xs text-[var(--wl-text-2)]">{{ t('watchlist.dna.strengthHint') }}</p>
      </div>
      <div class="flex flex-col gap-2">
        <button v-if="editing.isManual && editing.learned != null" type="button" class="wl-btn wl-btn-secondary" @click="useLearned">
          {{ t('watchlist.dna.useLearned', { value: editing.learned }) }}
        </button>
        <button type="button" class="wl-btn wl-btn-secondary !text-[var(--wl-danger)]" @click="remove">{{ t('watchlist.dna.remove') }}</button>
      </div>
    </div>
  </TemplateModal>

  <TemplateModal
    :show="adding"
    header
    footer
    size="sm"
    fixed-height="h-[70vh]"
    :title="t('watchlist.dna.addTitle')"
    :confirm-label="t('watchlist.dna.add')"
    :cancel-label="t('watchlist.open.cancel')"
    :confirm-disabled="!picked"
    body-class="px-5 pt-4 pb-5"
    @confirm="add"
    @cancel="adding = false"
  >
    <div class="flex flex-col gap-3">
      <SegmentPills v-model="addKind" :items="KINDS" fill />
      <input v-model="query" class="wl-field" :placeholder="t(addKind === 'genre' ? 'watchlist.dna.searchGenre' : 'watchlist.dna.searchTitles')" />
      <div class="flex flex-col rounded-[var(--wl-r-field)] bg-[var(--wl-well)] overflow-hidden">
        <button v-for="c in candidates" :key="c.key" type="button" class="wl-row !min-h-12" @click="picked = c">
          <img v-if="c.kind === 'title'" :src="c.poster || undefined" alt="" class="w-[34px] h-[51px] rounded-[6px] object-cover bg-[var(--wl-well)] shrink-0" />
          <span class="min-w-0 flex-1">
            <span class="block truncate">{{ c.name }}</span>
            <span v-if="c.detail" class="wl-sub">{{ c.detail }}</span>
          </span>
          <Glyph v-if="picked?.key === c.key" name="checkBold" :sw="2.75" class="w-4 h-4 text-[var(--wl-accent)]" />
        </button>
      </div>
      <div v-if="picked" class="flex flex-col gap-2 pt-1">
        <div class="flex justify-between text-[15px]">
          <span>{{ t('watchlist.dna.strength') }}</span>
          <span class="font-semibold tabular-nums">{{ addStrength }}</span>
        </div>
        <input v-model.number="addStrength" type="range" min="-100" max="100" step="5" class="w-full" :style="{ accentColor: INTEREST }" />
      </div>
    </div>
  </TemplateModal>

  <TemplateModal
    :show="askingRebuild"
    :title="t('watchlist.dna.rebuildConfirm')"
    :message="t('watchlist.dna.rebuildBody')"
    :confirm-label="t('watchlist.dna.rebuildYes')"
    @confirm="rebuild"
    @cancel="askingRebuild = false"
  />
</template>
