import admin from '../firebase.js';
import User from '../models/User.js';
import { ObjectId } from 'mongodb';

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

function buildIdFilterFromPayloadId(value) {
  if (!value) return null;
  if (value instanceof ObjectId) {
    return { _id: value };
  }
  const raw = String(value).trim();
  if (!raw.length) return null;
  if (ObjectId.isValid(raw)) {
    return { _id: new ObjectId(raw) };
  }
  return { _id: raw };
}

async function resolveFirebaseAuthContext(req, token) {
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
    return { ok: true };
  } catch (error) {
    return { ok: false, error };
  }
}

function extractUserIdFromJwt(payload) {
  if (!payload || typeof payload !== 'object') return null;
  return payload.sub ?? payload._id ?? payload.id ?? null;
}

export async function authMiddleware(req, res, next) {
  const token = extractBearerToken(req.headers?.authorization || '');
  if (!token) {
    return res.status(401).json({ message: 'No token provided' });
  }

  const firebaseResult = await resolveFirebaseAuthContext(req, token);
  if (firebaseResult.ok) {
    req.authToken = token;
    return next();
  }

  if (firebaseResult.error) {
    console.error('[authMiddleware] Failed to verify Firebase token', firebaseResult.error);
  }
  return res.status(401).json({ message: 'Invalid token' });
}
