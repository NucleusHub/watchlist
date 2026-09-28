import { registerFallback, useI18n } from '@core/useI18n.js'
import en from '../locales/en-US.json'
import cs from '../locales/cs-CZ.json'

// The iOS app has no home server to ask for a language: it follows the one
// picked for it in the iOS Settings app (Settings → Watchlist → Language),
// which WebKit reports first in navigator.languages. iOS only offers the
// languages listed under CFBundleLocalizations in ios/App/App/Info.plist —
// keep that list in step with this one.
const LOCALES = { 'en-US': en, 'cs-CZ': cs }

function deviceLocale() {
  const tags = navigator.languages?.length ? navigator.languages : [navigator.language]
  for (const tag of tags) {
    const lang = String(tag || '').toLowerCase().split('-')[0]
    const match = Object.keys(LOCALES).find((l) => l.toLowerCase().startsWith(`${lang}-`))
    if (match) return match
  }
  return 'en-US'
}

export function applyDeviceLocale() {
  const l = deviceLocale()
  // English underneath, so a string missing from a translation still reads.
  registerFallback({ ...en, ...LOCALES[l] })
  useI18n().locale.value = l
  document.documentElement.lang = l.split('-')[0]
}
