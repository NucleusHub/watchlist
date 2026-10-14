// The report body the iOS ReportSheet posts to nucleus-home.dev, with web device details.
export const REPORT_URL = 'https://nucleus-home.dev/api/v1/reports'
export const MAX_SHOTS = 4

const osOf = (ua) => (/Windows/.test(ua) ? 'windows' : /Android/.test(ua) ? 'android' : /iPhone|iPad/.test(ua) ? 'ios' : /Mac/.test(ua) ? 'macos' : /Linux/.test(ua) ? 'linux' : 'web')

export function buildReport({ title, details, email, shots, version, locale, ua, platform }) {
  const body = {
    title: title.trim().slice(0, 200),
    description: details.trim().slice(0, 10000),
    locale,
    app: { id: 'watchlist', name: 'Watchlist', version, build: '' },
    device: { model: 'Browser', modelId: platform || '', manufacturer: '', platform: 'web', os: osOf(ua), osVersion: '', webView: ua },
    attachments: shots.map((data) => ({ type: 'image/jpeg', data })),
  }
  if (email.trim()) body.email = email.trim()
  return body
}

export const validEmail = (s) => !s.trim() || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s.trim())
