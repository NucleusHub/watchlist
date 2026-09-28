<script setup>
import { watch, onBeforeUnmount } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { haptic } from '@/native.js'

// A question with a few explained answers, as a sheet of option cards — for
// choices where each answer needs a line saying what it will do.
const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, default: '' },
  message: { type: String, default: '' },
  // [{ key, label, desc, icon, tone: 'indigo' | 'emerald' | 'violet' | 'red', recommended }]
  options: { type: Array, default: () => [] },
})
const emit = defineEmits(['choose', 'close'])
const { t } = useI18n()

const ICONS = {
  merge: 'M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
  sparkle: 'M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456z',
  device: 'M10.5 1.5H8.25A2.25 2.25 0 006 3.75v16.5a2.25 2.25 0 002.25 2.25h7.5A2.25 2.25 0 0018 20.25V3.75a2.25 2.25 0 00-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 18.75h3',
  trash: 'M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0',
  replace: 'M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99',
}

watch(() => props.show, (open) => { document.body.style.overflow = open ? 'hidden' : '' })
onBeforeUnmount(() => { document.body.style.overflow = '' })

function choose(o) {
  haptic('Light')
  emit('choose', o.key)
}
</script>

<template>
  <Teleport to="body">
    <Transition name="cm">
      <div v-if="show" class="cm-root" role="dialog" aria-modal="true" :aria-label="title">
        <div class="cm-scrim" @click="emit('close')" />
        <div class="cm-sheet">
          <span class="cm-grabber" aria-hidden="true" />
          <h2 class="cm-title">{{ title }}</h2>
          <p v-if="message" class="cm-message">{{ message }}</p>

          <div class="cm-options">
            <button
              v-for="(o, i) in options"
              :key="o.key"
              type="button"
              :class="['cm-option', { 'is-recommended': o.recommended, 'is-danger': o.tone === 'red' }]"
              :style="{ '--i': i }"
              @click="choose(o)"
            >
              <span :class="['cm-icon', `cm-tone-${o.tone || 'indigo'}`]">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" class="w-[22px] h-[22px]">
                  <path stroke-linecap="round" stroke-linejoin="round" :d="ICONS[o.icon] || ICONS.merge" />
                </svg>
              </span>
              <span class="cm-text">
                <span class="cm-label">
                  {{ o.label }}
                  <span v-if="o.recommended" class="cm-badge">{{ t('watchlist.choice.recommended') }}</span>
                </span>
                <span v-if="o.desc" class="cm-desc">{{ o.desc }}</span>
              </span>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" class="cm-chevron">
                <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
              </svg>
            </button>
          </div>

          <button type="button" class="cm-cancel" @click="emit('close')">{{ t('watchlist.data.cancel') }}</button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.cm-root {
  position: fixed;
  inset: 0;
  z-index: 300;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}
@media (min-width: 640px) {
  .cm-root { align-items: center; padding: 24px; }
}
.cm-scrim {
  position: absolute;
  inset: 0;
  background: rgba(2, 6, 23, 0.4);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}

.cm-sheet {
  position: relative;
  width: 100%;
  max-width: 440px;
  padding: 10px 16px max(16px, env(safe-area-inset-bottom));
  border-radius: 30px 30px 0 0;
  background:
    radial-gradient(120% 50% at 50% 0%, rgba(129, 140, 248, 0.16), transparent 70%),
    rgba(248, 250, 252, 0.9);
  backdrop-filter: blur(40px) saturate(1.6);
  -webkit-backdrop-filter: blur(40px) saturate(1.6);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow: 0 -16px 50px rgba(15, 23, 42, 0.22);
}
@media (min-width: 640px) {
  .cm-sheet { border-radius: 30px; padding-bottom: 16px; }
}
.dark .cm-sheet {
  background:
    radial-gradient(120% 50% at 50% 0%, rgba(139, 92, 246, 0.24), transparent 70%),
    rgba(17, 14, 36, 0.9);
  border-color: rgba(255, 255, 255, 0.1);
}

.cm-grabber {
  display: block;
  width: 38px;
  height: 5px;
  margin: 0 auto 16px;
  border-radius: 9999px;
  background: rgba(15, 23, 42, 0.15);
}
.dark .cm-grabber { background: rgba(255, 255, 255, 0.2); }
@media (min-width: 640px) { .cm-grabber { visibility: hidden; margin-bottom: 8px; } }

.cm-title {
  padding: 0 8px;
  text-align: center;
  font-size: 20px;
  font-weight: 700;
  letter-spacing: -0.01em;
  color: rgb(15 23 42);
}
.dark .cm-title { color: #fff; }
.cm-message {
  margin: 6px auto 0;
  max-width: 330px;
  padding: 0 8px;
  text-align: center;
  font-size: 14px;
  line-height: 1.45;
  color: rgb(100 116 139);
}
.dark .cm-message { color: rgba(255, 255, 255, 0.55); }

.cm-options { display: flex; flex-direction: column; gap: 10px; margin: 20px 0 8px; }

.cm-option {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  padding: 14px 14px 14px 12px;
  border-radius: 20px;
  text-align: left;
  cursor: pointer;
  background: rgba(255, 255, 255, 0.75);
  border: 1px solid rgba(15, 23, 42, 0.06);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  transition: transform 0.18s cubic-bezier(0.22, 1, 0.36, 1), background-color 0.18s ease;
  animation: cm-rise 0.45s calc(0.08s + var(--i) * 0.06s) cubic-bezier(0.22, 1, 0.36, 1) both;
}
.cm-option:active { transform: scale(0.98); background: rgba(255, 255, 255, 0.95); }
.dark .cm-option { background: rgba(255, 255, 255, 0.06); border-color: rgba(255, 255, 255, 0.08); box-shadow: none; }
.dark .cm-option:active { background: rgba(255, 255, 255, 0.1); }

.cm-option.is-recommended {
  background: linear-gradient(135deg, rgba(99, 102, 241, 0.1), rgba(168, 85, 247, 0.08)), rgba(255, 255, 255, 0.85);
  border-color: rgba(99, 102, 241, 0.35);
  box-shadow: 0 6px 20px rgba(99, 102, 241, 0.14);
}
.dark .cm-option.is-recommended {
  background: linear-gradient(135deg, rgba(129, 140, 248, 0.18), rgba(192, 132, 252, 0.12));
  border-color: rgba(165, 180, 252, 0.35);
}

.cm-icon {
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
  border-radius: 14px;
  flex-shrink: 0;
}
.cm-tone-indigo { color: #4f46e5; background: rgba(99, 102, 241, 0.13); }
.cm-tone-emerald { color: #059669; background: rgba(16, 185, 129, 0.13); }
.cm-tone-violet { color: #7c3aed; background: rgba(139, 92, 246, 0.13); }
.cm-tone-red { color: #dc2626; background: rgba(239, 68, 68, 0.12); }
.dark .cm-tone-indigo { color: #a5b4fc; background: rgba(129, 140, 248, 0.16); }
.dark .cm-tone-emerald { color: #6ee7b7; background: rgba(52, 211, 153, 0.14); }
.dark .cm-tone-violet { color: #c4b5fd; background: rgba(167, 139, 250, 0.16); }
.dark .cm-tone-red { color: #fca5a5; background: rgba(248, 113, 113, 0.14); }

.cm-text { flex: 1; min-width: 0; }
.cm-label {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 16px;
  font-weight: 600;
  color: rgb(15 23 42);
}
.dark .cm-label { color: #fff; }
.is-danger .cm-label { color: #dc2626; }
.dark .is-danger .cm-label { color: #f87171; }
.cm-desc {
  display: block;
  margin-top: 2px;
  font-size: 13px;
  line-height: 1.35;
  color: rgb(100 116 139);
}
.dark .cm-desc { color: rgba(255, 255, 255, 0.5); }

.cm-badge {
  padding: 2px 7px;
  border-radius: 9999px;
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #fff;
  background: linear-gradient(135deg, #6366f1, #a855f7);
}

.cm-chevron {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: rgb(148 163 184);
}
.dark .cm-chevron { color: rgba(255, 255, 255, 0.3); }

.cm-cancel {
  display: block;
  width: 100%;
  height: 48px;
  border-radius: 16px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  color: rgb(79 70 229);
  transition: background-color 0.15s ease;
}
.cm-cancel:active { background: rgba(99, 102, 241, 0.08); }
.dark .cm-cancel { color: rgb(196 181 253); }

.cm-enter-active, .cm-leave-active { transition: opacity 0.28s ease; }
.cm-enter-from, .cm-leave-to { opacity: 0; }
.cm-enter-active .cm-sheet { transition: transform 0.45s cubic-bezier(0.22, 1, 0.36, 1); }
.cm-leave-active .cm-sheet { transition: transform 0.25s ease-in; }
.cm-enter-from .cm-sheet, .cm-leave-to .cm-sheet { transform: translateY(100%); }
@media (min-width: 640px) {
  .cm-enter-from .cm-sheet, .cm-leave-to .cm-sheet { transform: translateY(20px) scale(0.97); }
}

@keyframes cm-rise { from { opacity: 0; transform: translateY(10px); } }

@media (prefers-reduced-motion: reduce) {
  .cm-option { animation: none; }
  .cm-enter-from .cm-sheet, .cm-leave-to .cm-sheet { transform: none; }
}
</style>
