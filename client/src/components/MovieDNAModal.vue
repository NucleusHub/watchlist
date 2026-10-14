<script setup>
import { ref, computed, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import { pageRoute } from '@/utils/routes.js'
import { getItems } from '@/api/watchlist.js'
import { searchMulti, hasTMDbKey } from '@/api/tmdb.js'
import { movieDNAUses, pages } from '@/utils/pluginSurfaces.js'
import { useMovieDNA } from '@/composables/useMovieDNA.js'
import { profile, traitsOf, genreKey, itemKey, titleKey } from '@/movieDNA/engine.js'

const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['close'])

const { t } = useI18n()
const { isPluginEnabled } = useRegistry()
const dna = useMovieDNA()

const items = ref([])
watch(
  () => props.show,
  async (v) => {
    if (!v) return
    view.value = 'main'
    items.value = await getItems().catch(() => [])
  }
)

const settings = dna.settings
const enabled = computed(() => settings.value.enabled)
const learned = computed(() => profile(items.value, settings.value))
const personPage = computed(() => pages.find((p) => p.id === 'person' && isPluginEnabled(p.pluginId)))
const uses = computed(() => movieDNAUses.filter((u) => isPluginEnabled(u.pluginId)))
const hidden = computed(() =>
  Object.entries(settings.value.notInterested).sort((a, b) => b[1].at.localeCompare(a[1].at))
)

const TITLE_LIMIT = 15
const showAllTitles = ref(false)
const titles = computed(() => traitsOf(learned.value, 'title'))
const sections = computed(() => [
  { key: 'genres', label: t('watchlist.dna.genres'), traits: traitsOf(learned.value, 'genre') },
  {
    key: 'titles',
    label: t('watchlist.dna.titles'),
    traits: showAllTitles.value ? titles.value : titles.value.slice(0, TITLE_LIMIT),
    more: titles.value.length - TITLE_LIMIT,
  },
  { key: 'people', label: t('watchlist.dna.people'), traits: traitsOf(learned.value, 'person') },
].filter((s) => s.traits.length))

const note = (trait) => {
  if (trait.isManual) return t('watchlist.dna.setByYou')
  if (trait.followed) return t('watchlist.dna.following')
  if (trait.boosts > 0) return t('watchlist.dna.boosted', { count: trait.boosts })
  return ''
}

// 'main' | 'edit' | 'add'
const view = ref('main')
const editing = ref(null)
const strength = ref(0)

function edit(trait) {
  editing.value = trait
  strength.value = trait.strength
  view.value = 'edit'
}
function saveStrength() {
  dna.setStrength(editing.value, strength.value)
  view.value = 'main'
}
function useLearned() {
  dna.setStrength(editing.value, null)
  view.value = 'main'
}
function remove(trait) {
  dna.removeFromDNA(trait)
  view.value = 'main'
}

const askingRebuild = ref(false)
function rebuild() {
  dna.rebuild()
  askingRebuild.value = false
}

const COMMON_GENRES = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', 'Drama', 'Family', 'Fantasy', 'History',
  'Horror', 'Music', 'Mystery', 'Romance', 'Science Fiction', 'Thriller', 'War', 'Western', 'Sci-Fi & Fantasy',
  'Action & Adventure', 'Kids', 'Reality', 'Soap', 'Talk', 'War & Politics',
]
const addKind = ref('genre')
const query = ref('')
const picked = ref(null)
const addStrength = ref(60)
const remote = ref([])

function startAdd() {
  addKind.value = 'genre'
  query.value = ''
  picked.value = null
  addStrength.value = 60
  remote.value = []
  view.value = 'add'
}
watch(addKind, () => { picked.value = null; query.value = ''; remote.value = [] })

const needle = computed(() => query.value.trim())
const existing = computed(() => new Set(learned.value.traits.map((x) => x.key)))
const candidates = computed(() => {
  const q = needle.value.toLowerCase()
  const match = (name) => !q || name.toLowerCase().includes(q)
  let out = []
  if (addKind.value === 'genre') {
    const seen = new Set()
    const names = [...items.value.flatMap((i) => i.genres ?? []), ...COMMON_GENRES].filter((g) => !seen.has(genreKey(g)) && seen.add(genreKey(g)))
    out = names.filter(match).map((name) => ({ key: genreKey(name), kind: 'genre', name }))
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
    remote.value = results.map((r) => {
      const type = r.media_type === 'movie' ? 'movie' : 'show'
      const year = (r.release_date || r.first_air_date || '').slice(0, 4)
      return {
        key: titleKey(type, r.id),
        kind: 'title',
        name: r.title || r.name,
        detail: [year, 'TMDb'].filter(Boolean).join(' · '),
        poster: r.poster_path ? `https://image.tmdb.org/t/p/w92${r.poster_path}` : null,
      }
    })
  }, 350)
})

function add() {
  const c = picked.value
  dna.addToDNA({ kind: c.kind, key: c.key, name: c.name, poster: c.poster, strength: addStrength.value })
  view.value = 'main'
}

const BULLETS = ['how1', 'how2', 'how3', 'how4', 'how5']
const rowClass = 'cursor-pointer w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left hover:bg-black/5 dark:hover:bg-white/10 transition-colors'
const btnClass = 'cursor-pointer px-3 py-1.5 rounded-lg text-sm font-medium transition-colors'
const primaryBtn = `${btnClass} text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed`
const subtleBtn = `${btnClass} text-slate-600 dark:text-slate-300 bg-black/[0.04] dark:bg-white/8 hover:bg-black/10 dark:hover:bg-white/15`
</script>

<template>
  <TemplateModal
    :show="show"
    header
    :title="t('watchlist.dna.title')"
    size="lg"
    z="z-[210]"
    fixed-height
    body-class="px-5 pb-5 pt-4"
    @cancel="view === 'main' ? emit('close') : (view = 'main')"
  >
    <div v-if="view === 'edit' && editing" class="flex flex-col gap-4">
      <h3 class="text-base font-semibold text-slate-900 dark:text-white">{{ editing.name }}</h3>
      <div class="flex flex-col gap-2 rounded-xl border border-black/5 dark:border-white/10 bg-white/40 dark:bg-white/[0.03] p-4">
        <div class="flex justify-between text-sm">
          <span class="text-slate-700 dark:text-slate-200">{{ t('watchlist.dna.strength') }}</span>
          <span class="font-semibold tabular-nums text-slate-900 dark:text-white">{{ strength }}</span>
        </div>
        <input v-model.number="strength" type="range" min="-100" max="100" step="5" class="w-full accent-indigo-600" />
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.dna.strengthHint') }}</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button type="button" :class="primaryBtn" @click="saveStrength">{{ t('watchlist.open.save') }}</button>
        <button v-if="editing.isManual && editing.learned != null" type="button" :class="subtleBtn" @click="useLearned">
          {{ t('watchlist.dna.useLearned', { value: editing.learned }) }}
        </button>
        <button type="button" :class="`${subtleBtn} !text-red-600 dark:!text-red-400`" @click="remove(editing)">{{ t('watchlist.dna.remove') }}</button>
        <button type="button" :class="subtleBtn" @click="view = 'main'">{{ t('watchlist.open.cancel') }}</button>
      </div>
    </div>

    <div v-else-if="view === 'add'" class="flex flex-col gap-3">
      <h3 class="text-base font-semibold text-slate-900 dark:text-white">{{ t('watchlist.dna.addTitle') }}</h3>
      <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1 self-start">
        <button
          v-for="k in ['genre', 'title']"
          :key="k"
          type="button"
          @click="addKind = k"
          :class="[
            'cursor-pointer px-3 py-1 rounded-lg text-xs font-medium transition-all',
            addKind === k ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
          ]"
        >{{ t(`watchlist.dna.kind.${k}`) }}</button>
      </div>
      <input
        v-model="query"
        :placeholder="t(addKind === 'genre' ? 'watchlist.dna.searchGenre' : 'watchlist.dna.searchTitles')"
        class="bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
      />
      <div class="flex flex-col max-h-64 overflow-y-auto">
        <button v-for="c in candidates" :key="c.key" type="button" :class="rowClass" @click="picked = c">
          <img v-if="c.poster" :src="c.poster" class="w-8 h-12 rounded object-cover shrink-0" alt="" />
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm text-slate-900 dark:text-white">{{ c.name }}</span>
            <span v-if="c.detail" class="block text-xs text-slate-400 dark:text-slate-500">{{ c.detail }}</span>
          </span>
          <span v-if="picked?.key === c.key" class="text-indigo-600 dark:text-indigo-400">✓</span>
        </button>
      </div>
      <div v-if="picked" class="flex flex-col gap-2 rounded-xl border border-black/5 dark:border-white/10 bg-white/40 dark:bg-white/[0.03] p-4">
        <div class="flex justify-between text-sm">
          <span class="text-slate-700 dark:text-slate-200">{{ t('watchlist.dna.strength') }}</span>
          <span class="font-semibold tabular-nums text-slate-900 dark:text-white">{{ addStrength }}</span>
        </div>
        <input v-model.number="addStrength" type="range" min="-100" max="100" step="5" class="w-full accent-indigo-600" />
      </div>
      <div class="flex gap-2">
        <button type="button" :class="primaryBtn" :disabled="!picked" @click="add">{{ t('watchlist.dna.add') }}</button>
        <button type="button" :class="subtleBtn" @click="view = 'main'">{{ t('watchlist.open.cancel') }}</button>
      </div>
    </div>

    <div v-else class="flex flex-col gap-5">
      <div
        v-if="enabled && !uses.length"
        class="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-700 dark:text-amber-300"
      >
        <p class="font-medium">{{ t('watchlist.dna.nothingUses') }}</p>
        <p class="text-xs mt-0.5">{{ t('watchlist.dna.nothingUsesDesc') }}</p>
      </div>

      <div class="flex flex-col gap-1.5">
        <div class="flex items-center justify-between gap-3 rounded-lg bg-white/60 dark:bg-white/[0.04] border border-black/5 dark:border-white/10 px-3 py-2.5">
          <span class="text-sm font-medium text-slate-800 dark:text-slate-100">{{ t('watchlist.dna.toggle') }}</span>
          <button
            type="button"
            role="switch"
            :aria-checked="enabled"
            @click="dna.setEnabled(!enabled)"
            :class="['cursor-pointer relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors', enabled ? 'bg-indigo-600' : 'bg-slate-300 dark:bg-slate-600']"
          >
            <span :class="['inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform', enabled ? 'translate-x-4' : 'translate-x-0.5']" />
          </button>
        </div>
        <p class="text-xs text-slate-400 dark:text-slate-500 px-1">{{ t(enabled ? 'watchlist.dna.footerOn' : 'watchlist.dna.footerOff') }}</p>
      </div>

      <template v-if="enabled">
        <section v-if="uses.length" class="flex flex-col gap-1.5">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">{{ t('watchlist.dna.usedBy') }}</h3>
          <p v-for="u in uses" :key="u.pluginId" class="text-sm text-slate-600 dark:text-slate-300">· {{ u.purpose }}</p>
        </section>

        <section class="flex flex-col gap-1.5">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">{{ t('watchlist.dna.how') }}</h3>
          <p v-for="b in BULLETS" :key="b" class="text-xs text-slate-500 dark:text-slate-400">· {{ t(`watchlist.dna.${b}`) }}</p>
        </section>

        <div v-if="!learned.traits.length" class="text-center py-8">
          <p class="text-base font-semibold text-slate-900 dark:text-white">{{ t('watchlist.dna.empty') }}</p>
          <p class="text-sm text-slate-500 dark:text-slate-400 mt-1">{{ t('watchlist.dna.emptyDesc') }}</p>
        </div>

        <section v-for="s in sections" :key="s.key" class="flex flex-col gap-1">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">{{ s.label }}</h3>
          <div v-for="trait in s.traits" :key="trait.key" class="flex items-center gap-1">
          <button type="button" :class="rowClass" @click="edit(trait)">
            <img
              v-if="trait.poster && trait.kind !== 'genre'"
              :src="trait.poster"
              alt=""
              :class="['object-cover shrink-0', trait.kind === 'person' ? 'w-10 h-10 rounded-full' : 'w-8 h-12 rounded']"
            />
            <span class="min-w-0 flex-1 flex flex-col gap-1.5">
              <span class="truncate text-sm text-slate-900 dark:text-white">{{ trait.name }}</span>
              <span class="relative block h-1.5 rounded-full bg-black/10 dark:bg-white/10">
                <span
                  class="absolute top-0 h-full rounded-full"
                  :class="trait.strength >= 0 ? 'bg-indigo-500' : 'bg-slate-500'"
                  :style="{ left: trait.strength >= 0 ? '50%' : `${50 - Math.abs(trait.strength) / 2}%`, width: `${Math.max(1.5, Math.abs(trait.strength) / 2)}%` }"
                />
                <span class="absolute left-1/2 -top-0.5 h-2.5 w-0.5 bg-slate-400/60" />
              </span>
            </span>
            <span class="w-20 shrink-0 text-right">
              <span class="block text-sm font-semibold tabular-nums text-slate-900 dark:text-white">{{ trait.strength }}</span>
              <span class="block text-[11px] text-slate-400 dark:text-slate-500">{{ note(trait) }}</span>
            </span>
          </button>
          <RouterLink
            v-if="trait.kind === 'person' && personPage"
            :to="pageRoute(personPage.pluginId, 'person', trait.key.slice('person:'.length))"
            class="shrink-0 text-sm font-medium text-indigo-600 dark:text-indigo-400 hover:underline px-2"
            @click="emit('close')"
          >
            {{ t('watchlist.dna.openPage') }}
          </RouterLink>
          </div>
          <button v-if="s.more > 0" type="button" :class="`${rowClass} text-sm text-indigo-600 dark:text-indigo-400`" @click="showAllTitles = !showAllTitles">
            {{ showAllTitles ? t('watchlist.dna.showFewer') : t('watchlist.dna.showAll', { count: s.more + TITLE_LIMIT }) }}
          </button>
        </section>

        <section v-if="hidden.length" class="flex flex-col gap-1">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">{{ t('watchlist.dna.notInterested') }}</h3>
          <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.dna.notInterestedDesc') }}</p>
          <div v-for="[key, title] in hidden" :key="key" class="flex items-center justify-between gap-3 px-3 py-2">
            <span class="truncate text-sm text-slate-900 dark:text-white">{{ title.name }}</span>
            <button type="button" class="cursor-pointer shrink-0 text-sm font-medium text-indigo-600 dark:text-indigo-400 hover:underline" @click="dna.clearNotInterested(key)">
              {{ t('watchlist.dna.showAgain') }}
            </button>
          </div>
        </section>

        <section class="flex flex-col gap-2">
          <div class="flex flex-wrap gap-2">
            <button type="button" :class="subtleBtn" @click="startAdd">{{ t('watchlist.dna.addOpen') }}</button>
            <button v-if="!askingRebuild" type="button" :class="subtleBtn" @click="askingRebuild = true">{{ t('watchlist.dna.rebuild') }}</button>
          </div>
          <div v-if="askingRebuild" class="rounded-xl border border-red-500/30 bg-red-500/10 p-3 flex flex-col gap-2">
            <p class="text-sm font-medium text-red-700 dark:text-red-300">{{ t('watchlist.dna.rebuildConfirm') }}</p>
            <p class="text-xs text-red-700/80 dark:text-red-300/80">{{ t('watchlist.dna.rebuildBody') }}</p>
            <div class="flex gap-2">
              <button type="button" :class="`${btnClass} text-white bg-red-600 hover:bg-red-500`" @click="rebuild">{{ t('watchlist.dna.rebuildYes') }}</button>
              <button type="button" :class="subtleBtn" @click="askingRebuild = false">{{ t('watchlist.open.cancel') }}</button>
            </div>
          </div>
        </section>
      </template>
    </div>
  </TemplateModal>
</template>
