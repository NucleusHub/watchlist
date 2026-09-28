<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { isNative, haptic } from '@/native.js'
import { readJson, writeJson } from '@/storage/persist.js'
import { useNucleusId } from '@/auth/nucleusId.js'
import logo from '@/assets/nucleus-logo-transparent.png'

// Shown once, on the first launch of the iOS app. Keeping the watchlist on
// the device is the default path; a Nucleus ID account is the optional extra.
const SEEN_KEY = 'watchlist-welcome-seen'

const { t } = useI18n()
const { isSignedIn, signIn } = useNucleusId()
const show = ref(false)

onMounted(async () => {
  if (!isNative || isSignedIn.value) return
  if (!(await readJson(SEEN_KEY))) show.value = true
})

watch(show, (open) => { document.body.style.overflow = open ? 'hidden' : '' })
onBeforeUnmount(() => { document.body.style.overflow = '' })

function close() {
  show.value = false
  writeJson(SEEN_KEY, true).catch(() => {})
}

function start() {
  haptic('Light')
  close()
}

function syncInstead() {
  close()
  signIn()
}

const POINTS = [
  {
    key: 'device',
    tone: 'indigo',
    d: 'M10.5 1.5H8.25A2.25 2.25 0 006 3.75v16.5a2.25 2.25 0 002.25 2.25h7.5A2.25 2.25 0 0018 20.25V3.75a2.25 2.25 0 00-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 18.75h3',
  },
  {
    key: 'backup',
    tone: 'emerald',
    d: 'M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
  },
  {
    key: 'sync',
    tone: 'violet',
    d: 'M2.25 15a4.5 4.5 0 004.5 4.5H18a3.75 3.75 0 001.332-7.257 3 3 0 00-3.758-3.848 5.25 5.25 0 00-10.233 2.33A4.502 4.502 0 002.25 15z',
  },
]
</script>

<template>
  <Teleport to="body">
    <Transition name="wm">
      <div v-if="show" class="wm-root" role="dialog" aria-modal="true" :aria-label="t('watchlist.welcome.title')">
        <div class="wm-scrim" />

        <div class="wm-sheet">
          <div class="wm-hero" aria-hidden="true">
            <div class="wm-glow" />
            <div class="wm-poster wm-poster--l">
              <span class="wm-line w-3/5" /><span class="wm-line w-2/5" />
            </div>
            <div class="wm-poster wm-poster--r">
              <span class="wm-line w-1/2" /><span class="wm-line w-1/3" />
            </div>
            <div class="wm-poster wm-poster--c">
              <span class="wm-play">
                <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 translate-x-px"><path d="M8 5.14v13.72a1 1 0 001.5.86l11-6.86a1 1 0 000-1.72l-11-6.86A1 1 0 008 5.14z" /></svg>
              </span>
              <span class="wm-stars">
                <svg v-for="n in 5" :key="n" viewBox="0 0 24 24" fill="currentColor" :class="['w-3 h-3', n === 5 && 'opacity-40']"><path d="M11.48 3.5a.56.56 0 011.04 0l2.13 5.1a.56.56 0 00.47.35l5.52.44c.5.04.7.66.32.99l-4.2 3.6a.56.56 0 00-.18.56l1.28 5.38a.56.56 0 01-.84.61l-4.72-2.88a.56.56 0 00-.59 0l-4.72 2.88a.56.56 0 01-.84-.61l1.28-5.38a.56.56 0 00-.18-.56l-4.2-3.6a.56.56 0 01.32-.99l5.52-.44a.56.56 0 00.47-.35z" /></svg>
              </span>
              <span class="wm-line w-3/4" /><span class="wm-line w-1/2" />
            </div>
            <span class="wm-chip">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" class="w-3 h-3"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>
              {{ t('watchlist.welcome.chip') }}
            </span>
          </div>

          <div class="wm-body">
            <h2 class="wm-title wm-in" style="--i: 0">{{ t('watchlist.welcome.title') }}</h2>
            <p class="wm-subtitle wm-in" style="--i: 1">{{ t('watchlist.welcome.subtitle') }}</p>

            <ul class="wm-points">
              <li v-for="(p, i) in POINTS" :key="p.key" class="wm-point wm-in" :style="{ '--i': i + 2 }">
                <span :class="['wm-point-icon', `wm-tone-${p.tone}`]">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round" :d="p.d" />
                  </svg>
                </span>
                <span class="min-w-0">
                  <span class="wm-point-title">{{ t(`watchlist.welcome.${p.key}Title`) }}</span>
                  <span class="wm-point-desc">{{ t(`watchlist.welcome.${p.key}Desc`) }}</span>
                </span>
              </li>
            </ul>

            <div class="wm-actions wm-in" style="--i: 5">
              <button type="button" class="wm-primary" @click="start">
                <span class="wm-shine" aria-hidden="true" />
                {{ t('watchlist.welcome.start') }}
              </button>
              <p class="wm-hint">{{ t('watchlist.welcome.startHint') }}</p>
              <button type="button" class="wm-secondary" @click="syncInstead">
                <img :src="logo" alt="" class="w-5 h-5" />
                {{ t('watchlist.welcome.syncCta') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.wm-root {
  position: fixed;
  inset: 0;
  z-index: 300;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}
@media (min-width: 640px) {
  .wm-root { align-items: center; padding: 24px; }
}

.wm-scrim {
  position: absolute;
  inset: 0;
  background: rgba(2, 6, 23, 0.45);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

.wm-sheet {
  position: relative;
  width: 100%;
  max-width: 440px;
  max-height: 94vh;
  overflow-y: auto;
  overscroll-behavior: contain;
  border-radius: 34px 34px 0 0;
  padding-bottom: max(20px, env(safe-area-inset-bottom));
  background:
    radial-gradient(120% 60% at 50% 0%, rgba(129, 140, 248, 0.22), transparent 70%),
    rgba(255, 255, 255, 0.86);
  backdrop-filter: blur(40px) saturate(1.6);
  -webkit-backdrop-filter: blur(40px) saturate(1.6);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow: 0 -20px 60px rgba(15, 23, 42, 0.25);
}
@media (min-width: 640px) {
  .wm-sheet { border-radius: 34px; padding-bottom: 24px; }
}
.dark .wm-sheet {
  background:
    radial-gradient(120% 60% at 50% 0%, rgba(139, 92, 246, 0.32), transparent 70%),
    rgba(15, 12, 34, 0.86);
  border-color: rgba(255, 255, 255, 0.1);
}

/* ── Hero: a little stack of posters ─────────────────────────────── */
.wm-hero {
  position: relative;
  height: 210px;
  display: grid;
  place-items: center;
  margin-bottom: 4px;
}
.wm-glow {
  position: absolute;
  width: 240px;
  height: 240px;
  border-radius: 9999px;
  background: conic-gradient(from 180deg, #818cf8, #c084fc, #f472b6, #818cf8);
  filter: blur(48px);
  opacity: 0.45;
  animation: wm-spin 14s linear infinite;
}
.dark .wm-glow { opacity: 0.55; }

.wm-poster {
  position: absolute;
  top: 34px;
  width: 104px;
  height: 150px;
  border-radius: 16px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  gap: 6px;
  box-shadow: 0 18px 40px rgba(30, 27, 75, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.35);
  animation: wm-float 6s ease-in-out infinite;
}
.wm-poster--l {
  background: linear-gradient(160deg, #38bdf8, #6366f1);
  transform: translateX(-74px) rotate(-12deg);
  animation-delay: -2s;
  --r: -12deg;
  --x: -74px;
}
.wm-poster--r {
  background: linear-gradient(160deg, #f472b6, #a855f7);
  transform: translateX(74px) rotate(12deg);
  animation-delay: -4s;
  --r: 12deg;
  --x: 74px;
}
.wm-poster--c {
  top: 22px;
  width: 118px;
  height: 170px;
  z-index: 1;
  background: linear-gradient(160deg, #1e1b4b 0%, #4338ca 55%, #7c3aed 100%);
  --r: 0deg;
  --x: 0px;
}
.wm-line {
  display: block;
  height: 6px;
  border-radius: 9999px;
  background: rgba(255, 255, 255, 0.55);
}
.wm-line + .wm-line { opacity: 0.6; }
.wm-play {
  position: absolute;
  top: 50%;
  left: 50%;
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
  margin: -34px 0 0 -22px;
  border-radius: 9999px;
  color: #4338ca;
  background: rgba(255, 255, 255, 0.92);
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.25);
}
.wm-stars { display: flex; gap: 2px; color: #fcd34d; margin-bottom: 2px; }

.wm-chip {
  position: absolute;
  z-index: 2;
  bottom: 14px;
  left: 50%;
  transform: translateX(-50%);
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px 6px 8px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 600;
  white-space: nowrap;
  color: #065f46;
  background: rgba(255, 255, 255, 0.95);
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.18);
  animation: wm-pop 0.5s 0.45s cubic-bezier(0.34, 1.56, 0.64, 1) both;
}
.wm-chip svg {
  box-sizing: content-box;
  padding: 3px;
  border-radius: 9999px;
  color: #fff;
  background: #10b981;
}
.dark .wm-chip { color: #a7f3d0; background: rgba(30, 27, 60, 0.95); }

/* ── Copy ─────────────────────────────────────────────────────────── */
.wm-body { padding: 0 24px; }
.wm-title {
  text-align: center;
  font-size: 28px;
  line-height: 1.15;
  font-weight: 700;
  letter-spacing: -0.02em;
  white-space: pre-line;
  color: rgb(15 23 42);
}
.dark .wm-title { color: #fff; }
.wm-subtitle {
  margin: 8px auto 0;
  max-width: 320px;
  text-align: center;
  font-size: 15px;
  line-height: 1.45;
  color: rgb(100 116 139);
}
.dark .wm-subtitle { color: rgba(255, 255, 255, 0.6); }

.wm-points { display: flex; flex-direction: column; gap: 16px; margin: 26px 0 28px; }
.wm-point { display: flex; align-items: flex-start; gap: 14px; }
.wm-point-icon {
  display: grid;
  place-items: center;
  width: 42px;
  height: 42px;
  border-radius: 13px;
  flex-shrink: 0;
}
.wm-tone-indigo { color: #4f46e5; background: rgba(99, 102, 241, 0.13); }
.wm-tone-emerald { color: #059669; background: rgba(16, 185, 129, 0.13); }
.wm-tone-violet { color: #7c3aed; background: rgba(139, 92, 246, 0.13); }
.dark .wm-tone-indigo { color: #a5b4fc; background: rgba(129, 140, 248, 0.16); }
.dark .wm-tone-emerald { color: #6ee7b7; background: rgba(52, 211, 153, 0.14); }
.dark .wm-tone-violet { color: #c4b5fd; background: rgba(167, 139, 250, 0.16); }
.wm-point-title { display: block; font-size: 16px; font-weight: 600; color: rgb(15 23 42); }
.wm-point-desc { display: block; margin-top: 2px; font-size: 14px; line-height: 1.4; color: rgb(100 116 139); }
.dark .wm-point-title { color: #fff; }
.dark .wm-point-desc { color: rgba(255, 255, 255, 0.55); }

/* ── Actions ──────────────────────────────────────────────────────── */
.wm-actions { display: flex; flex-direction: column; align-items: stretch; }
.wm-primary {
  position: relative;
  overflow: hidden;
  height: 56px;
  border-radius: 18px;
  font-size: 17px;
  font-weight: 650;
  color: #fff;
  cursor: pointer;
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 55%, #a855f7 100%);
  box-shadow: 0 12px 28px rgba(99, 102, 241, 0.42), inset 0 1px 0 rgba(255, 255, 255, 0.3);
  transition: transform 0.18s cubic-bezier(0.22, 1, 0.36, 1), box-shadow 0.18s ease;
}
.wm-primary:active { transform: scale(0.97); box-shadow: 0 6px 16px rgba(99, 102, 241, 0.35); }
.wm-shine {
  position: absolute;
  inset: 0;
  background: linear-gradient(100deg, transparent 30%, rgba(255, 255, 255, 0.35) 50%, transparent 70%);
  transform: translateX(-120%);
  animation: wm-shine 3.2s 1.1s ease-in-out infinite;
}
.wm-hint {
  margin: 10px 0 18px;
  text-align: center;
  font-size: 13px;
  color: rgb(100 116 139);
}
.dark .wm-hint { color: rgba(255, 255, 255, 0.5); }
.wm-secondary {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  height: 48px;
  border-radius: 16px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  color: rgb(51 65 85);
  background: rgba(15, 23, 42, 0.05);
  border: 1px solid rgba(15, 23, 42, 0.06);
  transition: transform 0.18s ease, background-color 0.18s ease;
}
.wm-secondary:active { transform: scale(0.97); background: rgba(15, 23, 42, 0.09); }
.dark .wm-secondary { color: rgba(255, 255, 255, 0.85); background: rgba(255, 255, 255, 0.07); border-color: rgba(255, 255, 255, 0.08); }

/* ── Motion ───────────────────────────────────────────────────────── */
.wm-in { animation: wm-rise 0.55s calc(0.12s + var(--i) * 0.06s) cubic-bezier(0.22, 1, 0.36, 1) both; }

.wm-enter-active, .wm-leave-active { transition: opacity 0.3s ease; }
.wm-enter-from, .wm-leave-to { opacity: 0; }
.wm-enter-active .wm-sheet { transition: transform 0.5s cubic-bezier(0.22, 1, 0.36, 1); }
.wm-leave-active .wm-sheet { transition: transform 0.28s ease-in; }
.wm-enter-from .wm-sheet, .wm-leave-to .wm-sheet { transform: translateY(100%); }
@media (min-width: 640px) {
  .wm-enter-from .wm-sheet, .wm-leave-to .wm-sheet { transform: translateY(24px) scale(0.97); }
}

@keyframes wm-float {
  0%, 100% { transform: translateX(var(--x)) translateY(0) rotate(var(--r)); }
  50% { transform: translateX(var(--x)) translateY(-8px) rotate(var(--r)); }
}
@keyframes wm-spin { to { transform: rotate(360deg); } }
@keyframes wm-rise { from { opacity: 0; transform: translateY(14px); } }
@keyframes wm-pop { from { opacity: 0; transform: translateX(-50%) translateY(8px) scale(0.8); } }
@keyframes wm-shine {
  0% { transform: translateX(-120%); }
  45%, 100% { transform: translateX(120%); }
}

@media (prefers-reduced-motion: reduce) {
  .wm-poster, .wm-glow, .wm-shine, .wm-in, .wm-chip { animation: none; }
  .wm-enter-from .wm-sheet, .wm-leave-to .wm-sheet { transform: none; }
}
</style>
