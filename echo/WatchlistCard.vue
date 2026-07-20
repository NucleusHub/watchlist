<script setup>
import { computed } from 'vue'
import EchoEmbedContainer from '@core/echo/EchoEmbedContainer.vue'
import EchoAddButton from '@core/echo/EchoAddButton.vue'
import TableIcon from './icons/table.svg?component'

// Renderer for "watchlist.item" messages. Lives in Watchlist (next to its
// manifest.echo.json) and is auto-registered into Echo via this app's
// integration.echo.js.
// payload = { itemId, title, type, status, posterUrl, year, rating, tmdbRating,
//   runtime, seasons, episodes, showRuntime }.
const props = defineProps({
  payload: { type: Object, required: true },
})

// "Add" → create the item in the caller's own watchlist (the Watchlist app's
// API does the insert). Added as "planned" — it's new to your list. Carry the
// runtime/season metadata across too, and let the type decide which of the
// movie- vs show-only fields apply, so the added item isn't missing data the
// sender's card showed.
async function addToWatchlist() {
  const p = props.payload
  const isShow = p.type === 'show'
  const res = await fetch('/api/watchlist', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      title: p.title,
      type: isShow ? 'show' : 'movie',
      status: 'planned',
      posterUrl: p.posterUrl || null,
      year: p.year || null,
      tmdbRating: p.tmdbRating || null,
      runtime: isShow ? null : (p.runtime ?? null),
      seasons: isShow ? (p.seasons ?? null) : null,
      episodes: isShow ? (p.episodes ?? null) : null,
      showRuntime: isShow ? (p.showRuntime ?? null) : null,
    }),
  })
  if (!res.ok) throw new Error('Failed to add')
}

const STATUS_LABEL = { planned: 'Planned', watching: 'Watching', completed: 'Completed' }
const statusLabel = computed(() => STATUS_LABEL[props.payload.status] || props.payload.status || '')
const meta = computed(() =>
  [props.payload.type === 'show' ? 'Show' : 'Movie', props.payload.year].filter(Boolean).join(' · ')
)
</script>

<template>
  <EchoEmbedContainer app="watchlist" label="Watchlist" accent="#f59e0b">
    <template #actions>
      <EchoAddButton :handler="addToWatchlist" label="Add" done-label="Added" />
    </template>
    <div class="flex gap-3">
      <img
        v-if="payload.posterUrl"
        :src="payload.posterUrl"
        :alt="payload.title"
        class="h-20 w-[3.5rem] shrink-0 rounded-md object-cover"
      />
      <span
        v-else
        class="flex h-20 w-[3.5rem] shrink-0 items-center justify-center rounded-md bg-amber-400/15 text-amber-400"
      >
        <TableIcon width="20" height="20" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="truncate font-medium text-slate-900 dark:text-white">{{ payload.title }}</p>
        <p class="mt-0.5 text-xs text-slate-500 dark:text-white/55">{{ meta }}</p>
        <div class="mt-1.5 flex items-center gap-2">
          <span class="rounded-full bg-amber-400/15 px-2 py-0.5 text-[0.65rem] font-medium uppercase tracking-wide text-amber-500 dark:text-amber-300">{{ statusLabel }}</span>
          <span v-if="payload.rating || payload.tmdbRating" class="text-xs text-slate-500 dark:text-white/55">
            ★ {{ payload.rating || payload.tmdbRating }}
          </span>
        </div>
      </div>
    </div>
  </EchoEmbedContainer>
</template>
