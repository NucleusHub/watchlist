import { createLiquidGlass } from '@avenra/liquid-glass'
import { getSvgPath } from 'figma-squircle'

// Refraction profiles: `dome` for small round controls, the default for bars and cards.
const PROFILES = {
  panel: { bezelWidth: 16, glassThickness: 70, refractiveIndex: 1.5, blur: 2.5, saturation: 1.7, specularSlope: 0.5 },
  dome: { bezelWidth: 12, glassThickness: 50, refractiveIndex: 1.6, blur: 1.2, saturation: 1.7, specularSlope: 0.7 },
}
// Only Chromium can point backdrop-filter at an SVG filter; elsewhere `.glass` alone is the frosted fallback.
const canRefract = () =>
  typeof window !== 'undefined' && !!window.chrome && CSS.supports?.('backdrop-filter', 'url(#x)') &&
  !window.matchMedia?.('(prefers-reduced-transparency: reduce)').matches

// v-glass: frosted glass. v-glass.dome or v-glass="'live'" adds real refraction, kept to small header
// controls: the filter is recomputed every frame content moves beneath it, so large panels stay frosted.
// v-glass="false" leaves the element plain.
export const vGlass = {
  mounted(el, { value, modifiers }) {
    if (value === false) return
    el.classList.add('glass')
    if (!(modifiers.dome || value === 'live') || !canRefract()) return
    try {
      el._glass = createLiquidGlass(el, PROFILES[modifiers.dome ? 'dome' : 'panel'])
      el.classList.add('lg-host', 'lg-live')
    } catch {}
  },
  // A bound :class rewrites the whole attribute on change, dropping the classes added above.
  updated(el, { value }) {
    if (value === false) return
    el.classList.add('glass')
    if (el._glass) el.classList.add('lg-host', 'lg-live')
  },
  beforeUnmount(el) {
    el._glass?.destroy()
    el._glass = null
  },
}

// v-squircle: G2 corners by clip-path where CSS corner-shape is missing. Only for unshadowed boxes (posters, artwork).
const nativeSquircle = typeof CSS !== 'undefined' && CSS.supports?.('corner-shape', 'squircle')
const observed = new WeakSet()
let ro = null

function clip(el) {
  const { width, height } = el.getBoundingClientRect()
  const radius = parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0
  if (!width || !height || !radius) return
  el.style.clipPath = `path('${getSvgPath({ width, height, cornerRadius: radius * 1.25, cornerSmoothing: 0.6 })}')`
}

export const vSquircle = nativeSquircle
  ? {}
  : {
      mounted(el) {
        ro ??= new ResizeObserver((entries) => entries.forEach((e) => clip(e.target)))
        ro.observe(el)
        observed.add(el)
      },
      beforeUnmount(el) {
        if (observed.has(el)) ro?.unobserve(el)
      },
    }

