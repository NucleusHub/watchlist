// Auth disabled for the standalone iOS build — cookie-based cross-origin auth
// doesn't work reliably from a Capacitor WKWebView. Every request is treated
// as one fixed local profile instead of verifying a session cookie/JWT.
//
// To re-enable real auth, restore:
//   export { requireAuth, verifyToken, verifyProfile } from '../core/server/auth.js'
const LOCAL_PROFILE = { profileId: '000000000000000000000001', role: 'admin' }

export function requireAuth(req, res, next) {
  req.profile = LOCAL_PROFILE
  next()
}

export function verifyToken() {
  return LOCAL_PROFILE
}

export function verifyProfile() {
  return LOCAL_PROFILE
}
