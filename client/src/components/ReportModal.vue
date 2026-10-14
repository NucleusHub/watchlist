<script setup>
import { ref, computed, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { REPORT_URL, MAX_SHOTS, buildReport, validEmail } from '@/utils/report.js'
import { APP_VERSION } from '@/utils/about.js'

const { t, locale } = useI18n()
const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['close'])

const title = ref('')
const details = ref('')
const email = ref('')
const shots = ref([])
const sending = ref(false)
const sent = ref(false)
const failure = ref('')

watch(() => props.show, (v) => {
  if (!v) return
  title.value = details.value = email.value = failure.value = ''
  shots.value = []
  sent.value = false
})

const canSend = computed(() => title.value.trim() && details.value.trim() && !sending.value)

// JPEG, longest side 1600 px, like the iOS sheet.
function toJpeg(file) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    const url = URL.createObjectURL(file)
    img.onload = () => {
      const scale = Math.min(1, 1600 / Math.max(img.width, img.height))
      const canvas = Object.assign(document.createElement('canvas'), { width: Math.round(img.width * scale), height: Math.round(img.height * scale) })
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height)
      URL.revokeObjectURL(url)
      resolve(canvas.toDataURL('image/jpeg', 0.82))
    }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('image')) }
    img.src = url
  })
}

async function pick(e) {
  for (const file of [...e.target.files]) {
    if (shots.value.length >= MAX_SHOTS) break
    try { shots.value.push(await toJpeg(file)) } catch {}
  }
  e.target.value = ''
}

async function send() {
  if (!validEmail(email.value)) { failure.value = t('watchlist.report.badEmail'); return }
  sending.value = true
  failure.value = ''
  try {
    const body = buildReport({
      title: title.value, details: details.value, email: email.value,
      shots: shots.value.map((s) => s.split(',')[1]),
      version: APP_VERSION, locale: locale.value || navigator.language, ua: navigator.userAgent, platform: navigator.platform,
    })
    const res = await fetch(REPORT_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    if (res.ok) sent.value = true
    else failure.value = res.status === 429 ? t('watchlist.report.tooMany') : t('watchlist.report.failed', { status: res.status })
  } catch {
    failure.value = t('watchlist.report.offline')
  } finally {
    sending.value = false
  }
}

const field = 'w-full bg-white dark:bg-slate-700 text-slate-900 dark:text-white rounded-lg px-3 py-2 text-sm placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500'
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="md"
    z="z-[210]"
    :title="t('watchlist.report.title')"
    :confirm-label="sent ? t('watchlist.report.done') : t('watchlist.report.send')"
    :cancel-label="t('watchlist.open.cancel')"
    :hide-cancel="sent"
    :confirm-disabled="!sent && !canSend"
    :busy="sending"
    body-class="px-5 pb-5 pt-5"
    @confirm="sent ? emit('close') : send()"
    @cancel="emit('close')"
  >
    <div v-if="sent" class="flex flex-col items-center gap-2 py-6 text-center">
      <svg class="w-12 h-12 text-emerald-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
      <p class="text-lg font-semibold text-slate-900 dark:text-white">{{ t('watchlist.report.sent') }}</p>
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ email.trim() ? t('watchlist.report.thanksReply') : t('watchlist.report.thanks') }}</p>
    </div>
    <div v-else class="flex flex-col gap-4">
      <input v-model="title" type="text" maxlength="200" :placeholder="t('watchlist.report.whatHappened')" :class="field" />
      <textarea v-model="details" rows="5" maxlength="10000" :placeholder="t('watchlist.report.details')" :class="[field, 'resize-y']" />

      <div class="flex flex-col gap-2">
        <p class="text-xs uppercase tracking-wide text-slate-400 dark:text-slate-500">{{ t('watchlist.report.screenshots') }}</p>
        <div class="flex flex-wrap gap-2">
          <div v-for="(shot, i) in shots" :key="i" class="relative w-16 h-24 rounded-lg overflow-hidden">
            <img :src="shot" alt="" class="w-full h-full object-cover" />
            <button
              type="button"
              :aria-label="t('watchlist.report.removeShot')"
              class="cursor-pointer absolute top-1 right-1 w-5 h-5 rounded-full bg-black/60 text-white text-xs leading-none"
              @click="shots.splice(i, 1)"
            >×</button>
          </div>
          <label v-if="shots.length < MAX_SHOTS" class="cursor-pointer grid place-items-center w-16 h-24 rounded-lg border-2 border-dashed border-indigo-500/40 text-indigo-600 dark:text-indigo-400 hover:bg-indigo-500/10 transition-colors">
            <input type="file" accept="image/*" multiple class="sr-only" @change="pick" />
            <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" d="M12 5v14M5 12h14" /></svg>
          </label>
        </div>
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.report.shotsHint', { max: MAX_SHOTS }) }}</p>
      </div>

      <div class="flex flex-col gap-2">
        <p class="text-xs uppercase tracking-wide text-slate-400 dark:text-slate-500">{{ t('watchlist.report.replyTo') }}</p>
        <input v-model="email" type="email" :placeholder="t('watchlist.report.email')" :class="field" />
        <p class="text-xs text-slate-400 dark:text-slate-500">{{ t('watchlist.report.diagnostics', { version: APP_VERSION || '?' }) }}</p>
      </div>
      <p v-if="failure" class="text-sm text-red-500">{{ failure }}</p>
    </div>
  </TemplateModal>
</template>
