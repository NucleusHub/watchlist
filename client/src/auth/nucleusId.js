import { ref, computed, readonly } from 'vue'
import { isNative } from '@/native.js'
import { readJson, writeJson, remove } from '@/storage/persist.js'
import { randomToken, challengeFor } from './pkce.js'

// Sign in with Nucleus ID — OAuth 2.0 authorization code + PKCE against the
// Nucleus site (nucleus-web: server/src/routes/nucleus-id.js). The app is a
// public client: no secret, the redirect comes back on the app's own URL
// scheme (registered in ios/App/App/Info.plist).
export const NUCLEUS_ID_ORIGIN = (import.meta.env.VITE_NUCLEUS_ID_ORIGIN || 'https://nucleus-home.dev').replace(/\/+$/, '')
const CLIENT_ID = import.meta.env.VITE_NUCLEUS_ID_CLIENT || 'watchlist'
// Pages on the Nucleus site the app links to: Apple requires both to be
// reachable from inside the app (account deletion: guideline 5.1.1(v)).
export const ACCOUNT_DELETE_URL = `${NUCLEUS_ID_ORIGIN}/account/delete`
export const PRIVACY_URL = `${NUCLEUS_ID_ORIGIN}/privacy`
const REDIRECT_URI = 'com.nucleushome.watchlist:/oauth'
const SCOPE = 'profile data'

const SESSION_KEY = 'watchlist-nucleus-id'
const PENDING_KEY = 'watchlist-nucleus-id-pending'
const REFRESH_MARGIN_MS = 60 * 1000

const session = ref(null) // { accessToken, refreshToken, expiresAt, user }
const signingIn = ref(false)
const error = ref('')
const signedInHooks = new Set()
const signedOutHooks = new Set()

class AuthError extends Error {
  constructor(message, { status, code } = {}) {
    super(message)
    this.status = status
    this.code = code
  }
}

async function save(next) {
  session.value = next
  if (next) await writeJson(SESSION_KEY, next)
  else await remove(SESSION_KEY)
}

async function tokenRequest(params) {
  let res
  try {
    res = await fetch(`${NUCLEUS_ID_ORIGIN}/api/v1/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: CLIENT_ID, ...params }),
    })
  } catch {
    throw new AuthError('offline', { code: 'offline' })
  }
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new AuthError(body.error_description || 'Sign-in failed', { status: res.status, code: body.error })
  return {
    accessToken: body.access_token,
    refreshToken: body.refresh_token,
    expiresAt: Date.now() + (body.expires_in || 3600) * 1000,
  }
}

async function fetchUser(accessToken) {
  const res = await fetch(`${NUCLEUS_ID_ORIGIN}/api/v1/oauth/userinfo`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!res.ok) throw new AuthError('Could not load your account', { status: res.status })
  const { sub, preferred_username, name, email } = await res.json()
  return { sub, handle: preferred_username, name: name || preferred_username, email: email || null }
}

let refreshing = null
function refreshTokens() {
  // Two requests racing to refresh would rotate the token twice and the
  // loser would sign the person out; share the one in flight.
  refreshing ??= (async () => {
    try {
      const tokens = await tokenRequest({ grant_type: 'refresh_token', refresh_token: session.value.refreshToken })
      await save({ ...session.value, ...tokens })
    } catch (err) {
      if (err.code === 'invalid_grant') await endSession({ expired: true })
      throw err
    } finally {
      refreshing = null
    }
  })()
  return refreshing
}

/** fetch() against Nucleus ID with a valid access token, refreshing as needed. */
export async function nucleusFetch(path, options = {}) {
  if (!session.value) throw new AuthError('Not signed in', { status: 401 })
  if (session.value.expiresAt - Date.now() < REFRESH_MARGIN_MS) await refreshTokens()
  const send = () =>
    fetch(`${NUCLEUS_ID_ORIGIN}${path}`, {
      ...options,
      headers: { ...options.headers, Authorization: `Bearer ${session.value.accessToken}` },
    })
  let res = await send()
  if (res.status === 401 && session.value) {
    await refreshTokens()
    res = await send()
  }
  return res
}

async function endSession({ expired = false, clean = false } = {}) {
  await save(null)
  if (expired) error.value = 'expired'
  for (const fn of signedOutHooks) await fn({ expired, clean })
}

let browser = null
async function openBrowser(url) {
  if (!isNative) return window.location.assign(url)
  browser ??= (await import('@capacitor/browser')).Browser
  await browser.open({ url, presentationStyle: 'popover' })
}

/**
 * @param {{ mode?: 'keep' | 'clean' }} options  keep: merge this device's
 *   watchlist into the account; clean: drop it and use only the account's.
 */
export async function signIn({ mode = 'keep' } = {}) {
  error.value = ''
  signingIn.value = true
  try {
    const verifier = randomToken(48)
    const state = randomToken(16)
    await writeJson(PENDING_KEY, { verifier, state, mode })
    const url = new URL(`${NUCLEUS_ID_ORIGIN}/authorize`)
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: CLIENT_ID,
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      state,
      code_challenge: await challengeFor(verifier),
      code_challenge_method: 'S256',
    })
    await openBrowser(url.href)
  } catch (err) {
    signingIn.value = false
    error.value = err.message || 'failed'
  }
}

async function handleCallback(rawUrl) {
  if (!rawUrl?.startsWith(REDIRECT_URI)) return
  browser?.close().catch(() => {})
  const params = new URL(rawUrl).searchParams
  const pending = await readJson(PENDING_KEY)
  await remove(PENDING_KEY)
  try {
    if (params.get('error')) {
      if (params.get('error') !== 'access_denied') error.value = params.get('error_description') || 'failed'
      return
    }
    if (!pending || params.get('state') !== pending.state) throw new AuthError('Sign-in expired, please try again.')
    const tokens = await tokenRequest({
      grant_type: 'authorization_code',
      code: params.get('code'),
      redirect_uri: REDIRECT_URI,
      code_verifier: pending.verifier,
    })
    const user = await fetchUser(tokens.accessToken)
    await save({ ...tokens, user })
    for (const fn of signedInHooks) await fn(user, { mode: pending.mode || 'keep' })
  } catch (err) {
    error.value = err.code === 'offline' ? 'offline' : err.message || 'failed'
  } finally {
    signingIn.value = false
  }
}

/** @param {{ clean?: boolean }} options  clean: also empty the watchlist on this device. */
export async function signOut({ clean = false } = {}) {
  const token = session.value?.refreshToken
  await endSession({ clean })
  if (!token) return
  fetch(`${NUCLEUS_ID_ORIGIN}/api/v1/oauth/revoke`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: CLIENT_ID, token }),
  }).catch(() => {})
}

export const onSignedIn = (fn) => signedInHooks.add(fn)
export const onSignedOut = (fn) => signedOutHooks.add(fn)

let initialized = false
export async function initNucleusId() {
  if (initialized) return
  initialized = true
  session.value = await readJson(SESSION_KEY)
  if (!isNative) return
  const { App } = await import('@capacitor/app')
  App.addListener('appUrlOpen', ({ url }) => handleCallback(url))
  const { Browser } = await import('@capacitor/browser')
  browser = Browser
  // Closing the sheet without finishing leaves no callback to end the spinner.
  Browser.addListener('browserFinished', () => setTimeout(() => { signingIn.value = false }, 800))
  if (session.value) {
    fetchUser(session.value.accessToken)
      .catch(() => refreshTokens().then(() => fetchUser(session.value.accessToken)))
      .then((user) => user && save({ ...session.value, user }))
      .catch(() => {})
  }
}

export function useNucleusId() {
  return {
    account: computed(() => session.value?.user ?? null),
    isSignedIn: computed(() => !!session.value),
    signingIn: readonly(signingIn),
    error,
    signIn,
    signOut,
  }
}
