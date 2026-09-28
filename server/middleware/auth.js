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
