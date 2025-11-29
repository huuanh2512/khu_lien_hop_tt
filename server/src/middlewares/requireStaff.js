export function requireStaff(req, res, next) {
  const appUser = req.appUser;
  if (!appUser) {
    return res.status(401).json({ message: 'Unauthenticated' });
  }

  if (appUser.role !== 'staff') {
    return res.status(403).json({ message: 'Staff only' });
  }

  return next();
}
