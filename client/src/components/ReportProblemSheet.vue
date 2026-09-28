<script setup>
import { ref, computed, watch, nextTick } from 'vue'
import { Icon, Spinner } from '@core/icons'
import { useI18n } from '@core/useI18n.js'
import PageSheet from '@/components/PageSheet.vue'
import { useNucleusId } from '@/auth/nucleusId.js'
import { MAX_ATTACHMENTS, collectDiagnostics, prepareImage, sendReport } from '@/api/report.js'
import { haptic } from '@/native.js'

const props = defineProps({
  show: { type: Boolean, default: false },
})
const emit = defineEmits(['close'])
const { t, locale } = useI18n()
const { account, isSignedIn } = useNucleusId()

const title = ref('')
const description = ref('')
const email = ref('')
const anonymous = ref(false)
const images = ref([]) // { id, preview, type, data }
const sending = ref(false)
const sent = ref(false)
const error = ref('')
const diagnostics = ref(null)

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const asAccount = computed(() => isSignedIn.value && !anonymous.value)
const emailInvalid = computed(() => !!email.value.trim() && !EMAIL.test(email.value.trim()))
const canSend = computed(() => !!title.value.trim() && !!description.value.trim() && !emailInvalid.value && !sending.value)
const dirty = computed(() => !sent.value && !!(title.value.trim() || description.value.trim() || images.value.length))

const accountInitial = computed(() => (account.value?.name || account.value?.handle || '?').trim().charAt(0).toUpperCase())

const diagnosticsText = computed(() => {
  const d = diagnostics.value
  if (!d) return ''
  const app = [d.app.name, d.app.version && `${d.app.version}${d.app.build ? ` (${d.app.build})` : ''}`].filter(Boolean).join(' ')
  const system = [d.device.os || d.device.platform, d.device.osVersion].filter(Boolean).join(' ')
  return [app, d.device.model, system].filter(Boolean).join(' · ')
})

function reset() {
  for (const img of images.value) URL.revokeObjectURL(img.preview)
  title.value = ''
  description.value = ''
  email.value = ''
  anonymous.value = false
  images.value = []
  sending.value = false
  sent.value = false
  error.value = ''
}

watch(() => props.show, (open) => {
  if (!open) return
  collectDiagnostics().then((d) => { diagnostics.value = d }).catch(() => {})
})

function close() {
  if (sending.value) return
  emit('close')
}
// Wiped once the sheet is gone, not while it is still sliding away.
function onClosed() {
  if (!props.show) reset()
}
watch(() => props.show, (open) => { if (!open) setTimeout(onClosed, 400) })

// ── Screenshots ──────────────────────────────────────────────────────────
const fileInput = ref(null)
const addingImages = ref(false)
let nextId = 0
async function onFilesPicked(e) {
  const files = [...(e.target.files || [])].slice(0, MAX_ATTACHMENTS - images.value.length)
  e.target.value = ''
  if (!files.length) return
  addingImages.value = true
  try {
    for (const file of files) {
      try {
        images.value.push({ id: ++nextId, ...(await prepareImage(file)) })
      } catch {
        error.value = t('watchlist.report.imageFailed')
      }
    }
  } finally {
    addingImages.value = false
  }
}
function removeImage(img) {
  URL.revokeObjectURL(img.preview)
  images.value = images.value.filter((i) => i !== img)
}

// ── Description grows with its text, like Notes ─────────────────────────
const descriptionEl = ref(null)
function grow() {
  const el = descriptionEl.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${el.scrollHeight}px`
}
watch(description, () => nextTick(grow))

// ── Sending ──────────────────────────────────────────────────────────────
async function send() {
  if (!canSend.value) return
  error.value = ''
  sending.value = true
  document.activeElement?.blur?.()
  try {
    await sendReport({
      title: title.value.trim(),
      description: description.value.trim(),
      email: asAccount.value ? '' : email.value.trim(),
      asAccount: asAccount.value,
      attachments: images.value,
      locale: locale.value,
    })
    sent.value = true
    haptic('Medium')
  } catch (err) {
    error.value = err.code === 'offline'
      ? t('watchlist.report.offline')
      : err.code === 'unreachable'
        ? t('watchlist.report.unreachable')
        : err.status === 429
        ? t('watchlist.report.tooMany')
        : t('watchlist.report.failed', { reason: err.message })
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <PageSheet
    :show="show"
    :title="t('watchlist.report.title')"
    :confirm-discard="dirty ? t('watchlist.report.discard') : ''"
    @close="close"
  >
    <Transition name="rp-swap" mode="out-in">
      <div v-if="sent" key="sent" class="rp-done">
        <span class="rp-done-badge">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" class="w-9 h-9">
            <path class="rp-check" stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
          </svg>
        </span>
        <h3 class="rp-done-title">{{ t('watchlist.report.sentTitle') }}</h3>
        <p class="rp-done-text">{{ t(asAccount || email.trim() ? 'watchlist.report.sentReply' : 'watchlist.report.sentText') }}</p>
        <button type="button" class="rp-primary nuc-press" @click="emit('close')">{{ t('watchlist.report.done') }}</button>
      </div>

      <form v-else key="form" novalidate @submit.prevent="send">
        <p class="rp-intro">{{ t('watchlist.report.intro') }}</p>

        <section class="rp-group">
          <div class="rp-row">
            <input
              v-model="title"
              type="text"
              maxlength="200"
              enterkeyhint="next"
              autocapitalize="sentences"
              :placeholder="t('watchlist.report.titlePlaceholder')"
              :aria-label="t('watchlist.report.titleLabel')"
              class="rp-input"
              @keydown.enter.prevent="descriptionEl?.focus()"
            />
          </div>
          <div class="rp-row">
            <textarea
              ref="descriptionEl"
              v-model="description"
              rows="6"
              maxlength="10000"
              autocapitalize="sentences"
              :placeholder="t('watchlist.report.descriptionPlaceholder')"
              :aria-label="t('watchlist.report.descriptionLabel')"
              class="rp-input rp-textarea"
            />
          </div>
        </section>
        <p class="rp-foot">{{ t('watchlist.report.requiredHint') }}</p>

        <h4 class="rp-heading">{{ t('watchlist.report.screenshots') }}</h4>
        <section class="rp-group">
          <div v-if="images.length" class="rp-thumbs">
            <TransitionGroup name="rp-thumb">
              <div v-for="img in images" :key="img.id" class="rp-thumb">
                <img :src="img.preview" alt="" />
                <button type="button" class="rp-thumb-remove" :aria-label="t('watchlist.report.removeImage')" @click="removeImage(img)">
                  <Icon name="close" class="w-3 h-3" :sw="3" />
                </button>
              </div>
            </TransitionGroup>
          </div>
          <button
            type="button"
            class="rp-row rp-action"
            :disabled="images.length >= MAX_ATTACHMENTS || addingImages"
            @click="fileInput?.click()"
          >
            <svg class="w-[22px] h-[22px]" fill="none" stroke="currentColor" stroke-width="1.75" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15.75l5.159-5.159a2.25 2.25 0 013.182 0l5.159 5.159m-1.5-1.5l1.409-1.409a2.25 2.25 0 013.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0022.5 18.75V5.25A2.25 2.25 0 0020.25 3H3.75A2.25 2.25 0 001.5 5.25v13.5A2.25 2.25 0 003.75 21zm10.5-11.25h.008v.008h-.008V9.75zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
            </svg>
            <span class="flex-1 text-left">{{ images.length ? t('watchlist.report.addMore') : t('watchlist.report.addScreenshots') }}</span>
            <Spinner v-if="addingImages" class="w-4 h-4 animate-spin" />
            <span v-else class="rp-count">{{ images.length }}/{{ MAX_ATTACHMENTS }}</span>
          </button>
          <input ref="fileInput" type="file" accept="image/*" multiple class="hidden" @change="onFilesPicked" />
        </section>
        <p class="rp-foot">{{ t('watchlist.report.screenshotsHint') }}</p>

        <h4 class="rp-heading">{{ t('watchlist.report.contact') }}</h4>
        <section class="rp-group">
          <template v-if="isSignedIn">
            <div :class="['rp-row', 'rp-account', { 'is-off': anonymous }]">
              <span class="rp-avatar">{{ accountInitial }}</span>
              <span class="flex-1 min-w-0">
                <span class="block truncate font-medium">{{ account?.name }}</span>
                <span class="block truncate text-sm text-slate-500 dark:text-white/45">@{{ account?.handle }} · Nucleus ID</span>
              </span>
            </div>
            <label class="rp-row">
              <span class="flex-1">{{ t('watchlist.report.anonymous') }}</span>
              <button
                type="button"
                role="switch"
                :aria-checked="anonymous"
                :class="['rp-switch', { 'is-on': anonymous }]"
                @click="anonymous = !anonymous"
              >
                <span class="rp-knob" />
              </button>
            </label>
          </template>
          <div v-if="!asAccount" class="rp-row">
            <input
              v-model="email"
              type="email"
              inputmode="email"
              autocomplete="email"
              autocapitalize="off"
              spellcheck="false"
              maxlength="254"
              enterkeyhint="done"
              :placeholder="t('watchlist.report.emailPlaceholder')"
              :aria-label="t('watchlist.report.emailPlaceholder')"
              class="rp-input"
            />
          </div>
        </section>
        <p :class="['rp-foot', { 'text-red-600 dark:text-red-400': emailInvalid }]">
          {{ emailInvalid ? t('watchlist.report.emailInvalid') : asAccount ? t('watchlist.report.asAccountHint') : isSignedIn ? t('watchlist.report.anonymousHint') : t('watchlist.report.emailHint') }}
        </p>

        <button type="submit" class="rp-primary nuc-press" :disabled="!canSend">
          <Spinner v-if="sending" class="w-5 h-5 animate-spin" />
          <span>{{ sending ? t('watchlist.report.sending') : t('watchlist.report.send') }}</span>
        </button>
        <p v-if="error" class="rp-error" role="alert">{{ error }}</p>
        <p v-if="diagnosticsText" class="rp-diagnostics">
          {{ t('watchlist.report.diagnostics') }}<br />
          <span class="font-mono">{{ diagnosticsText }}</span>
        </p>
      </form>
    </Transition>
  </PageSheet>
</template>

<style scoped>
.rp-intro {
  margin: 0 0 18px;
  padding: 0 8px;
  text-align: center;
  font-size: 14px;
  line-height: 1.45;
  color: rgb(100 116 139);
}
.dark .rp-intro { color: rgba(255, 255, 255, 0.55); }

.rp-heading {
  margin: 0 0 7px;
  padding: 0 16px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(100 116 139);
}
.dark .rp-heading { color: rgba(255, 255, 255, 0.45); }

.rp-group {
  border-radius: 26px;
  overflow: hidden;
  background: #fff;
}
.dark .rp-group { background: rgba(255, 255, 255, 0.07); }

.rp-foot {
  margin: 7px 0 26px;
  padding: 0 16px;
  font-size: 13px;
  line-height: 1.4;
  color: rgb(100 116 139);
}
.dark .rp-foot { color: rgba(255, 255, 255, 0.45); }

.rp-row {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  min-height: 50px;
  padding: 0 16px;
  font-size: 17px;
}
.rp-row + .rp-row::before,
.rp-thumbs + .rp-row::before {
  content: '';
  position: absolute;
  top: 0;
  left: 16px;
  right: 0;
  height: 0.5px;
  background: rgba(60, 60, 67, 0.29);
}
.dark .rp-row + .rp-row::before,
.dark .rp-thumbs + .rp-row::before { background: rgba(84, 84, 88, 0.65); }

.rp-input {
  flex: 1;
  min-width: 0;
  padding: 14px 0;
  font-size: 17px;
  color: inherit;
  background: transparent;
  border: 0;
  outline: none;
}
.rp-input::placeholder { color: rgba(60, 60, 67, 0.3); }
.dark .rp-input::placeholder { color: rgba(235, 235, 245, 0.3); }
.rp-textarea {
  min-height: 150px;
  max-height: 45vh;
  line-height: 1.4;
  resize: none;
}

.rp-action {
  cursor: pointer;
  color: rgb(79 70 229);
  transition: background-color 0.15s ease;
}
.dark .rp-action { color: rgb(196 181 253); }
.rp-action:active { background: rgba(15, 23, 42, 0.06); }
.dark .rp-action:active { background: rgba(255, 255, 255, 0.07); }
.rp-action:disabled { cursor: default; opacity: 0.45; }
.rp-count { font-size: 15px; color: rgb(148 163 184); font-variant-numeric: tabular-nums; }
.dark .rp-count { color: rgba(255, 255, 255, 0.35); }

.rp-thumbs {
  display: flex;
  gap: 10px;
  padding: 14px 16px;
  overflow-x: auto;
}
.rp-thumb {
  position: relative;
  flex-shrink: 0;
  width: 76px;
  height: 104px;
}
.rp-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 14px;
  box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.12);
}
.rp-thumb-remove {
  position: absolute;
  top: -6px;
  right: -6px;
  display: grid;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 9999px;
  cursor: pointer;
  color: #fff;
  background: rgba(60, 60, 67, 0.85);
  border: 2px solid #fff;
}
.dark .rp-thumb-remove { border-color: #16131f; background: rgba(120, 120, 128, 0.9); }
.rp-thumb-enter-active, .rp-thumb-leave-active { transition: opacity 0.2s ease, transform 0.25s cubic-bezier(0.22, 1, 0.36, 1); }
.rp-thumb-enter-from, .rp-thumb-leave-to { opacity: 0; transform: scale(0.8); }

.rp-account { padding-top: 10px; padding-bottom: 10px; transition: opacity 0.25s ease; }
.rp-account.is-off { opacity: 0.4; }
.rp-avatar {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 9999px;
  flex-shrink: 0;
  font-size: 17px;
  font-weight: 600;
  color: #fff;
  background: linear-gradient(135deg, #818cf8, #a855f7);
}

.rp-switch {
  position: relative;
  flex-shrink: 0;
  width: 51px;
  height: 31px;
  border-radius: 9999px;
  background: rgba(120, 120, 128, 0.16);
  cursor: pointer;
  transition: background-color 0.25s ease;
}
.dark .rp-switch { background: rgba(120, 120, 128, 0.32); }
.rp-switch.is-on { background: #34c759; }
.rp-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 27px;
  height: 27px;
  border-radius: 9999px;
  background: #fff;
  box-shadow: 0 3px 8px rgba(0, 0, 0, 0.15), 0 1px 1px rgba(0, 0, 0, 0.16);
  transition: transform 0.3s cubic-bezier(0.22, 1, 0.36, 1);
}
.rp-switch.is-on .rp-knob { transform: translateX(20px); }

.rp-primary {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  height: 52px;
  border-radius: 9999px;
  font-size: 17px;
  font-weight: 600;
  color: #fff;
  cursor: pointer;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  box-shadow: 0 8px 22px -8px rgba(99, 102, 241, 0.6);
  transition: opacity 0.2s ease;
}
.rp-primary:disabled { cursor: default; opacity: 0.4; box-shadow: none; }

.rp-error {
  margin: 12px 16px 0;
  text-align: center;
  font-size: 14px;
  line-height: 1.4;
  color: rgb(220 38 38);
}
.dark .rp-error { color: rgb(248 113 113); }

.rp-diagnostics {
  margin: 20px 16px 0;
  text-align: center;
  font-size: 12px;
  line-height: 1.5;
  color: rgb(148 163 184);
}
.dark .rp-diagnostics { color: rgba(255, 255, 255, 0.35); }

.rp-done {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 56px 16px 0;
  text-align: center;
}
.rp-done-badge {
  display: grid;
  place-items: center;
  width: 76px;
  height: 76px;
  border-radius: 9999px;
  color: #fff;
  background: linear-gradient(135deg, #34d399, #10b981);
  box-shadow: 0 12px 30px -10px rgba(16, 185, 129, 0.6);
  animation: rp-pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}
.rp-check {
  stroke-dasharray: 30;
  stroke-dashoffset: 30;
  animation: rp-draw 0.4s 0.25s ease-out forwards;
}
.rp-done-title { margin-top: 20px; font-size: 22px; font-weight: 700; letter-spacing: -0.01em; }
.rp-done-text {
  margin: 6px 0 32px;
  max-width: 300px;
  font-size: 15px;
  line-height: 1.45;
  color: rgb(100 116 139);
}
.dark .rp-done-text { color: rgba(255, 255, 255, 0.55); }

.rp-swap-enter-active, .rp-swap-leave-active { transition: opacity 0.2s ease; }
.rp-swap-enter-from, .rp-swap-leave-to { opacity: 0; }

@keyframes rp-pop { from { transform: scale(0.4); opacity: 0; } }
@keyframes rp-draw { to { stroke-dashoffset: 0; } }
@media (prefers-reduced-motion: reduce) {
  .rp-done-badge { animation: none; }
  .rp-check { animation: none; stroke-dashoffset: 0; }
}
</style>
