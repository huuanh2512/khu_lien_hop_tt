export function requireAdmin(req, res, next) {
  const appUser = req.appUser;
  if (!appUser) {
    return res.status(401).json({ message: 'Unauthenticated' });
  }

  if (appUser.role !== 'admin') {
    return res.status(403).json({ message: 'Admin only' });
  }

  return next();
}
