export function requireVerifiedCustomer(req, res, next) {
  const appUser = req.appUser;
  const firebaseUser = req.firebaseUser;

  if (!appUser || !firebaseUser) {
    return res.status(401).json({ message: 'Unauthenticated' });
  }

  if (appUser.role === 'customer' && !firebaseUser.email_verified) {
    return res.status(403).json({ error: 'Email not verified' });
  }

  return next();
}
