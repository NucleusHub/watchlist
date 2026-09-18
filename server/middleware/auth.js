// Thin re-export of the vendored core auth (core/server/auth.js). Kept as a
// stable local path so existing `../middleware/auth.js` imports across this
// app's routes (and Echo's Socket.IO handshake) keep working unchanged.
export { requireAuth, verifyToken, verifyProfile } from '../core/server/auth.js'
