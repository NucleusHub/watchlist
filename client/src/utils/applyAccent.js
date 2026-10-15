import { setAppAccent } from '@core/useAppearance.js'
import { accentHex } from '@/utils/accent.js'

// Core recolours the whole page (stylesheets, wallpaper, glass) onto the accent; kept apart so accent.js stays testable in Node.
export const applyAccent = (accent) => setAppAccent(accentHex(accent))
