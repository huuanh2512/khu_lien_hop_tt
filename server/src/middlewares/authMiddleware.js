import admin from '../firebase.js';
import User from '../models/User.js';

function extractBearerToken(headerValue) {
  if (!headerValue || typeof headerValue !== 'string') {
    return null;
  }
  const trimmed = headerValue.trim();
  if (!trimmed.toLowerCase().startsWith('bearer ')) {
    return null;
  }
  const token = trimmed.slice(7).trim();
  return token.length ? token : null;
}

export async function authMiddleware(req, res, next) {
  const token = extractBearerToken(req.headers?.authorization || '');
  if (!token) {
    return res.status(401).json({ message: 'No token provided' });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.firebaseUser = decoded;
    const findClauses = [{ firebaseUid: decoded.uid }];
    if (decoded.email) {
      findClauses.push({ email: decoded.email.trim().toLowerCase() });
    }

    const filter = findClauses.length > 1 ? { $or: findClauses } : findClauses[0];
    let user = await User.findOne(filter);

    if (!user) {
      user = await User.create({
        firebaseUid: decoded.uid,
        email: decoded.email?.trim().toLowerCase() ?? null,
        role: 'customer',
      });
    } else if (!user.firebaseUid) {
      user = await User.updateFirebaseUid(user._id, decoded.uid);
    }

    req.appUser = user;
    req.authToken = token;
    return next();
  } catch (error) {
    console.error('[authMiddleware] verifyIdToken error', error);
    return res.status(401).json({ message: 'Invalid token' });
  }
}
