import express from 'express';
import admin from '../firebase.js';
import { authMiddleware } from '../middlewares/authMiddleware.js';
import { requireAdmin } from '../middlewares/requireAdmin.js';
import User from '../models/User.js';

function normalizeId(value) {
  if (!value) return null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length ? trimmed : null;
  }
  if (typeof value === 'object' && typeof value.toHexString === 'function') {
    return value.toHexString();
  }
  try {
    const asString = String(value);
    return asString.trim().length ? asString.trim() : null;
  } catch (_) {
    return null;
  }
}

const router = express.Router();

function parseDateValue(raw) {
  if (!raw) return undefined;
  if (raw instanceof Date) {
    return Number.isNaN(raw.valueOf()) ? undefined : raw;
  }
  const value = new Date(raw);
  return Number.isNaN(value.valueOf()) ? undefined : value;
}

// ---------------------------------------------
// CUSTOMER REGISTER VIA FIREBASE
// ---------------------------------------------
router.post('/register-firebase', authMiddleware, async (req, res) => {
  try {
    const firebaseUser = req.firebaseUser;
    if (!firebaseUser) {
      return res.status(401).json({ message: 'Missing Firebase user context' });
    }

    const { name, gender, birthday, dateOfBirth, mainSportId } = req.body || {};
    const dobInput = dateOfBirth ?? birthday ?? null;
    const parsedDob = parseDateValue(dobInput);

    const clauses = [{ firebaseUid: firebaseUser.uid }];
    const normalizedEmail = firebaseUser.email ? User.normalizeEmail(firebaseUser.email) : null;
    if (normalizedEmail) {
      clauses.push({ email: normalizedEmail });
    }

    const filter = clauses.length > 1 ? { $or: clauses } : clauses[0];
    let user = await User.findOne(filter);

    if (!user) {
      user = await User.create({
        firebaseUid: firebaseUser.uid,
        email: normalizedEmail,
        name,
        gender,
        dateOfBirth: parsedDob ?? null,
        mainSportId,
        role: 'customer',
      });
    } else {
      const updates = {};
      if (!user.firebaseUid) updates.firebaseUid = firebaseUser.uid;
      if (name !== undefined) updates.name = name ?? user.name;
      if (gender !== undefined) updates.gender = gender ?? user.gender;
      if (dobInput !== null && parsedDob !== undefined) {
        updates.dateOfBirth = parsedDob;
      }
      if (mainSportId !== undefined) {
        updates.mainSportId = mainSportId ?? user.mainSportId;
      }
      if (Object.keys(updates).length) {
        user = await User.updateById(user._id, updates);
      }
    }

    return res.json({
      success: true,
      user: {
        id: user._id,
        firebaseUid: user.firebaseUid,
        email: user.email,
        role: user.role,
        name: user.name,
        gender: user.gender,
        dateOfBirth: user.dateOfBirth ?? null,
        mainSportId: user.mainSportId ?? null,
      },
    });
  } catch (err) {
    console.error('[register-firebase] error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
});

function validateAdminCreatePayload(body = {}) {
  const { email, password, name, gender, birthday } = body;
  const normalizedEmail = User.normalizeEmail(email);
  if (!normalizedEmail) {
    return { error: 'Email is required' };
  }
  if (typeof password !== 'string' || password.length < 6) {
    return { error: 'Password must be at least 6 characters' };
  }
  return {
    email: normalizedEmail,
    password,
    name,
    gender,
    birthday: parseDateValue(birthday) ?? null,
  };
}

async function createStaffLikeUser({ role, body, res }) {
  const payload = validateAdminCreatePayload(body);
  if (payload.error) {
    return res.status(400).json({ message: payload.error });
  }

  const existing = await User.findOne({ email: payload.email });
  if (existing) {
    return res.status(409).json({ message: 'Email already in use' });
  }

  const fbUser = await admin.auth().createUser({
    email: payload.email,
    password: payload.password,
    emailVerified: false,
    disabled: false,
  });

  const user = await User.create({
    firebaseUid: fbUser.uid,
    email: payload.email,
    name: payload.name,
    gender: payload.gender,
    dateOfBirth: payload.birthday,
    birthday: payload.birthday,
    role,
  });

  return res.json({
    success: true,
    user: {
      id: user._id,
      firebaseUid: user.firebaseUid,
      email: user.email,
      role: user.role,
      name: user.name,
      gender: user.gender,
      birthday: user.dateOfBirth ?? null,
    },
  });
}

// ---------------------------------------------
// ADMIN CREATE STAFF
// ---------------------------------------------
router.post('/create-staff', authMiddleware, requireAdmin, async (req, res) => {
  try {
    await createStaffLikeUser({ role: 'staff', body: req.body, res });
  } catch (err) {
    console.error('[create-staff] error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
});

// ---------------------------------------------
// ADMIN CREATE ADMIN
// ---------------------------------------------
router.post('/create-admin', authMiddleware, requireAdmin, async (req, res) => {
  try {
    await createStaffLikeUser({ role: 'admin', body: req.body, res });
  } catch (err) {
    console.error('[create-admin] error:', err);
    return res.status(500).json({ message: 'Server error' });
  }
});

router.get('/me', authMiddleware, async (req, res) => {
  try {
    const user = req.appUser;
    return res.json({
      id: normalizeId(user._id),
      _id: normalizeId(user._id),
      email: user.email,
      role: user.role,
      name: user.name,
      status: user.status ?? 'active',
      phone: user.phone ?? null,
      facilityId: normalizeId(user.facilityId),
      gender: user.gender ?? null,
      dateOfBirth: user.dateOfBirth ?? null,
      mainSportId: normalizeId(user.mainSportId),
      createdAt: user.createdAt ?? null,
      updatedAt: user.updatedAt ?? null,
    });
  } catch (err) {
    console.error('[authRoutes] Failed to resolve /api/auth/me', err);
    return res.status(500).json({ message: 'Server error' });
  }
});

export default router;
