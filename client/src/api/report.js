import { isNative } from '@/native.js'
import { NUCLEUS_ID_ORIGIN, nucleusFetch } from '@/auth/nucleusId.js'

// Bug reports go to the Nucleus site (nucleus-web: server/src/routes/reports.js),
// which mails them to the team. Nothing is kept there.
const ENDPOINT = '/api/v1/reports'

export const MAX_ATTACHMENTS = 4
const MAX_SIDE = 1600

const OS_NAMES = { ios: 'iOS', android: 'Android', mac: 'macOS', windows: 'Windows', unknown: '' }

// iOS reports the hardware identifier, which is not the name on the box:
// "iPhone17,3" is an iPhone 16. Unknown ones are sent as they are.
const IPHONES = {
  'iPhone10,1': 'iPhone 8', 'iPhone10,4': 'iPhone 8', 'iPhone10,2': 'iPhone 8 Plus', 'iPhone10,5': 'iPhone 8 Plus',
  'iPhone10,3': 'iPhone X', 'iPhone10,6': 'iPhone X',
  'iPhone11,2': 'iPhone XS', 'iPhone11,4': 'iPhone XS Max', 'iPhone11,6': 'iPhone XS Max', 'iPhone11,8': 'iPhone XR',
  'iPhone12,1': 'iPhone 11', 'iPhone12,3': 'iPhone 11 Pro', 'iPhone12,5': 'iPhone 11 Pro Max', 'iPhone12,8': 'iPhone SE (2nd generation)',
  'iPhone13,1': 'iPhone 12 mini', 'iPhone13,2': 'iPhone 12', 'iPhone13,3': 'iPhone 12 Pro', 'iPhone13,4': 'iPhone 12 Pro Max',
  'iPhone14,4': 'iPhone 13 mini', 'iPhone14,5': 'iPhone 13', 'iPhone14,2': 'iPhone 13 Pro', 'iPhone14,3': 'iPhone 13 Pro Max',
  'iPhone14,6': 'iPhone SE (3rd generation)', 'iPhone14,7': 'iPhone 14', 'iPhone14,8': 'iPhone 14 Plus',
  'iPhone15,2': 'iPhone 14 Pro', 'iPhone15,3': 'iPhone 14 Pro Max', 'iPhone15,4': 'iPhone 15', 'iPhone15,5': 'iPhone 15 Plus',
  'iPhone16,1': 'iPhone 15 Pro', 'iPhone16,2': 'iPhone 15 Pro Max',
  'iPhone17,1': 'iPhone 16 Pro', 'iPhone17,2': 'iPhone 16 Pro Max', 'iPhone17,3': 'iPhone 16', 'iPhone17,4': 'iPhone 16 Plus',
  'iPhone17,5': 'iPhone 16e',
  'iPhone18,1': 'iPhone 17 Pro', 'iPhone18,2': 'iPhone 17 Pro Max', 'iPhone18,3': 'iPhone 17', 'iPhone18,4': 'iPhone Air',
}
const modelName = (id) => (id === 'x86_64' || id === 'arm64' ? 'Simulator' : IPHONES[id] || id)

let cached = null
/** What the report says about the app and the phone — asked once per launch. */
export function collectDiagnostics() {
  cached ??= (async () => {
    const [{ Device }, appInfo] = await Promise.all([
      import('@capacitor/device'),
      isNative ? import('@capacitor/app').then(({ App }) => App.getInfo()).catch(() => null) : null,
    ])
    const d = await Device.getInfo().catch(() => ({}))
    return {
      app: appInfo
        ? { id: appInfo.id, name: appInfo.name, version: appInfo.version, build: appInfo.build }
        : { id: 'watchlist', name: 'Watchlist', version: __APP_VERSION__ },
      device: {
        model: modelName(d.model || ''),
        modelId: d.model && modelName(d.model) !== d.model ? d.model : '',
        manufacturer: d.manufacturer || '',
        platform: d.platform || '',
        os: OS_NAMES[d.operatingSystem] ?? d.operatingSystem ?? '',
        osVersion: d.osVersion || '',
        webView: isNative ? '' : d.webViewVersion || '',
      },
    }
  })()
  return cached
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => resolve({ img, url })
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('unreadable'))
    }
    img.src = url
  })
}

/**
 * A picked photo, shrunk to a JPEG a mail server takes without complaint.
 * @returns {Promise<{ preview: string, type: string, data: string }>} data is base64
 */
export async function prepareImage(file) {
  const { img, url } = await loadImage(file)
  const scale = Math.min(1, MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(img.naturalWidth * scale)
  canvas.height = Math.round(img.naturalHeight * scale)
  canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height)
  const dataUrl = canvas.toDataURL('image/jpeg', 0.82)
  return { preview: url, type: 'image/jpeg', data: dataUrl.slice(dataUrl.indexOf(',') + 1) }
}

/**
 * @param {{ title: string, description: string, email?: string, asAccount: boolean,
 *   attachments: { type: string, data: string }[], locale?: string }} report
 */
export async function sendReport({ title, description, email, asAccount, attachments, locale }) {
  const diagnostics = await collectDiagnostics()
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      title,
      description,
      email: email || undefined,
      locale,
      ...diagnostics,
      attachments: attachments.map(({ type, data }) => ({ type, data })),
    }),
  }
  let res
  try {
    res = asAccount ? await nucleusFetch(ENDPOINT, options) : await fetch(NUCLEUS_ID_ORIGIN + ENDPOINT, options)
  } catch (err) {
    if (err?.status) throw err
    // fetch only says "it failed": no connection, or the server couldn't be
    // reached (down, or refusing this origin) — tell the two apart.
    const code = navigator.onLine === false || err?.code === 'offline' ? 'offline' : 'unreachable'
    throw Object.assign(new Error(code), { code })
  }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw Object.assign(new Error(body.error?.message || `HTTP ${res.status}`), { status: res.status, code: body.error?.code })
  }
}
