import dotenv from 'dotenv';
dotenv.config();
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import fs from 'node:fs';
import { Int32, MongoClient, ObjectId, ReturnDocument } from 'mongodb';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { quotePrice } from './pricing.js';
import authRoutes from './routes/authRoutes.js';
import { authMiddleware } from './middlewares/authMiddleware.js';
import { requireAdmin } from './middlewares/requireAdmin.js';
import { requireStaff } from './middlewares/requireStaff.js';
import { requireVerifiedCustomer } from './middlewares/requireVerifiedCustomer.js';

const app = express();
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true);
    if (!allowedOrigins.length || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
}));
app.use(express.json());
app.use(morgan('dev'));

// Mongo connection details come from env so we can deploy anywhere.
const MONGODB_URI = process.env.MONGODB_URI;
if (!MONGODB_URI) {
  throw new Error('MONGODB_URI is not set');
}
const DB_NAME = process.env.MONGODB_DB_NAME || 'khu_lien_hop_tt';
let client; let db;
const JWT_SECRET = process.env.JWT_SECRET || 'dev_secret_change_me';
const STAFF_PLACEHOLDER_EMAIL_DOMAIN = 'staff-placeholder.local';
const AUTO_CANCEL_PENDING_MINUTES = Number(process.env.AUTO_CANCEL_PENDING_MINUTES ?? 10);
const AUTO_CANCEL_SWEEP_INTERVAL_MS = Number(process.env.AUTO_CANCEL_SWEEP_INTERVAL_MS ?? 60_000);
const SYSTEM_ACTOR_ID = (() => {
  const candidate = process.env.SYSTEM_ACTOR_ID;
  if (candidate && ObjectId.isValid(candidate)) {
    return new ObjectId(candidate);
  }
  return new ObjectId('000000000000000000000000');
})();

// Allowed statuses for courts
const COURT_ALLOWED_STATUSES = new Set(['active', 'inactive', 'maintenance', 'deleted']);

async function connectMongo() {
  client = new MongoClient(MONGODB_URI);
  await client.connect();
  db = client.db(DB_NAME);
  console.log(`[mongo] Connected to database ${DB_NAME}`);
}

// Health
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' });
});

// --- Auth helpers ---
function authenticate(req, _res, next) {
  try {
    const h = req.headers?.authorization;
    if (h && typeof h === 'string' && h.startsWith('Bearer ')) {
      const token = h.substring('Bearer '.length);
      const payload = jwt.verify(token, JWT_SECRET);
      req.user = payload; // { sub, role, iat, exp }
    }
  } catch (_) {
    // ignore invalid tokens
  }
  next();
}

app.use(authenticate);
app.use('/api/auth', authRoutes);
app.use('/api/staff', authMiddleware, requireStaff);
app.use('/api/admin', authMiddleware, requireAdmin);

const SENSITIVE_AUDIT_KEYS = new Set(['password','passwordhash','resetpassword','token','authorization','authtoken','resettoken']);

function sanitizeAuditData(value) {
  if (value === undefined || value === null) return undefined;
  if (value instanceof ObjectId) return value.toHexString();
  if (value instanceof Date) return value;
  if (Array.isArray(value)) {
    return value
      .map((item) => sanitizeAuditData(item))
      .filter((item) => item !== undefined);
  }
  if (typeof value === 'object') {
    const result = {};
    for (const [key, raw] of Object.entries(value)) {
      const lower = key.toLowerCase();
      if (SENSITIVE_AUDIT_KEYS.has(lower)) continue;
      const sanitized = sanitizeAuditData(raw);
      if (sanitized !== undefined) result[key] = sanitized;
    }
    return result;
  }
  if (typeof value === 'function') return undefined;
  if (typeof value === 'string' && value.length > 2000) {
    return `${value.substring(0, 1997)}...`; // avoid huge payloads
  }
  return value;
}

function cleanObject(obj) {
  if (!obj || typeof obj !== 'object') return undefined;
  const next = { ...obj };
  Object.keys(next).forEach((k) => {
    if (next[k] === undefined || next[k] === null) delete next[k];
  });
  return Object.keys(next).length ? next : undefined;
}

function coerceNumber(value) {
  if (value === undefined || value === null) return null;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'object' && typeof value.valueOf === 'function') {
    const converted = value.valueOf();
    if (typeof converted === 'number' && Number.isFinite(converted)) return converted;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function buildIdCandidates(idParam) {
  const raw = String(idParam ?? '').trim();
  if (!raw) return [];
  const seen = new Set();
  const values = [];

  const add = (value) => {
    if (value === undefined || value === null) return;
    const key = value instanceof ObjectId ? `oid:${value.toHexString()}` : `str:${String(value)}`;
    if (seen.has(key)) return;
    seen.add(key);
    values.push(value);
  };

  add(raw);
  if (ObjectId.isValid(raw)) {
    add(new ObjectId(raw));
  }

  const match = raw.match(/^ObjectId\((?:"|')?([0-9a-fA-F]{24})(?:"|')?\)$/);
  if (match) {
    const hex = match[1];
    add(hex);
    add(`ObjectId("${hex}")`);
    add(`ObjectId('${hex}')`);
    add(`ObjectId(${hex})`);
    if (ObjectId.isValid(hex)) add(new ObjectId(hex));
  }

  const hexOnly = raw.replace(/[^0-9a-fA-F]/g, '');
  if (hexOnly.length === 24) {
    add(hexOnly);
    add(`ObjectId("${hexOnly}")`);
    add(`ObjectId('${hexOnly}')`);
    add(`ObjectId(${hexOnly})`);
    if (ObjectId.isValid(hexOnly)) {
      add(new ObjectId(hexOnly));
    }
  }

  return values;
}

function buildComparableIdSet(value) {
  const inputs = Array.isArray(value) ? value : buildIdCandidates(value);
  const set = new Set();

  const addNormalized = (input) => {
    if (input === undefined || input === null) return;
    if (input instanceof ObjectId) {
      set.add(input.toHexString().toLowerCase());
      return;
    }
    const raw = String(input).trim();
    if (!raw) return;
    if (ObjectId.isValid(raw)) {
      set.add(new ObjectId(raw).toHexString().toLowerCase());
      return;
    }
    const match = raw.match(/([0-9a-fA-F]{24})/);
    if (match && ObjectId.isValid(match[1])) {
      set.add(match[1].toLowerCase());
      return;
    }
    set.add(raw.toLowerCase());
  };

  for (const item of inputs) addNormalized(item);
  return set;
}

function buildIdMatchFilter(idParam) {
  const candidates = buildIdCandidates(idParam);
  if (!candidates.length) return { _id: idParam };

  const orClauses = [];
  const objectIdCandidates = candidates.filter((item) => item instanceof ObjectId);
  if (objectIdCandidates.length) {
    orClauses.push({ _id: { $in: objectIdCandidates } });
  }
  const stringCandidates = candidates.filter((item) => typeof item === 'string');
  if (stringCandidates.length) {
    orClauses.push({ _id: { $in: stringCandidates } });
  }

  if (!orClauses.length) return { _id: idParam };
  if (orClauses.length === 1) return orClauses[0];
  return { $or: orClauses };
}

function escapeRegex(value) {
  return String(value ?? '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function logDeleteDebug(entry) {
  try {
    const payload = {
      ts: new Date().toISOString(),
      ...entry,
    };
    const replacer = (_key, value) => (value instanceof ObjectId ? { $oid: value.toHexString() } : value);
    fs.appendFileSync('delete-debug.log', `${JSON.stringify(payload, replacer)}\n`);
  } catch (err) {
    console.error('[admin.users:delete] failed to write debug log', err);
  }
}

function buildSyntheticStaffEmail(id) {
  const rawId = id instanceof ObjectId ? id.toHexString() : String(id ?? '').trim();
  const token = rawId || new ObjectId().toHexString();
  return `staff+${token}@${STAFF_PLACEHOLDER_EMAIL_DOMAIN}`;
}

function isSyntheticStaffEmail(value) {
  return typeof value === 'string' && value.endsWith(`@${STAFF_PLACEHOLDER_EMAIL_DOMAIN}`);
}

function sanitizeStaffContact(user) {
  if (!user || typeof user !== 'object') return user;
  const cloned = { ...user };
  if (cloned._id instanceof ObjectId) cloned._id = cloned._id.toHexString();
  const syntheticFlag = cloned.syntheticEmail === true || isSyntheticStaffEmail(cloned.email);
  if (syntheticFlag) {
    cloned.syntheticEmail = true;
    cloned.email = null;
  }
  return cloned;
}

function normalizeStringArrayInput(value) {
  if (!value) return [];
  if (Array.isArray(value)) {
    return value
      .map((item) => (item == null ? '' : String(item).trim()))
      .filter((item) => item.length);
  }
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length);
  }
  if (typeof value === 'object') {
    return Object.values(value)
      .map((item) => (item == null ? '' : String(item).trim()))
      .filter((item) => item.length);
  }
  return [];
}

function coerceObjectId(value) {
  if (value == null) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  if (ObjectId.isValid(raw)) return new ObjectId(raw);
  const match = raw.match(/([0-9a-fA-F]{24})/);
  if (match && ObjectId.isValid(match[1])) return new ObjectId(match[1]);
  return null;
}

const ALLOWED_GENDERS = new Set(['male', 'female', 'other']);

function normalizeGenderInput(value) {
  if (value === undefined) return { provided: false };
  if (value === null) return { provided: true, value: null };
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed.length) {
      return { provided: true, value: null };
    }
    const lower = trimmed.toLowerCase();
    if (ALLOWED_GENDERS.has(lower)) {
      return { provided: true, value: lower };
    }
  }
  return { provided: true, error: 'invalid_gender' };
}

function coerceDateValue(input) {
  if (input === undefined || input === null) return null;
  if (input instanceof Date) {
    return Number.isNaN(input.valueOf()) ? null : input;
  }
  if (typeof input === 'number') {
    const d = new Date(input);
    return Number.isNaN(d.valueOf()) ? null : d;
  }
  if (typeof input === 'string') {
    const trimmed = input.trim();
    if (!trimmed.length) return null;
    const d = new Date(trimmed);
    return Number.isNaN(d.valueOf()) ? null : d;
  }
  if (typeof input === 'object') {
    if (input.$date !== undefined) return coerceDateValue(input.$date);
    if (input.date !== undefined) return coerceDateValue(input.date);
    if (input.value !== undefined) return coerceDateValue(input.value);
    if (input.iso !== undefined) return coerceDateValue(input.iso);
  }
  return null;
}

function normalizeDateInput(value) {
  if (value === undefined) return { provided: false };
  if (value === null) return { provided: true, value: null };
  if (typeof value === 'string' && !value.trim().length) {
    return { provided: true, value: null };
  }
  const parsed = coerceDateValue(value);
  if (parsed) return { provided: true, value: parsed };
  return { provided: true, error: 'invalid_date' };
}

function normalizeObjectIdInput(value) {
  if (value === undefined) return { provided: false };
  if (value === null) return { provided: true, value: null };
  const trimmed = typeof value === 'string' ? value.trim() : value;
  if (trimmed === '' || trimmed === null) {
    return { provided: true, value: null };
  }
  const oid = coerceObjectId(trimmed);
  if (oid) return { provided: true, value: oid };
  return { provided: true, error: 'invalid_object_id' };
}

function normalizeIdString(value) {
  if (value instanceof ObjectId) return value.toHexString();
  if (value && typeof value === 'object' && typeof value.toHexString === 'function') {
    return value.toHexString();
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed.length) return null;
    if (ObjectId.isValid(trimmed)) return new ObjectId(trimmed).toHexString();
    return trimmed;
  }
  return null;
}

function getAppUserObjectId(req) {
  if (!req) return null;
  const candidates = [];
  if (req.appUser) {
    candidates.push(req.appUser._id, req.appUser.id, req.appUser.userId);
  }
  if (req.user) {
    candidates.push(req.user._id, req.user.id, req.user.sub);
  }
  if (req.firebaseUser) {
    candidates.push(req.firebaseUser.uid);
  }
  for (const candidate of candidates) {
    const oid = coerceObjectId(candidate);
    if (oid) return oid;
  }
  return null;
}

function extractUserName(user) {
  if (!user || typeof user !== 'object') return null;
  if (typeof user.name === 'string' && user.name.trim().length) {
    return user.name.trim();
  }
  const profile = user.profile && typeof user.profile === 'object' ? user.profile : null;
  if (profile) {
    if (typeof profile.fullName === 'string' && profile.fullName.trim().length) {
      return profile.fullName.trim();
    }
    if (typeof profile.name === 'string' && profile.name.trim().length) {
      return profile.name.trim();
    }
  }
  return null;
}

function shapeAuthUser(userDoc) {
  if (!userDoc || typeof userDoc !== 'object') return null;
  const dateOfBirth = userDoc.dateOfBirth ?? userDoc.birthday ?? null;
  const shaped = {
    _id: normalizeIdString(userDoc._id),
    id: normalizeIdString(userDoc._id),
    email: typeof userDoc.email === 'string' ? userDoc.email : null,
    role: typeof userDoc.role === 'string' ? userDoc.role : 'customer',
    status: typeof userDoc.status === 'string' ? userDoc.status : 'active',
    name: extractUserName(userDoc),
    phone: typeof userDoc.phone === 'string' ? userDoc.phone : null,
    facilityId: normalizeIdString(userDoc.facilityId),
    gender: typeof userDoc.gender === 'string' ? userDoc.gender : null,
    dateOfBirth,
    mainSportId: normalizeIdString(userDoc.mainSportId),
    createdAt: userDoc.createdAt ?? null,
    updatedAt: userDoc.updatedAt ?? null,
  };
  if (!shaped.email && isSyntheticStaffEmail(userDoc.email)) {
    shaped.syntheticEmail = true;
  }
  return shaped;
}

function shapeUserProfile(userDoc) {
  const shaped = shapeAuthUser(userDoc);
  if (!shaped) return null;
  return {
    id: shaped.id,
    _id: shaped._id,
    email: shaped.email,
    name: shaped.name,
    phone: shaped.phone,
    gender: shaped.gender,
    dateOfBirth: shaped.dateOfBirth,
    mainSportId: shaped.mainSportId,
    facilityId: shaped.facilityId,
    status: shaped.status,
    role: shaped.role,
    syntheticEmail: shaped.syntheticEmail ?? false,
  };
}

function normalizeNotificationStatus(value) {
  if (typeof value !== 'string') return 'unread';
  const trimmed = value.trim().toLowerCase();
  return trimmed === 'read' ? 'read' : 'unread';
}

function shapeNotification(doc) {
  if (!doc || typeof doc !== 'object') return null;
  return {
    _id: normalizeIdString(doc._id),
    id: normalizeIdString(doc._id),
    title: typeof doc.title === 'string' ? doc.title : '',
    message: typeof doc.message === 'string' ? doc.message : '',
    status: normalizeNotificationStatus(doc.status),
    channel: typeof doc.channel === 'string' ? doc.channel : null,
    priority: typeof doc.priority === 'string' ? doc.priority : null,
    data: sanitizeAuditData(doc.data) ?? null,
    createdAt: doc.createdAt ?? doc.at ?? doc.insertedAt ?? null,
    updatedAt: doc.updatedAt ?? null,
    readAt: doc.readAt ?? null,
    recipientRole: typeof doc.recipientRole === 'string' ? doc.recipientRole : null,
    recipientId: normalizeIdString(doc.recipientId),
    facilityId: normalizeIdString(doc.facilityId),
  };
}

const DOC_CACHE_TTL_MS = 5 * 60 * 1000;
const facilityCache = new Map();
const courtCache = new Map();
const sportCache = new Map();

function getCachedDocument(cache, key) {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.cachedAt > DOC_CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.doc;
}

function setCachedDocument(cache, key, doc) {
  if (!doc) return;
  cache.set(key, { doc, cachedAt: Date.now() });
}

async function fetchFacilityById(id) {
  if (!id) return null;
  if (id && typeof id === 'object' && id._id) return id;
  const objectId = coerceObjectId(id);
  if (!objectId) return null;
  const cacheKey = objectId.toHexString();
  const cached = getCachedDocument(facilityCache, cacheKey);
  if (cached) return cached;
  const doc = await db.collection('facilities').findOne({ _id: objectId });
  if (doc) setCachedDocument(facilityCache, cacheKey, doc);
  return doc;
}

async function fetchCourtById(id) {
  if (!id) return null;
  if (id && typeof id === 'object' && id._id) return id;
  const objectId = coerceObjectId(id);
  if (!objectId) return null;
  const cacheKey = objectId.toHexString();
  const cached = getCachedDocument(courtCache, cacheKey);
  if (cached) return cached;
  const doc = await db.collection('courts').findOne({ _id: objectId });
  if (doc) setCachedDocument(courtCache, cacheKey, doc);
  return doc;
}

async function fetchSportById(id) {
  if (!id) return null;
  if (id && typeof id === 'object' && id._id) return id;
  const objectId = coerceObjectId(id);
  if (!objectId) return null;
  const cacheKey = objectId.toHexString();
  const cached = getCachedDocument(sportCache, cacheKey);
  if (cached) return cached;
  const doc = await db.collection('sports').findOne({ _id: objectId });
  if (doc) setCachedDocument(sportCache, cacheKey, doc);
  return doc;
}

async function fetchStaffUser(req, { refresh = false } = {}) {
  if (!req) return null;
  if (!refresh && req.staffUser) return req.staffUser;
  const staffId = getAppUserObjectId(req);
  if (!staffId) return null;
  const staffDoc = await db.collection('users').findOne({ _id: staffId, role: 'staff', status: { $ne: 'deleted' } });
  if (!staffDoc) return null;
  const sanitized = { ...staffDoc };
  if (isSyntheticStaffEmail(sanitized.email)) {
    sanitized.syntheticEmail = true;
    sanitized.email = null;
  }
  req.staffUser = sanitized;
  return sanitized;
}

function shapeMatchRequest(doc, { currentUserId } = {}) {
  if (!doc || typeof doc !== 'object') return null;
  const currentId = coerceObjectId(currentUserId);
  const normalizedMode = normalizeMatchRequestMode(doc.mode);
  const toHex = (value) => {
    if (value instanceof ObjectId) return value.toHexString();
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (!trimmed.length) return null;
      if (ObjectId.isValid(trimmed)) return new ObjectId(trimmed).toHexString();
      return trimmed;
    }
    return null;
  };

  const participants = Array.isArray(doc.participants)
    ? doc.participants.map((value) => toHex(value)).filter(Boolean)
    : [];

  const teamArray = (source) => (Array.isArray(source)
    ? source.map((value) => toHex(value)).filter(Boolean)
    : []);

  const teams = {
    teamA: teamArray(doc.teams?.teamA),
    teamB: teamArray(doc.teams?.teamB),
  };

  const buildTeamInfo = (teamDoc, fallbackCaptain) => {
    const captainId = toHex(teamDoc?.captainUserId ?? fallbackCaptain);
    const teamNameValue = typeof teamDoc?.teamName === 'string' ? normalizeTeamNameInput(teamDoc.teamName) : null;
    const info = cleanObject({
      captainUserId: captainId,
      teamName: teamNameValue,
    });
    return info ?? null;
  };

  const hostTeam = normalizedMode === 'team'
    ? (buildTeamInfo(doc.hostTeam, doc.creatorId) ?? buildTeamInfo({ captainUserId: doc.creatorId }, null))
    : null;
  const guestTeam = normalizedMode === 'team'
    ? buildTeamInfo(doc.guestTeam, null)
    : null;

  const creatorId = coerceObjectId(doc.creatorId);
  let joinedTeam = null;
  const currentHex = currentId ? currentId.toHexString() : null;
  if (currentHex) {
    if (teams.teamA.some((id) => id === currentHex)) joinedTeam = 'teamA';
    else if (teams.teamB.some((id) => id === currentHex)) joinedTeam = 'teamB';
  }

  return cleanObject({
    _id: toHex(doc._id),
    id: toHex(doc._id),
    sportId: toHex(doc.sportId),
    facilityId: toHex(doc.facilityId),
    courtId: toHex(doc.courtId),
    creatorId: toHex(doc.creatorId),
    facility: sanitizeAuditData(doc.facility) ?? null,
    court: sanitizeAuditData(doc.court) ?? null,
    sport: sanitizeAuditData(doc.sport) ?? null,
    desiredStart: doc.desiredStart ?? doc.start ?? null,
    desiredEnd: doc.desiredEnd ?? doc.end ?? null,
    mode: normalizedMode,
    status: typeof doc.status === 'string' ? doc.status : 'open',
    bookingStatus: typeof doc.bookingStatus === 'string' ? doc.bookingStatus : undefined,
    visibility: typeof doc.visibility === 'string' ? doc.visibility : 'public',
    skillRange: doc.skillRange ?? null,
    teamSize: doc.teamSize ?? null,
    participantLimit: doc.participantLimit ?? null,
    location: doc.location ?? null,
    notes: doc.notes ?? null,
    participants,
    participantCount: participants.length,
    teams,
    hostTeam,
    guestTeam,
    joinedTeam,
    isCreator: creatorId && currentId ? creatorId.equals(currentId) : false,
    createdAt: doc.createdAt ?? null,
    updatedAt: doc.updatedAt ?? null,
  });
}

async function fetchMatchRequests({ filter = {}, match, limit = 20, sort = { updatedAt: -1, _id: -1 }, currentUserId } = {}) {
  if (!db) return [];
  const matchStage = match || filter || {};
  const pipeline = [];
  if (matchStage && Object.keys(matchStage).length) {
    pipeline.push({ $match: matchStage });
  }
  pipeline.push(
    { $lookup: { from: 'facilities', localField: 'facilityId', foreignField: '_id', as: 'facility' } },
    { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
    { $lookup: { from: 'courts', localField: 'courtId', foreignField: '_id', as: 'court' } },
    { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
    { $lookup: { from: 'sports', localField: 'sportId', foreignField: '_id', as: 'sport' } },
    { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
  );
  if (sort) pipeline.push({ $sort: sort });
  const normalizedLimit = Number.isFinite(limit) ? Math.max(1, Math.min(200, Number(limit))) : null;
  if (normalizedLimit) pipeline.push({ $limit: normalizedLimit });
  const docs = await db.collection('match_requests').aggregate(pipeline).toArray();
  return docs.map((doc) => shapeMatchRequest(doc, { currentUserId }));
}

const TEAM_ALIAS_MAP = new Map([
  ['teama', 'teamA'],
  ['team a', 'teamA'],
  ['team_a', 'teamA'],
  ['team-a', 'teamA'],
  ['team1', 'teamA'],
  ['a', 'teamA'],
  ['team b', 'teamB'],
  ['teamb', 'teamB'],
  ['team_b', 'teamB'],
  ['team-b', 'teamB'],
  ['team2', 'teamB'],
  ['b', 'teamB'],
]);

const TEAM_AUTO_VALUES = new Set(['auto', 'balanced', 'balance', 'even', 'either']);
const MATCH_REQUEST_ALLOWED_MODES = new Set(['solo','team']);

function normalizeTeamChoice(input) {
  if (input === undefined) return { provided: false };
  if (input === null) return { provided: true, value: null };
  const trimmed = String(input).trim();
  if (!trimmed.length) return { provided: true, value: null };
  const lower = trimmed.toLowerCase();
  if (TEAM_AUTO_VALUES.has(lower)) return { provided: true, value: 'auto' };
  if (TEAM_ALIAS_MAP.has(lower)) return { provided: true, value: TEAM_ALIAS_MAP.get(lower) };
  if (lower === 'teama' || lower === 'team a' || lower === 'team_a' || lower === 'team-a') return { provided: true, value: 'teamA' };
  if (lower === 'teamb' || lower === 'team b' || lower === 'team_b' || lower === 'team-b') return { provided: true, value: 'teamB' };
  if (trimmed === 'teamA' || trimmed === 'teamB') return { provided: true, value: trimmed };
  return { provided: true, error: 'invalid_team' };
}

function normalizeTeamNameInput(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed.length) return null;
  return trimmed.substring(0, 120);
}

function normalizeMatchRequestMode(value) {
  if (typeof value === 'string') {
    const trimmed = value.trim().toLowerCase();
    if (MATCH_REQUEST_ALLOWED_MODES.has(trimmed)) return trimmed;
  }
  return 'solo';
}

function resolveTeamCapacity(source) {
  if (!source || typeof source !== 'object') return null;
  const size = coerceNumber(source.teamSize);
  if (size && size > 0) return size;
  const limit = coerceNumber(source.participantLimit);
  if (limit && limit > 0) return Math.max(1, Math.ceil(limit / 2));
  return null;
}

const USER_BOOKING_ALLOWED_STATUSES = new Set(['pending', 'confirmed', 'cancelled', 'completed', 'matched']);

function normalizeBookingForResponse(doc) {
  if (!doc || typeof doc !== 'object') return doc;

  const currencyCandidates = [doc.currency, doc.pricingSnapshot?.currency];
  let currency = 'VND';
  for (const candidate of currencyCandidates) {
    if (typeof candidate === 'string' && candidate.trim().length) {
      currency = candidate.trim();
      break;
    }
  }

  const totalCandidates = [doc.total, doc.pricingSnapshot?.total];
  let total = null;
  for (const candidate of totalCandidates) {
    if (candidate === undefined || candidate === null) continue;
    if (typeof candidate === 'number' && Number.isFinite(candidate)) {
      total = candidate;
      break;
    }
    const parsed = Number.parseFloat(String(candidate));
    if (!Number.isNaN(parsed) && Number.isFinite(parsed)) {
      total = parsed;
      break;
    }
  }

  const toCleanString = (value) => {
    if (value === undefined || value === null) return null;
    const text = String(value).trim();
    return text.length ? text : null;
  };

  const participants = Array.isArray(doc.participants)
    ? doc.participants
        .map((item) => (item == null ? null : String(item).trim()))
        .filter((item) => item && item.length)
    : undefined;

  return {
    ...doc,
    currency,
    total,
    status: toCleanString(doc.status)?.toLowerCase() ?? 'pending',
    facilityName: toCleanString(doc.facilityName),
    courtName: toCleanString(doc.courtName),
    sportName: toCleanString(doc.sportName),
    participants,
  };
}

function deriveBookingInvoiceAmount(bookingDoc) {
  if (!bookingDoc) return 0;
  const candidates = [bookingDoc.total, bookingDoc.pricingSnapshot?.total, bookingDoc.pricingSnapshot?.subtotal];
  for (const candidate of candidates) {
    const normalized = coerceNumber(candidate);
    if (normalized !== null && Number.isFinite(normalized)) {
      return normalized;
    }
  }
  return 0;
}

function deriveBookingInvoiceCurrency(bookingDoc) {
  if (!bookingDoc) return 'VND';
  const candidates = [bookingDoc.currency, bookingDoc.pricingSnapshot?.currency];
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim().length) {
      return candidate.trim().toUpperCase();
    }
  }
  return 'VND';
}

function buildBookingInvoiceDescription(bookingDoc) {
  const parts = ['Thanh toán đặt sân'];
  const courtName = typeof bookingDoc?.courtName === 'string' && bookingDoc.courtName.trim().length
    ? bookingDoc.courtName.trim()
    : null;
  if (courtName) parts.push(courtName);
  const facilityName = typeof bookingDoc?.facilityName === 'string' && bookingDoc.facilityName.trim().length
    ? bookingDoc.facilityName.trim()
    : null;
  if (facilityName) parts.push(facilityName);
  const start = coerceDateValue(bookingDoc?.start);
  if (start instanceof Date && !Number.isNaN(start.valueOf())) {
    parts.push(start.toLocaleString('vi-VN', { hour12: false }));
  }
  return parts.join(' | ');
}

async function ensureBookingInvoice(bookingDoc, { issuedAt } = {}) {
  if (!db || !bookingDoc || typeof bookingDoc !== 'object') return null;
  const bookingId = coerceObjectId(bookingDoc._id ?? bookingDoc.bookingId);
  if (!bookingId) return null;

  const amount = deriveBookingInvoiceAmount(bookingDoc);
  const currency = deriveBookingInvoiceCurrency(bookingDoc);
  const dueAt = coerceDateValue(bookingDoc.end) ?? coerceDateValue(bookingDoc.start) ?? new Date();
  const description = buildBookingInvoiceDescription(bookingDoc);
  const now = new Date();

  const pricingSnapshot = bookingDoc.pricingSnapshot
    ? sanitizeAuditData(bookingDoc.pricingSnapshot)
    : undefined;

  const updateDoc = {
    $set: cleanObject({
      amount,
      currency,
      dueAt,
      description,
      pricingSnapshot,
      updatedAt: now,
    }) || {},
    $setOnInsert: cleanObject({
      bookingId,
      status: 'unpaid',
      issuedAt: issuedAt ?? now,
      createdAt: now,
    }) || {},
  };

    const result = await db.collection('invoices').findOneAndUpdate(
    { bookingId },
    updateDoc,
    { upsert: true, returnDocument: ReturnDocument.AFTER },
  );

  return result.value ?? null;
}

async function voidBookingInvoice(bookingDoc, { reason = 'booking_cancelled' } = {}) {
  if (!db || !bookingDoc || typeof bookingDoc !== 'object') return null;
  const bookingId = coerceObjectId(bookingDoc._id ?? bookingDoc.bookingId);
  if (!bookingId) return null;

  const now = new Date();
  const update = {
    $set: {
      status: 'void',
      voidedAt: now,
      voidReason: reason,
      updatedAt: now,
    },
  };

    const result = await db.collection('invoices').findOneAndUpdate(
    { bookingId },
    update,
    { returnDocument: ReturnDocument.AFTER },
  );

  return result.value ?? null;
}

function shapeStaffCustomer(userDoc) {
  if (!userDoc || typeof userDoc !== 'object') return null;
  const customer = {
    _id: normalizeIdString(userDoc._id),
    id: normalizeIdString(userDoc._id),
    name: extractUserName(userDoc) || (typeof userDoc.name === 'string' ? userDoc.name : null),
    email: typeof userDoc.email === 'string' ? userDoc.email : null,
    phone: typeof userDoc.phone === 'string' ? userDoc.phone : null,
  };
  if (!customer.name && userDoc.profile && typeof userDoc.profile === 'object') {
    if (typeof userDoc.profile.fullName === 'string' && userDoc.profile.fullName.trim().length) {
      customer.name = userDoc.profile.fullName.trim();
    } else if (typeof userDoc.profile.name === 'string' && userDoc.profile.name.trim().length) {
      customer.name = userDoc.profile.name.trim();
    }
  }
  return cleanObject(customer);
}

function shapeStaffBooking(doc) {
  if (!doc || typeof doc !== 'object') return null;
  const sanitized = sanitizeAuditData(doc) || {};
  const court = doc.court ? cleanObject({
    _id: normalizeIdString(doc.court._id),
    id: normalizeIdString(doc.court._id),
    name: typeof doc.court.name === 'string' ? doc.court.name : null,
    code: typeof doc.court.code === 'string' ? doc.court.code : null,
  }) : undefined;
  const sport = doc.sport ? cleanObject({
    _id: normalizeIdString(doc.sport._id),
    id: normalizeIdString(doc.sport._id),
    name: typeof doc.sport.name === 'string' ? doc.sport.name : null,
  }) : undefined;
  return cleanObject({
    ...sanitized,
    customer: shapeStaffCustomer(doc.customer) ?? undefined,
    court,
    sport,
  });
}

function normalizePaymentAmount(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  if (typeof value === 'object' && value && typeof value.valueOf === 'function') {
    const converted = value.valueOf();
    if (typeof converted === 'number' && Number.isFinite(converted)) return converted;
  }
  return 0;
}

function normalizePaymentTimestamp(payment) {
  if (!payment || typeof payment !== 'object') return null;
  const candidates = [payment.createdAt, payment.processedAt, payment.paidAt, payment.updatedAt];
  for (const candidate of candidates) {
    const coerced = coerceDateValue(candidate);
    if (coerced) return coerced;
  }
  return null;
}

function shapeStaffPayments(payments) {
  if (!Array.isArray(payments) || !payments.length) return [];
  return payments.map((payment) => {
    const sanitized = sanitizeAuditData(payment) || {};
    return {
      ...sanitized,
      amount: normalizePaymentAmount(sanitized.amount ?? payment.amount ?? 0),
    };
  });
}

function computePaymentTotals(payments) {
  const normalizedPayments = shapeStaffPayments(payments);
  let totalPaid = 0;
  let lastPaymentAt = null;
  for (const payment of normalizedPayments) {
    const status = typeof payment.status === 'string' ? payment.status.trim().toLowerCase() : '';
    if (status === 'failed' || status === 'cancelled' || status === 'voided') continue;
    totalPaid += normalizePaymentAmount(payment.amount);
    const timestamp = normalizePaymentTimestamp(payment);
    if (timestamp && (!lastPaymentAt || timestamp > lastPaymentAt)) {
      lastPaymentAt = timestamp;
    }
  }
  return { payments: normalizedPayments, totalPaid, lastPaymentAt };
}

function shapeStaffInvoice(doc) {
  if (!doc || typeof doc !== 'object') return null;
  const amount = coerceNumber(doc.amount) ?? 0;
  const currency = typeof doc.currency === 'string' && doc.currency.trim().length
    ? doc.currency.trim()
    : (typeof doc.bookingCurrency === 'string' && doc.bookingCurrency.trim().length
      ? doc.bookingCurrency.trim()
      : 'VND');

  const { payments, totalPaid, lastPaymentAt } = computePaymentTotals(doc.payments);
  const status = typeof doc.status === 'string' && doc.status.trim().length ? doc.status.trim() : 'unpaid';
  const inactiveStatuses = new Set(['void', 'cancelled', 'canceled', 'refunded']);
  const isInactive = inactiveStatuses.has(status.toLowerCase());
  const outstanding = isInactive ? 0 : Math.max(0, amount - totalPaid);

  const bookingInfo = doc.booking ? cleanObject({
    _id: normalizeIdString(doc.booking._id),
    id: normalizeIdString(doc.booking._id),
    start: doc.booking.start ?? null,
    end: doc.booking.end ?? null,
    status: typeof doc.booking.status === 'string' ? doc.booking.status : null,
    courtId: normalizeIdString(doc.booking.courtId),
    sportId: normalizeIdString(doc.booking.sportId),
  }) : undefined;

  const courtInfo = doc.court ? cleanObject({
    _id: normalizeIdString(doc.court._id),
    id: normalizeIdString(doc.court._id),
    name: typeof doc.court.name === 'string' ? doc.court.name : null,
    code: typeof doc.court.code === 'string' ? doc.court.code : null,
  }) : undefined;

  return cleanObject({
    _id: normalizeIdString(doc._id),
    id: normalizeIdString(doc._id),
    bookingId: normalizeIdString(doc.bookingId ?? doc.booking?._id),
    amount,
    currency,
    status,
    issuedAt: doc.issuedAt ?? doc.createdAt ?? doc.booking?.start ?? null,
    lastPaymentAt,
    totalPaid,
    outstanding,
    booking: bookingInfo,
    customer: shapeStaffCustomer(doc.customer) ?? undefined,
    court: courtInfo,
    payments,
  });
}

function shapeStaffFacilitySummary(facilityDoc) {
  if (!facilityDoc || typeof facilityDoc !== 'object') return null;
  return cleanObject({
    id: normalizeIdString(facilityDoc._id),
    _id: normalizeIdString(facilityDoc._id),
    name: typeof facilityDoc.name === 'string' ? facilityDoc.name : null,
    phone: typeof facilityDoc.phone === 'string' ? facilityDoc.phone : null,
    email: typeof facilityDoc.email === 'string' ? facilityDoc.email : null,
    openingHours: facilityDoc.openingHours ?? null,
    address: facilityDoc.address ?? null,
  });
}

function shapeStaffProfileResponse(staffUser, facilityDoc) {
  if (!staffUser || typeof staffUser !== 'object') return null;
  const facility = shapeStaffFacilitySummary(facilityDoc);
  const name = typeof staffUser.name === 'string' && staffUser.name.trim().length
    ? staffUser.name.trim()
    : extractUserName(staffUser);
  return cleanObject({
    id: normalizeIdString(staffUser._id),
    _id: normalizeIdString(staffUser._id),
    name,
    email: typeof staffUser.email === 'string' ? staffUser.email : null,
    phone: typeof staffUser.phone === 'string' ? staffUser.phone : null,
    role: typeof staffUser.role === 'string' ? staffUser.role : 'staff',
    facilityId: normalizeIdString(staffUser.facilityId),
    facility: facility ?? undefined,
    createdAt: staffUser.createdAt ?? null,
    updatedAt: staffUser.updatedAt ?? null,
    syntheticEmail: staffUser.syntheticEmail === true,
  });
}

async function getDecoratedBookings(match, { sort = { start: -1, _id: -1 }, limit } = {}) {
  if (!db) return [];
  const pipeline = [{ $match: match }];

  pipeline.push(
    { $lookup: { from: 'facilities', localField: 'facilityId', foreignField: '_id', as: 'facility' } },
    { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
    { $lookup: { from: 'courts', localField: 'courtId', foreignField: '_id', as: 'court' } },
    { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
    { $lookup: { from: 'sports', localField: 'sportId', foreignField: '_id', as: 'sport' } },
    { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
  );

  pipeline.push({
    $project: {
      _id: 1,
      customerId: 1,
      facilityId: 1,
      sportId: 1,
      courtId: 1,
      matchRequestId: 1,
      start: 1,
      end: 1,
      status: 1,
      currency: 1,
      total: 1,
      pricingSnapshot: 1,
      participants: 1,
      voucherId: 1,
      createdAt: 1,
      updatedAt: 1,
      facilityName: '$facility.name',
      courtName: '$court.name',
      sportName: '$sport.name',
    },
  });

  if (sort) pipeline.push({ $sort: sort });
  if (limit && Number.isInteger(limit) && limit > 0) pipeline.push({ $limit: limit });

  const docs = await db.collection('bookings').aggregate(pipeline).toArray();
  return docs.map((doc) => normalizeBookingForResponse(doc));
}

async function checkCourtAvailability({ courtId, start, end, excludeBookingId = null }) {
  const courtObjectId = coerceObjectId(courtId);
  if (!courtObjectId) {
    return { available: false, reason: 'invalid_court' };
  }
  if (!(start instanceof Date) || Number.isNaN(start.valueOf()) || !(end instanceof Date) || Number.isNaN(end.valueOf())) {
    return { available: false, reason: 'invalid_time' };
  }

  const overlapFilter = {
    courtId: courtObjectId,
    start: { $lt: end },
    end: { $gt: start },
  };

  const bookingFilter = {
    ...overlapFilter,
    status: { $in: ['pending', 'confirmed', 'completed'] },
  };

  const excludeId = coerceObjectId(excludeBookingId);
  if (excludeId) {
    bookingFilter._id = { $ne: excludeId };
  }

  const bookingConflict = await db.collection('bookings').findOne(bookingFilter);
  if (bookingConflict) {
    return { available: false, reason: 'booking_conflict', conflict: bookingConflict };
  }

  const maintenanceConflict = await db.collection('maintenance').findOne(overlapFilter);
  if (maintenanceConflict) {
    return { available: false, reason: 'maintenance_conflict', conflict: maintenanceConflict };
  }

  return { available: true };
}

async function createNotifications({
  userIds = [],
  staffFacilityId = null,
  title,
  message,
  data,
  channel,
  priority,
  status,
}) {
  if (!db) return;
  const trimmedTitle = typeof title === 'string' ? title.trim() : '';
  if (!trimmedTitle) return;
  const trimmedMessage = typeof message === 'string' ? message.trim() : '';
  const normalizedChannel = typeof channel === 'string' ? channel.trim().toLowerCase() : '';
  const normalizedPriority = typeof priority === 'string' ? priority.trim().toLowerCase() : '';
  const normalizedStatus = (() => {
    if (typeof status !== 'string') return 'unread';
    const trimmed = status.trim().toLowerCase();
    return trimmed.length ? trimmed : 'unread';
  })();
  const now = new Date();
  const sanitizedData = sanitizeAuditData(data);
  const docs = [];

  const pushDoc = (doc) => {
    const clean = cleanObject({
      ...doc,
      title: trimmedTitle,
      message: trimmedMessage || undefined,
      channel: normalizedChannel || undefined,
      priority: normalizedPriority || undefined,
      data: sanitizedData,
      metadata: sanitizedData,
      status: normalizedStatus,
      createdAt: now,
    });
    if (clean) docs.push(clean);
  };

  for (const userId of userIds) {
    const oid = coerceObjectId(userId);
    if (!oid) continue;
    pushDoc({ recipientId: oid });
  }

  if (staffFacilityId) {
    const facilityCandidates = buildIdCandidates(staffFacilityId);
    if (facilityCandidates.length) {
      const facilityValue = facilityCandidates.find((value) => value instanceof ObjectId)
        ?? facilityCandidates.find((value) => typeof value === 'string' && ObjectId.isValid(value))
        ?? facilityCandidates[0];
      pushDoc({ recipientRole: 'staff', facilityId: facilityValue });
    }
  }

  if (!docs.length) return;
  await db.collection('notifications').insertMany(docs);
}

async function notifyMatchParticipants(matchRequestDoc, { title, message, data }) {
  if (!matchRequestDoc) return;
  const ids = [];
  const creatorId = coerceObjectId(matchRequestDoc.creatorId);
  if (creatorId) ids.push(creatorId);
  if (Array.isArray(matchRequestDoc.participants)) {
    for (const participant of matchRequestDoc.participants) {
      const oid = coerceObjectId(participant);
      if (oid) ids.push(oid);
    }
  }
  const unique = [];
  const seen = new Set();
  for (const oid of ids) {
    const hex = oid.toHexString();
    if (seen.has(hex)) continue;
    seen.add(hex);
    unique.push(oid);
  }
  if (!unique.length) return;
  await createNotifications({ userIds: unique, title, message, data });
}

async function notifyStaffMatchRequest(matchRequestDoc, {
  title,
  message,
  data,
  channel = 'booking',
  priority = 'high',
}) {
  if (!matchRequestDoc) return;
  const facilityId = matchRequestDoc.facilityId ?? matchRequestDoc.facility?.id ?? matchRequestDoc.facility?._id;
  if (!facilityId) return;
  await createNotifications({
    staffFacilityId: facilityId,
    title,
    message,
    data,
    channel,
    priority,
  });
}

async function notifyStaffBookingCreated(bookingDoc) {
  if (!bookingDoc) return;

  const facilityId = coerceObjectId(bookingDoc.facilityId);
  if (!facilityId) return;

  const normalizedStatus = typeof bookingDoc.status === 'string'
    ? bookingDoc.status.trim().toLowerCase()
    : 'pending';

  if (!['pending', 'confirmed'].includes(normalizedStatus)) return;

  const courtId = coerceObjectId(bookingDoc.courtId);
  const sportId = coerceObjectId(bookingDoc.sportId);
  const customerId = coerceObjectId(bookingDoc.customerId);
  const start = coerceDateValue(bookingDoc.start);
  const end = coerceDateValue(bookingDoc.end);

  const [facility, court, sport, customer] = await Promise.all([
    fetchFacilityById(facilityId),
    courtId ? fetchCourtById(courtId) : Promise.resolve(null),
    sportId ? fetchSportById(sportId) : Promise.resolve(null),
    customerId ? db.collection('users').findOne({ _id: customerId }) : Promise.resolve(null),
  ]);

  const extractCustomerName = () => {
    if (!customer) return null;
    if (typeof customer.name === 'string' && customer.name.trim().length) {
      return customer.name.trim();
    }
    const profile = typeof customer.profile === 'object' && customer.profile !== null
      ? customer.profile
      : null;
    if (profile) {
      if (typeof profile.fullName === 'string' && profile.fullName.trim().length) {
        return profile.fullName.trim();
      }
      if (typeof profile.name === 'string' && profile.name.trim().length) {
        return profile.name.trim();
      }
    }
    return null;
  };

  const customerName = extractCustomerName();

  const formatTimestamp = (value) => {
    if (!(value instanceof Date) || Number.isNaN(value.valueOf())) return null;
    return value.toLocaleString('vi-VN', { hour12: false });
  };

  let timeRange = null;
  const formattedStart = formatTimestamp(start);
  const formattedEnd = formatTimestamp(end);
  if (formattedStart && formattedEnd) {
    timeRange = `${formattedStart} - ${formattedEnd}`;
  } else if (formattedStart) {
    timeRange = formattedStart;
  }

  const messageSegments = [];
  if (customerName) messageSegments.push(`Khách ${customerName}`);
  if (sport?.name) messageSegments.push(`Môn ${sport.name}`);
  if (court?.name) messageSegments.push(`Sân ${court.name}`);
  if (facility?.name) messageSegments.push(`Tại ${facility.name}`);
  if (timeRange) messageSegments.push(timeRange);
  const message = messageSegments.join(' | ');

  const metadata = cleanObject({
    eventType: 'customer_booking_created',
    bookingId: bookingDoc._id ?? undefined,
    status: normalizedStatus,
    facilityId,
    facilityName: facility?.name,
    courtId: courtId ?? undefined,
    courtName: court?.name,
    sportId: sportId ?? undefined,
    sportName: sport?.name,
    customerId: customerId ?? undefined,
    customerName: customerName ?? undefined,
    start: start ?? undefined,
    end: end ?? undefined,
  });

  await createNotifications({
    staffFacilityId: facilityId,
    title: normalizedStatus === 'pending'
      ? 'Đặt sân mới đang chờ xử lý'
      : 'Đã tạo đặt sân mới',
    message: message || 'Có đặt sân mới từ khách hàng.',
    channel: 'booking',
    priority: normalizedStatus === 'pending' ? 'high' : 'medium',
    data: metadata,
  });
}

async function notifyStaffBookingCancelled(bookingDoc, { cancelledBy = 'customer' } = {}) {
  if (!bookingDoc) return;

  const facilityId = coerceObjectId(bookingDoc.facilityId);
  if (!facilityId && cancelledBy !== 'customer') return;

  const courtId = coerceObjectId(bookingDoc.courtId);
  const sportId = coerceObjectId(bookingDoc.sportId);
  const customerId = coerceObjectId(bookingDoc.customerId);
  const start = coerceDateValue(bookingDoc.start);
  const end = coerceDateValue(bookingDoc.end);

  const [facility, court, sport, customer] = await Promise.all([
    facilityId ? fetchFacilityById(facilityId) : Promise.resolve(null),
    courtId ? fetchCourtById(courtId) : Promise.resolve(null),
    sportId ? fetchSportById(sportId) : Promise.resolve(null),
    customerId ? db.collection('users').findOne({ _id: customerId }) : Promise.resolve(null),
  ]);

  const customerName = (() => {
    if (!customer) return null;
    if (typeof customer.name === 'string' && customer.name.trim().length) {
      return customer.name.trim();
    }
    const profile = typeof customer.profile === 'object' && customer.profile !== null
      ? customer.profile
      : null;
    if (profile) {
      if (typeof profile.fullName === 'string' && profile.fullName.trim().length) {
        return profile.fullName.trim();
      }
      if (typeof profile.name === 'string' && profile.name.trim().length) {
        return profile.name.trim();
      }
    }
    return null;
  })();

  const formattedStart = start instanceof Date && !Number.isNaN(start.valueOf())
    ? start.toLocaleString('vi-VN', { hour12: false })
    : null;
  const formattedEnd = end instanceof Date && !Number.isNaN(end.valueOf())
    ? end.toLocaleString('vi-VN', { hour12: false })
    : null;

  const segments = [];
  if (customerName) segments.push(`Khách ${customerName}`);
  if (sport?.name) segments.push(`Môn ${sport.name}`);
  if (court?.name) segments.push(`Sân ${court.name}`);
  if (facility?.name) segments.push(`Tại ${facility.name}`);
  if (formattedStart && formattedEnd) {
    segments.push(`${formattedStart} - ${formattedEnd}`);
  } else if (formattedStart) {
    segments.push(formattedStart);
  }

  const message = segments.join(' | ');

  const metadata = cleanObject({
    eventType: 'customer_booking_cancelled',
    bookingId: bookingDoc._id ?? undefined,
    facilityId: facilityId ?? bookingDoc.facilityId ?? undefined,
    facilityName: facility?.name,
    courtId: courtId ?? undefined,
    courtName: court?.name,
    sportId: sportId ?? undefined,
    sportName: sport?.name,
    customerId: customerId ?? undefined,
    customerName: customerName ?? undefined,
    start: start ?? undefined,
    end: end ?? undefined,
    cancelledBy,
  });

  await createNotifications({
    staffFacilityId: facilityId ?? bookingDoc.facilityId,
    title: 'Khách hàng đã huỷ đặt sân',
    message: message || 'Một lịch đặt sân đã bị huỷ bởi khách hàng.',
    channel: 'booking',
    priority: 'high',
    data: metadata,
  });
}

const systemAuditRequest = {
  appUser: { _id: SYSTEM_ACTOR_ID },
  user: { sub: SYSTEM_ACTOR_ID.toHexString(), role: 'system' },
  ip: 'system-auto-cancel',
  get: () => '',
};

async function autoCancelStaleBookings() {
  if (!db) return;
  if (!AUTO_CANCEL_PENDING_MINUTES || AUTO_CANCEL_PENDING_MINUTES <= 0) return;

  const now = new Date();
  const cutoff = new Date(now.getTime() - AUTO_CANCEL_PENDING_MINUTES * 60 * 1000);
  const staleBookings = await db.collection('bookings')
    .find({ status: 'pending', start: { $lte: cutoff } })
    .limit(100)
    .toArray();

  if (!staleBookings.length) return;

  for (const booking of staleBookings) {
    try {
      const bookingId = coerceObjectId(booking._id);
      if (!bookingId) continue;
      const cancelTime = new Date();
      const update = {
        status: 'cancelled',
        cancelledAt: cancelTime,
        cancelledBy: SYSTEM_ACTOR_ID,
        cancelledByRole: 'system',
        cancelledByUserId: null,
        cancelReasonCode: 'auto_pending_timeout',
        cancelReasonText: 'Tự động hủy do quá thời gian chờ duyệt',
        cancelledReason: 'pending_timeout',
        updatedAt: cancelTime,
      };

      const result = await db.collection('bookings').findOneAndUpdate(
        { _id: bookingId, status: 'pending' },
        { $set: update },
        { returnDocument: ReturnDocument.AFTER },
      );

      const updatedBooking = result.value;
      if (!updatedBooking) continue;

      await recordAudit(systemAuditRequest, {
        actorId: SYSTEM_ACTOR_ID,
        action: 'booking.auto-cancel',
        resource: 'booking',
        resourceId: bookingId,
        changes: { status: 'cancelled', cancelledReason: 'pending_timeout', cancelReasonCode: 'auto_pending_timeout' },
      });

      await syncMatchRequestBooking(updatedBooking, { status: 'cancelled', cancelReasonCode: 'auto_pending_timeout', cancelledByRole: 'system' });

      try {
        await voidBookingInvoice(updatedBooking, { reason: 'system_auto_timeout' });
      } catch (invoiceError) {
        console.error('autoCancel: failed to void invoice', invoiceError);
      }

      try {
        await notifyStaffBookingCancelled(updatedBooking, { cancelledBy: 'system_auto_timeout' });
      } catch (notificationError) {
        console.error('autoCancel: failed to notify staff', notificationError);
      }

      const customerId = coerceObjectId(updatedBooking.customerId);
      if (customerId) {
        try {
          await createNotifications({
            userIds: [customerId],
            title: 'Đặt sân đã bị huỷ tự động',
            message: 'Lịch đặt sân chờ xác nhận quá 10 phút nên đã bị huỷ.',
            data: {
              bookingId: bookingId,
              reason: 'pending_timeout',
              start: updatedBooking.start,
              facilityId: updatedBooking.facilityId,
            },
            channel: 'booking',
            priority: 'high',
          });
        } catch (custNotifyError) {
          console.error('autoCancel: failed to notify customer', custNotifyError);
        }
      }
    } catch (err) {
      console.error('autoCancel: failed to process booking', err);
    }
  }
}

async function notifyStaffPaymentReceived({ bookingDoc, invoiceDoc, paymentDoc, actorRole = 'customer' }) {
  if (!bookingDoc || !paymentDoc) return;

  const facilityId = coerceObjectId(bookingDoc.facilityId);
  if (!facilityId) return;

  const courtId = coerceObjectId(bookingDoc.courtId);
  const sportId = coerceObjectId(bookingDoc.sportId);
  const customerId = coerceObjectId(bookingDoc.customerId);

  const [facility, court, sport, customer] = await Promise.all([
    fetchFacilityById(facilityId),
    courtId ? fetchCourtById(courtId) : Promise.resolve(null),
    sportId ? fetchSportById(sportId) : Promise.resolve(null),
    customerId ? db.collection('users').findOne({ _id: customerId }) : Promise.resolve(null),
  ]);

  const customerName = (() => {
    if (!customer) return null;
    if (typeof customer.name === 'string' && customer.name.trim().length) {
      return customer.name.trim();
    }
    const profile = typeof customer.profile === 'object' && customer.profile !== null
      ? customer.profile
      : null;
    if (profile) {
      if (typeof profile.fullName === 'string' && profile.fullName.trim().length) {
        return profile.fullName.trim();
      }
      if (typeof profile.name === 'string' && profile.name.trim().length) {
        return profile.name.trim();
      }
    }
    return null;
  })();

  const amount = Number.parseFloat(String(paymentDoc.amount ?? 0)) || 0;
  const currency = typeof paymentDoc.currency === 'string' && paymentDoc.currency.trim().length
    ? paymentDoc.currency.trim().toUpperCase()
    : (typeof invoiceDoc?.currency === 'string' && invoiceDoc.currency.trim().length
      ? invoiceDoc.currency.trim().toUpperCase()
      : (typeof bookingDoc.currency === 'string' && bookingDoc.currency.trim().length
        ? bookingDoc.currency.trim().toUpperCase()
        : 'VND'));

  const formatMoney = () => {
    try {
      return new Intl.NumberFormat('vi-VN', { style: 'currency', currency }).format(amount);
    } catch (_) {
      return `${amount.toLocaleString('vi-VN')} ${currency}`;
    }
  };

  const segments = [];
  if (customerName) segments.push(`Khách ${customerName}`);
  if (facility?.name) segments.push(`Tại ${facility.name}`);
  if (court?.name) segments.push(`Sân ${court.name}`);
  if (sport?.name) segments.push(`Môn ${sport.name}`);
  if (amount > 0) segments.push(`Số tiền ${formatMoney()}`);

  const message = segments.join(' | ');

  const metadata = cleanObject({
    eventType: 'customer_payment_received',
    bookingId: bookingDoc._id ?? undefined,
    invoiceId: invoiceDoc?._id ?? invoiceDoc?.id ?? undefined,
    paymentId: paymentDoc._id ?? undefined,
    facilityId,
    facilityName: facility?.name,
    courtId: courtId ?? undefined,
    courtName: court?.name,
    sportId: sportId ?? undefined,
    sportName: sport?.name,
    customerId: customerId ?? undefined,
    customerName: customerName ?? undefined,
    amount,
    currency,
    actorRole,
  });

  await createNotifications({
    staffFacilityId: facilityId,
    title: 'Khách hàng đã thanh toán',
    message: message || 'Đã ghi nhận một khoản thanh toán mới từ khách hàng.',
    channel: 'finance',
    priority: amount >= 500000 ? 'high' : 'medium',
    data: metadata,
  });
}

function buildStaffNotificationClauses(staffUser) {
  if (!staffUser) return { orClauses: [], facilityCandidates: [] };
  const facilityCandidates = buildIdCandidates(staffUser.facilityId);
  const recipientCandidates = buildIdCandidates(staffUser._id);
  const orClauses = [];

  if (recipientCandidates.length > 1) {
    const objectIdCandidates = recipientCandidates.filter((item) => item instanceof ObjectId);
    if (objectIdCandidates.length) {
      orClauses.push({ recipientId: { $in: objectIdCandidates } });
    }
    const stringCandidates = recipientCandidates.filter((item) => typeof item === 'string');
    if (stringCandidates.length) {
      orClauses.push({ recipientId: { $in: stringCandidates } });
    }
  } else if (recipientCandidates.length === 1) {
    orClauses.push({ recipientId: recipientCandidates[0] });
  } else if (staffUser._id) {
    orClauses.push({ recipientId: staffUser._id });
  }

  if (facilityCandidates.length) {
    orClauses.push({
      recipientRole: 'staff',
      facilityId: facilityCandidates.length === 1
        ? facilityCandidates[0]
        : { $in: facilityCandidates },
    });
  } else {
    orClauses.push({ recipientRole: 'staff', facilityId: { $exists: false } });
  }
  return { orClauses, facilityCandidates };
}

function notificationMatchesStaff(notificationDoc, staffUser) {
  if (!notificationDoc || !staffUser) return false;

  const staffIdSet = buildComparableIdSet(staffUser._id);
  if (notificationDoc.recipientId) {
    const recipientSet = buildComparableIdSet(notificationDoc.recipientId);
    for (const id of recipientSet) {
      if (staffIdSet.has(id)) return true;
    }
  }

  if (notificationDoc.recipientRole === 'staff') {
    const notifFacilitySet = buildComparableIdSet(notificationDoc.facilityId);
    if (notifFacilitySet.size === 0) return true;
    const staffFacilitySet = buildComparableIdSet(staffUser.facilityId);
    for (const id of notifFacilitySet) {
      if (staffFacilitySet.has(id)) return true;
    }
  }

  return false;
}

async function ensureMatchRequestBooking(matchRequestDoc, { req } = {}) {
  if (!matchRequestDoc) return matchRequestDoc;
  const matchRequestId = coerceObjectId(matchRequestDoc._id);
  if (!matchRequestId) return matchRequestDoc;

  const existingBookingId = coerceObjectId(matchRequestDoc.matchedBookingId);
  if (existingBookingId) {
    const booking = await db.collection('bookings').findOne({ _id: existingBookingId });
    if (booking) {
      const bookingStatus = booking.status ?? matchRequestDoc.bookingStatus ?? 'pending';
      const statusUpdate = {
        bookingStatus,
        status: bookingStatus === 'cancelled' ? 'cancelled' : 'matched',
        updatedAt: new Date(),
      };
      await db.collection('match_requests').updateOne({ _id: matchRequestId }, { $set: statusUpdate });
      return db.collection('match_requests').findOne({ _id: matchRequestId }) || matchRequestDoc;
    }
  }

  const start = matchRequestDoc.desiredStart instanceof Date
    ? matchRequestDoc.desiredStart
    : (matchRequestDoc.desiredStart ? new Date(matchRequestDoc.desiredStart) : null);
  const end = matchRequestDoc.desiredEnd instanceof Date
    ? matchRequestDoc.desiredEnd
    : (matchRequestDoc.desiredEnd ? new Date(matchRequestDoc.desiredEnd) : null);

  if (!(start instanceof Date && !Number.isNaN(start.valueOf())) || !(end instanceof Date && !Number.isNaN(end.valueOf()))) {
    return matchRequestDoc;
  }

  const facilityId = coerceObjectId(matchRequestDoc.facilityId);
  const courtId = coerceObjectId(matchRequestDoc.courtId);
  const sportId = coerceObjectId(matchRequestDoc.sportId);
  if (!facilityId || !courtId || !sportId) {
    return matchRequestDoc;
  }

  const availability = await checkCourtAvailability({ courtId, start, end });
  if (!availability.available) {
    await db.collection('match_requests').updateOne(
      { _id: matchRequestId },
      { $set: { status: 'open', bookingStatus: 'conflict', updatedAt: new Date() } },
    );
    const reopened = await db.collection('match_requests').findOne({ _id: matchRequestId });
    await notifyMatchParticipants(reopened || matchRequestDoc, {
      title: 'Không thể đặt sân tự động',
      message: 'Khung giờ đã bị trùng với lịch khác. Vui lòng chọn thời gian mới.',
      data: { matchRequestId: matchRequestId, reason: availability.reason },
    });
    return reopened || matchRequestDoc;
  }

  const participantIds = [];
  if (Array.isArray(matchRequestDoc.participants)) {
    for (const participant of matchRequestDoc.participants) {
      const oid = coerceObjectId(participant);
      if (oid) participantIds.push(oid);
    }
  }
  const creatorId = coerceObjectId(matchRequestDoc.creatorId);
  if (creatorId) participantIds.push(creatorId);

  const uniqueParticipants = [];
  const seen = new Set();
  for (const oid of participantIds) {
    const hex = oid.toHexString();
    if (seen.has(hex)) continue;
    seen.add(hex);
    uniqueParticipants.push(oid);
  }

  const bookingCustomerId = creatorId ?? uniqueParticipants[0];
  if (!bookingCustomerId) {
    return matchRequestDoc;
  }

  const bookingUser = await db.collection('users').findOne({ _id: bookingCustomerId });
  const pricing = await quotePrice({
    db,
    facilityId: facilityId.toHexString(),
    sportId: sportId.toHexString(),
    courtId: courtId.toHexString(),
    start,
    end,
    currency: 'VND',
    user: bookingUser,
  });

  const bookingDoc = {
    customerId: bookingCustomerId,
    facilityId,
    courtId,
    sportId,
    matchRequestId,
    start,
    end,
    status: 'pending',
    participants: uniqueParticipants,
    currency: pricing?.currency || 'VND',
    pricingSnapshot: pricing,
    createdAt: new Date(),
    createdBy: bookingCustomerId,
  };

  const insert = await db.collection('bookings').insertOne(bookingDoc);
  const bookingId = insert.insertedId;

  const auditContext = (req && typeof req.get === 'function')
    ? req
    : {
        user: { sub: bookingCustomerId },
        ip: req?.ip ?? 'system',
        get: () => '',
      };

  await recordAudit(auditContext, {
    actorId: bookingCustomerId,
    action: 'match_request.auto-booking',
    resource: 'match_request',
    resourceId: matchRequestId,
    changes: { bookingId, participantCount: uniqueParticipants.length },
  });

  await db.collection('match_requests').updateOne(
    { _id: matchRequestId },
    {
      $set: {
        matchedBookingId: bookingId,
        bookingStatus: 'pending',
        status: 'matched',
        updatedAt: new Date(),
      },
    },
  );

  const refreshed = await db.collection('match_requests').findOne({ _id: matchRequestId });
  const sport = await fetchSportById(sportId);
  const facility = await fetchFacilityById(facilityId);
  const court = await fetchCourtById(courtId);

  const scheduleData = {
    matchRequestId: matchRequestId,
    bookingId,
    status: 'pending',
    start,
    end,
    facilityId,
    courtId,
    sportId,
  };

  const timeRange = `${start.toLocaleString('vi-VN', { hour12: false })} - ${end.toLocaleString('vi-VN', { hour12: false })}`;
  const messageSegments = [];
  if (sport?.name) messageSegments.push(`Môn ${sport.name}`);
  if (facility?.name) messageSegments.push(`tại ${facility.name}`);
  if (court?.name) messageSegments.push(`sân ${court.name}`);
  messageSegments.push(timeRange);
  const composedMessage = messageSegments.join(' | ');

  await notifyMatchParticipants(refreshed, {
    title: 'Đã tạo đặt sân chờ xác nhận',
    message: composedMessage,
    data: scheduleData,
  });
  await notifyStaffMatchRequest(refreshed, {
    title: 'Có yêu cầu đặt sân chờ xác nhận',
    message: composedMessage,
    data: scheduleData,
  });

  return refreshed || matchRequestDoc;
}

async function syncMatchRequestBooking(updatedBooking, { status, cancelReasonCode, cancelledByRole } = {}) {
  if (!updatedBooking?.matchRequestId) return;
  const matchRequestId = coerceObjectId(updatedBooking.matchRequestId);
  if (!matchRequestId) return;

  const matchRequest = await db.collection('match_requests').findOne({ _id: matchRequestId });
  if (!matchRequest) return;

  const normalizedStatus = status || updatedBooking.status || 'pending';
  const statusUpdate = {
    bookingStatus: normalizedStatus,
    updatedAt: new Date(),
  };
  if (normalizedStatus === 'cancelled') {
    statusUpdate.status = 'cancelled';
    statusUpdate.cancelledAt = statusUpdate.updatedAt;
    // Propagate cancellation metadata from booking if provided
    if (cancelReasonCode) {
      statusUpdate.cancelReasonCode = cancelReasonCode;
    }
    if (cancelledByRole) {
      statusUpdate.cancelledByRole = cancelledByRole;
    }
  } else if (normalizedStatus === 'pending' || normalizedStatus === 'confirmed' || normalizedStatus === 'completed') {
    statusUpdate.status = 'matched';
  }

  await db.collection('match_requests').updateOne({ _id: matchRequestId }, { $set: statusUpdate });
  const refreshed = await db.collection('match_requests').findOne({ _id: matchRequestId });

  if (!refreshed) return;

  const sport = await fetchSportById(updatedBooking.sportId ?? refreshed.sportId);
  const facility = await fetchFacilityById(updatedBooking.facilityId ?? refreshed.facilityId);
  const court = await fetchCourtById(updatedBooking.courtId ?? refreshed.courtId);

  const scheduleData = {
    matchRequestId,
    bookingId: updatedBooking._id,
    status: normalizedStatus,
    start: updatedBooking.start ?? refreshed.desiredStart,
    end: updatedBooking.end ?? refreshed.desiredEnd,
    facilityId: updatedBooking.facilityId ?? refreshed.facilityId,
    courtId: updatedBooking.courtId ?? refreshed.courtId,
    sportId: updatedBooking.sportId ?? refreshed.sportId,
  };

  const start = updatedBooking.start instanceof Date ? updatedBooking.start : (updatedBooking.start ? new Date(updatedBooking.start) : null);
  const end = updatedBooking.end instanceof Date ? updatedBooking.end : (updatedBooking.end ? new Date(updatedBooking.end) : null);
  const timeRange = (start && end)
    ? `${start.toLocaleString('vi-VN', { hour12: false })} - ${end.toLocaleString('vi-VN', { hour12: false })}`
    : null;

  const segments = [];
  if (sport?.name) segments.push(`Môn ${sport.name}`);
  if (facility?.name) segments.push(`tại ${facility.name}`);
  if (court?.name) segments.push(`sân ${court.name}`);
  if (timeRange) segments.push(timeRange);
  const baseMessage = segments.join(' | ');

  let title;
  let message;
  if (normalizedStatus === 'confirmed') {
    title = 'Lịch thi đấu đã được xác nhận';
    message = baseMessage || 'Nhân viên đã xác nhận lịch thi đấu của bạn.';
  } else if (normalizedStatus === 'cancelled') {
    title = 'Lịch thi đấu đã bị huỷ';
    message = baseMessage || 'Lịch thi đấu từ lời mời đã bị huỷ.';
  } else if (normalizedStatus === 'completed') {
    title = 'Lịch thi đấu đã hoàn tất';
    message = baseMessage || 'Lịch thi đấu của bạn đã hoàn tất.';
  } else {
    return;
  }


async function cancelOverlappingMatchRequests(bookingDoc) {
  if (!bookingDoc) return;
  const courtId = coerceObjectId(bookingDoc.courtId);
  const bookingStart = coerceDateValue(bookingDoc.start);
  const bookingEnd = coerceDateValue(bookingDoc.end);
  if (!courtId || !bookingStart || !bookingEnd) return;

  const linkedMatchRequestId = coerceObjectId(bookingDoc.matchRequestId);
  const conflictFilter = {
    courtId,
    status: 'open',
    desiredStart: { $lt: bookingEnd },
    desiredEnd: { $gt: bookingStart },
  };
  if (linkedMatchRequestId) conflictFilter._id = { $ne: linkedMatchRequestId };

  const overlappingRequests = await db.collection('match_requests').find(conflictFilter).toArray();
  if (!overlappingRequests.length) return;

  const requestIds = overlappingRequests
    .map((doc) => coerceObjectId(doc._id))
    .filter((oid) => oid);
  if (!requestIds.length) return;

  const now = new Date();
  const conflictBookingId = coerceObjectId(bookingDoc._id);
  const updateFields = {
    status: 'cancelled',
    bookingStatus: 'cancelled',
    cancelledReason: 'auto_conflict',
    cancelledAt: now,
    cancelledByRole: 'system',
    cancelledByUserId: null,
    cancelReasonCode: 'overlapped_booking',
    cancelReasonText: 'Hủy do sân đã được đặt trùng khung giờ',
    updatedAt: now,
  };
  if (conflictBookingId) updateFields.conflictBookingId = conflictBookingId;

  await db.collection('match_requests').updateMany(
    { _id: { $in: requestIds } },
    { $set: updateFields },
  );

  const sport = await fetchSportById(bookingDoc.sportId);
  const facility = await fetchFacilityById(bookingDoc.facilityId);
  const court = await fetchCourtById(bookingDoc.courtId);

  for (const request of overlappingRequests) {
    const refreshed = await db.collection('match_requests').findOne({ _id: request._id }) || request;
    const desiredStart = coerceDateValue(refreshed.desiredStart);
    const desiredEnd = coerceDateValue(refreshed.desiredEnd);
    const timeRange = desiredStart && desiredEnd
      ? `${desiredStart.toLocaleString('vi-VN', { hour12: false })} - ${desiredEnd.toLocaleString('vi-VN', { hour12: false })}`
      : null;

    const segments = [];
    if (sport?.name) segments.push(`Môn ${sport.name}`);
    if (facility?.name) segments.push(`tại ${facility.name}`);
    if (court?.name) segments.push(`sân ${court.name}`);
    if (timeRange) segments.push(timeRange);
    const baseMessage = segments.join(' | ') || 'Khung giờ đã được đặt bởi lịch khác.';

    const dataPayload = {
      matchRequestId: refreshed._id,
      reason: 'court_conflict',
    };
    if (conflictBookingId) dataPayload.bookingId = conflictBookingId;

    await notifyMatchParticipants(refreshed, {
      title: 'Lời mời thi đấu bị huỷ do trùng lịch',
      message: `${baseMessage}. Khung giờ này đã có đặt sân khác.`,
      data: dataPayload,
    });

    await notifyStaffMatchRequest(refreshed, {
      title: 'Lời mời thi đấu bị huỷ tự động',
      message: `${baseMessage}. Hệ thống đã huỷ vì có đặt sân mới.`,
      data: dataPayload,
    });
  }
}
  await notifyMatchParticipants(refreshed, {
    title,
    message,
    data: scheduleData,
  });
}

async function recordAudit(req, entry = {}) {
  try {
    if (!db) return;
    const actorSource = entry.actorId
      ?? getAppUserObjectId(req)
      ?? req.appUser?._id
      ?? req.appUser?.id
      ?? req.firebaseUser?.uid
      ?? req.user?.sub
      ?? entry.actor?.id;
    let actorId;
    if (actorSource && ObjectId.isValid(String(actorSource))) {
      actorId = new ObjectId(String(actorSource));
    }
    if (!actorId) {
      // Schema currently requires actorId. Skip logging if none supplied.
      return;
    }

    const target = cleanObject({
      resource: entry.resource || req.path,
      id: entry.resourceId ? String(entry.resourceId) : undefined,
    });

    const doc = cleanObject({
      actorId,
      action: entry.action || req.method.toLowerCase(),
      target,
      changes: sanitizeAuditData(entry.changes),
      message: entry.message,
      ip: req.ip,
      userAgent: req.get('user-agent'),
      at: entry.at instanceof Date ? entry.at : new Date(),
    });

    if (!doc) return;
    await db.collection('audit_logs').insertOne(doc);
  } catch (err) {
    console.error('[audit] Failed to record audit log', err);
  }
}

// --- Auth ---
app.post('/api/auth/register', async (req, res, next) => {
  try {
    const { email, password, name, gender, dateOfBirth, mainSportId } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'email and password required' });
    if (typeof email !== 'string' || typeof password !== 'string') return res.status(400).json({ error: 'invalid payload' });
    if (password.length < 6) return res.status(400).json({ error: 'password must be at least 6 characters' });

    const existing = await db.collection('users').findOne({ email: email.toLowerCase() });
    if (existing) return res.status(409).json({ error: 'Email already registered' });

    const genderResult = normalizeGenderInput(gender);
    if (genderResult.provided && genderResult.error) {
      return res.status(400).json({ error: 'Giới tính không hợp lệ' });
    }

    const dobResult = normalizeDateInput(dateOfBirth);
    if (dobResult.provided && dobResult.error) {
      return res.status(400).json({ error: 'Ngày sinh không hợp lệ' });
    }

    const mainSportResult = normalizeObjectIdInput(mainSportId);
    if (mainSportResult.provided && mainSportResult.error) {
      return res.status(400).json({ error: 'mainSportId không hợp lệ' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const userDoc = {
      email: email.toLowerCase(),
      name: typeof name === 'string' ? name : undefined,
      role: 'customer',
      status: 'active',
      passwordHash,
      createdAt: new Date(),
    };
    if (genderResult.provided && genderResult.value) userDoc.gender = genderResult.value;
    if (dobResult.provided && dobResult.value) userDoc.dateOfBirth = dobResult.value;
    if (mainSportResult.provided && mainSportResult.value) userDoc.mainSportId = mainSportResult.value;
    const r = await db.collection('users').insertOne(userDoc);
    const inserted = await db.collection('users').findOne({ _id: r.insertedId });
    const user = shapeAuthUser(inserted) ?? { _id: r.insertedId, email: userDoc.email, name: userDoc.name, role: userDoc.role, status: userDoc.status };
    const token = jwt.sign({ sub: String(r.insertedId), role: user.role }, JWT_SECRET, { expiresIn: '7d' });
    await recordAudit(req, {
      actorId: r.insertedId,
      action: 'auth.register',
      resource: 'user',
      resourceId: r.insertedId,
      changes: { email: userDoc.email, name: userDoc.name, role: userDoc.role },
    });
    res.status(201).json({ token, user });
  } catch (e) { next(e); }
});

app.post('/api/auth/login', async (req, res, next) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'email and password required' });
    const u = await db.collection('users').findOne({ email: email.toLowerCase() });
    if (!u || !u.passwordHash) return res.status(401).json({ error: 'Invalid email or password' });
    const ok = await bcrypt.compare(password, u.passwordHash);
    if (!ok) return res.status(401).json({ error: 'Invalid email or password' });
    if (u.status && u.status !== 'active') return res.status(403).json({ error: 'Account is not active' });
  const user = shapeAuthUser(u);
  const token = jwt.sign({ sub: String(u._id), role: user.role }, JWT_SECRET, { expiresIn: '7d' });
    await recordAudit(req, {
      actorId: u._id,
      action: 'auth.login',
      resource: 'user',
      resourceId: u._id,
    });
    res.json({ token, user });
  } catch (e) { next(e); }
});

// Sports list (basic)
app.get('/api/sports', async (req, res, next) => {
  try {
    const includeCount = req.query.includeCount === 'true';
    if (!includeCount) {
      const items = await db.collection('sports').find({ active: { $ne: false } }).sort({ name: 1 }).toArray();
      return res.json(items);
    }
    const items = await db.collection('sports').aggregate([
      { $match: { active: { $ne: false } } },
      { $lookup: {
          from: 'courts',
          let: { sid: '$_id' },
          pipeline: [
            { $match: { $expr: { $eq: ['$sportId', '$$sid'] } } },
            { $match: { $or: [ { status: 'active' }, { status: { $exists: false } } ] } },
            { $count: 'count' },
          ],
          as: 'courtStats'
      }},
      { $addFields: { courtCount: { $ifNull: [ { $arrayElemAt: ['$courtStats.count', 0] }, 0 ] } } },
      { $project: { courtStats: 0 } },
      { $sort: { name: 1 } },
    ]).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

// Facilities
app.get('/api/facilities', async (req, res, next) => {
  try {
    const items = await db.collection('facilities').find({ active: { $ne: false } }).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

// Courts by facility (and optional sport)
app.get('/api/facilities/:id/courts', async (req, res, next) => {
  try {
    const filter = { facilityId: new ObjectId(req.params.id), status: { $ne: 'deleted' } };
    if (req.query.sportId) filter.sportId = new ObjectId(req.query.sportId);
    const items = await db.collection('courts').find(filter).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

// Availability check for a court (avoid conflicts with bookings and maintenance)
app.get('/api/courts/:id/availability', async (req, res, next) => {
  try {
    const { start, end } = req.query;
    if (!start || !end) return res.status(400).json({ error: 'start & end required (ISO date)' });
    const s = new Date(start); const e = new Date(end);
    if (!(s < e)) return res.status(400).json({ error: 'start must be < end' });
    const courtId = new ObjectId(req.params.id);

    const overlapExpr = { $or: [
      { start: { $lt: e }, end: { $gt: s } },
    ]};

    const bookingConflict = await db.collection('bookings').findOne({ courtId, ...overlapExpr, status: { $in: ['pending','confirmed','completed'] } });
    const maintenanceConflict = await db.collection('maintenance').findOne({ courtId, ...overlapExpr });

    const available = !bookingConflict && !maintenanceConflict;
    res.json({ available, bookingConflict: !!bookingConflict, maintenanceConflict: !!maintenanceConflict });
  } catch (e) { next(e); }
});

// Price quote endpoint
app.post('/api/price/quote', async (req, res, next) => {
  try {
    const { facilityId, sportId, courtId, start, end, currency = 'VND', userId } = req.body;
    if (!facilityId || !sportId || !courtId || !start || !end) return res.status(400).json({ error: 'Missing required fields' });
    const s = new Date(start); const e = new Date(end);
    const user = userId ? await db.collection('users').findOne({ _id: new ObjectId(userId) }) : null;
    const quote = await quotePrice({ db, facilityId, sportId, courtId, start: s, end: e, currency, user });
    res.json(quote);
  } catch (e) { next(e); }
});

// Create booking (minimal validation)
app.post('/api/bookings', async (req, res, next) => {
  try {
    const payload = req.body;
    // Basic check: required fields exist
    const required = ['customerId','facilityId','courtId','sportId','start','end','status','pricingSnapshot','currency'];
    for (const k of required) if (!(k in payload)) return res.status(400).json({ error: `Missing ${k}` });

    // Coerce ObjectIds and dates
    const customerId = coerceObjectId(payload.customerId);
    const facilityId = coerceObjectId(payload.facilityId);
    const courtId = coerceObjectId(payload.courtId);
    const sportId = coerceObjectId(payload.sportId);
    if (!customerId) return res.status(400).json({ error: 'Invalid customerId' });
    if (!facilityId) return res.status(400).json({ error: 'Invalid facilityId' });
    if (!courtId) return res.status(400).json({ error: 'Invalid courtId' });
    if (!sportId) return res.status(400).json({ error: 'Invalid sportId' });
    const s = new Date(payload.start);
    const e = new Date(payload.end);
    // Check availability
    const conflict = await db.collection('bookings').findOne({
      courtId,
      $or: [ { start: { $lt: e }, end: { $gt: s } } ],
      status: { $in: ['pending','confirmed','completed'] },
    });
    const maintenance = await db.collection('maintenance').findOne({
      courtId,
      $or: [ { start: { $lt: e }, end: { $gt: s } } ],
    });
    if (conflict || maintenance) return res.status(409).json({ error: 'Court not available for the requested time' });

    // Recompute price on server to trust pricing
    const quote = await quotePrice({
      db,
      facilityId: facilityId.toHexString(),
      sportId: sportId.toHexString(),
      courtId: courtId.toHexString(),
      start: s,
      end: e,
      currency: payload.currency,
      user: await db.collection('users').findOne({ _id: customerId }),
    });

    const voucherRaw = typeof payload.voucherId === 'string' ? payload.voucherId.trim() : '';
    const voucherId = voucherRaw ? coerceObjectId(voucherRaw) : null;
    if (voucherRaw && !voucherId) {
      return res.status(400).json({ error: 'Invalid voucherId' });
    }
    const doc = {
      ...payload,
      customerId,
      facilityId,
      courtId,
      sportId,
      participants: Array.isArray(payload.participants)
        ? payload.participants
            .map((x) => String(x).trim())
            .filter((x) => ObjectId.isValid(x))
            .map((x) => new ObjectId(x))
        : [],
      start: s,
      end: e,
      pricingSnapshot: quote,
      createdAt: payload.createdAt ? new Date(payload.createdAt) : new Date(),
    };
    if (voucherId) {
      doc.voucherId = voucherId;
    } else {
      delete doc.voucherId;
    }

    const r = await db.collection('bookings').insertOne(doc);
    const createdBooking = { _id: r.insertedId, ...doc };

    await recordAudit(req, {
      action: 'booking.create',
      resource: 'booking',
      resourceId: r.insertedId,
      payload: {
        facilityId: payload.facilityId,
        courtId: payload.courtId,
        sportId: payload.sportId,
        customerId: payload.customerId,
        start: payload.start,
        end: payload.end,
        status: payload.status,
      },
    });

    const normalizedStatus = typeof createdBooking.status === 'string'
      ? createdBooking.status.trim().toLowerCase()
      : '';

    try {
      await notifyStaffBookingCreated(createdBooking);
    } catch (notificationError) {
      console.error('Failed to notify staff about new booking', notificationError);
    }

    if (normalizedStatus === 'confirmed') {
      try {
        await ensureBookingInvoice(createdBooking);
      } catch (invoiceError) {
        console.error('Failed to ensure invoice for confirmed booking', invoiceError);
      }
    }

    try {
      await cancelOverlappingMatchRequests(createdBooking);
    } catch (overlapError) {
      console.error('Failed to cancel overlapping match requests', overlapError);
    }

    res.status(201).json(createdBooking);
  } catch (e) { next(e); }
});

// Get bookings by customer
app.get('/api/customers/:id/bookings', async (req, res, next) => {
  try {
    const id = new ObjectId(req.params.id);
    const list = await db.collection('bookings').find({ customerId: id }).sort({ start: -1 }).toArray();
    res.json(list);
  } catch (e) { next(e); }
});

app.get('/api/user/bookings/upcoming', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    const now = new Date();
    const match = {
      $and: [
        { end: { $gte: now } },
        {
          $or: [
            { customerId: userId },
            { participants: userId },
          ],
        },
      ],
    };

    const upcomingBookings = await getDecoratedBookings(match, { sort: { start: 1 } });
    res.json(upcomingBookings);
  } catch (e) { next(e); }
});

app.get('/api/user/bookings', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    let requestedStatus = null;
    if (typeof req.query?.status === 'string' && req.query.status.trim().length) {
      const normalized = req.query.status.trim().toLowerCase();
      if (USER_BOOKING_ALLOWED_STATUSES.has(normalized)) {
        requestedStatus = normalized;
      }
    }

    const match = { customerId: userId };
    if (requestedStatus) match.status = requestedStatus;

    const bookings = await getDecoratedBookings(match, { sort: { start: -1, _id: -1 } });
    res.json(bookings);
  } catch (e) { next(e); }
});

app.put('/api/bookings/:id/cancel', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    const bookingId = coerceObjectId(req.params.id);
    if (!bookingId) return res.status(400).json({ error: 'Invalid booking id' });

    const booking = await db.collection('bookings').findOne({ _id: bookingId });
    if (!booking) return res.status(404).json({ error: 'Booking not found' });

    const belongsToUser = booking.customerId instanceof ObjectId
      ? booking.customerId.equals(userId)
      : String(booking.customerId) === userId.toHexString();
    if (!belongsToUser) return res.status(403).json({ error: 'Không có quyền huỷ đặt sân này' });

    const status = typeof booking.status === 'string' ? booking.status.trim().toLowerCase() : '';
    if (status !== 'pending') {
      return res.status(409).json({ error: 'booking_not_cancellable', message: 'Chỉ có thể huỷ khi đặt sân đang chờ xác nhận.' });
    }

    const now = new Date();
    const update = {
      status: 'cancelled',
      updatedAt: now,
      cancelledAt: now,
      cancelledBy: userId,
      cancelledByRole: 'customer',
      cancelledByUserId: userId,
      cancelReasonCode: 'customer_cancel',
      cancelReasonText: 'Khách hàng hủy đặt sân',
      cancelledReason: 'customer_cancelled',
    };

    const result = await db.collection('bookings').findOneAndUpdate(
      { _id: bookingId },
      { $set: update },
      { returnDocument: 'after' },
    );

    const updatedBooking = result.value ?? { ...booking, ...update };

    await recordAudit(req, {
      actorId: userId,
      action: 'booking.cancel',
      resource: 'booking',
      resourceId: bookingId,
      changes: { status: 'cancelled', cancelledAt: now, cancelReasonCode: 'customer_cancel' },
    });

    await syncMatchRequestBooking(updatedBooking, { status: 'cancelled', cancelReasonCode: 'customer_cancel', cancelledByRole: 'customer' });

    try {
      await voidBookingInvoice(updatedBooking, { reason: 'customer_cancelled' });
    } catch (invoiceError) {
      console.error('Failed to void invoice after customer cancellation', invoiceError);
    }

    try {
      await notifyStaffBookingCancelled(updatedBooking, { cancelledBy: 'customer' });
    } catch (notificationError) {
      console.error('Failed to notify staff about booking cancellation', notificationError);
    }

    const [decorated] = await getDecoratedBookings({ _id: bookingId }, { limit: 1 });
    res.json(decorated ?? normalizeBookingForResponse(updatedBooking));
  } catch (e) { next(e); }
});

// --- Customer billing ---
app.get('/api/user/invoices', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    const pipeline = [
      { $lookup: { from: 'bookings', localField: 'bookingId', foreignField: '_id', as: 'booking' } },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $match: { 'booking.customerId': userId } },
      { $lookup: { from: 'courts', localField: 'booking.courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'facilities', localField: 'booking.facilityId', foreignField: '_id', as: 'facility' } },
      { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
      {
        $project: {
          _id: 1,
          bookingId: '$booking._id',
          amount: '$amount',
          currency: '$currency',
          bookingCurrency: '$booking.currency',
          status: '$status',
          issuedAt: '$issuedAt',
          dueAt: '$dueAt',
          description: '$description',
          bookingStart: '$booking.start',
          bookingEnd: '$booking.end',
          courtName: '$court.name',
          facilityName: '$facility.name',
        },
      },
      { $sort: { issuedAt: -1, _id: -1 } },
    ];

    const docs = await db.collection('invoices').aggregate(pipeline).toArray();

    const invoices = docs.map((doc) => {
      const amountValue = typeof doc.amount === 'number'
        ? doc.amount
        : Number.parseFloat(String(doc.amount ?? 0)) || 0;
      const currencyValue = (typeof doc.currency === 'string' && doc.currency.trim().length)
        ? doc.currency.trim()
        : (typeof doc.bookingCurrency === 'string' && doc.bookingCurrency.trim().length
          ? doc.bookingCurrency.trim()
          : 'VND');

      const statusValue = (typeof doc.status === 'string' && doc.status.trim().length)
        ? doc.status.trim()
        : 'unpaid';
      const issuedAtValue = doc.issuedAt instanceof Date
        ? doc.issuedAt
        : (doc.bookingStart instanceof Date ? doc.bookingStart : null);
      const dueAtValue = doc.dueAt instanceof Date
        ? doc.dueAt
        : (doc.bookingEnd instanceof Date ? doc.bookingEnd : null);
      const descriptionValue = (typeof doc.description === 'string' && doc.description.trim().length)
        ? doc.description.trim()
        : null;

      return {
        _id: doc._id,
        bookingId: doc.bookingId,
        amount: amountValue,
        currency: currencyValue,
        status: statusValue,
        issuedAt: issuedAtValue,
        dueAt: dueAtValue,
        description: descriptionValue,
        courtName: doc.courtName ?? null,
        facilityName: doc.facilityName ?? null,
      };
    });

    res.json(invoices);
  } catch (e) { next(e); }
});

app.get('/api/user/payments', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    const { invoiceId } = req.query || {};
    const pipeline = [];
    if (invoiceId !== undefined) {
      const candidates = buildIdCandidates(invoiceId);
      if (candidates.length) {
        pipeline.push({ $match: { invoiceId: { $in: candidates } } });
      } else {
        return res.json([]);
      }
    }

    pipeline.push(
      { $lookup: { from: 'invoices', localField: 'invoiceId', foreignField: '_id', as: 'invoice' } },
      { $unwind: { path: '$invoice', preserveNullAndEmptyArrays: false } },
      { $lookup: { from: 'bookings', localField: 'invoice.bookingId', foreignField: '_id', as: 'booking' } },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $match: { 'booking.customerId': userId } },
      {
        $project: {
          _id: 1,
          invoiceId: '$invoice._id',
          amount: '$amount',
          currency: '$currency',
          invoiceCurrency: '$invoice.currency',
          status: '$status',
          method: '$method',
          provider: '$provider',
          txnRef: '$txnRef',
          processedAt: '$createdAt',
        },
      },
      { $sort: { processedAt: -1, _id: -1 } },
    );

    const docs = await db.collection('payments').aggregate(pipeline).toArray();

    const payments = docs.map((doc) => {
      const amountValue = typeof doc.amount === 'number'
        ? doc.amount
        : Number.parseFloat(String(doc.amount ?? 0)) || 0;
      const currencyValue = (typeof doc.currency === 'string' && doc.currency.trim().length)
        ? doc.currency.trim()
        : (typeof doc.invoiceCurrency === 'string' && doc.invoiceCurrency.trim().length
          ? doc.invoiceCurrency.trim()
          : 'VND');
      const statusValue = (typeof doc.status === 'string' && doc.status.trim().length)
        ? doc.status.trim()
        : 'initiated';
      const methodValue = (typeof doc.method === 'string' && doc.method.trim().length)
        ? doc.method.trim()
        : (typeof doc.provider === 'string' && doc.provider.trim().length ? doc.provider.trim() : null);
      const referenceValue = (typeof doc.txnRef === 'string' && doc.txnRef.trim().length)
        ? doc.txnRef.trim()
        : null;
      const processedAtValue = doc.processedAt instanceof Date ? doc.processedAt : null;

      return {
        _id: doc._id,
        invoiceId: doc.invoiceId,
        amount: amountValue,
        currency: currencyValue,
        status: statusValue,
        method: methodValue,
        provider: methodValue ? doc.provider ?? null : (typeof doc.provider === 'string' && doc.provider.trim().length ? doc.provider.trim() : null),
        reference: referenceValue,
        processedAt: processedAtValue,
      };
    });

    res.json(payments);
  } catch (e) { next(e); }
});

app.post('/api/user/invoices/:id/pay', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });

    const invoiceCandidates = buildIdCandidates(req.params.id);
    if (!invoiceCandidates.length) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const invoice = await db.collection('invoices').findOne({ _id: { $in: invoiceCandidates } });
    if (!invoice) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const bookingCandidates = buildIdCandidates(invoice.bookingId);
    const booking = bookingCandidates.length
      ? await db.collection('bookings').findOne({ _id: { $in: bookingCandidates } })
      : null;
    if (!booking || String(booking.customerId ?? '') !== String(userId)) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    if (invoice.status === 'void' || invoice.status === 'refunded') {
      return res.status(400).json({ error: 'Không thể thanh toán hoá đơn này' });
    }

    const invoiceObjectId = invoice._id instanceof ObjectId
      ? invoice._id
      : (ObjectId.isValid(String(invoice._id)) ? new ObjectId(String(invoice._id)) : null);
    if (!invoiceObjectId) {
      return res.status(500).json({ error: 'Hoá đơn không hợp lệ' });
    }
    const invoiceIdString = invoiceObjectId.toHexString();
    const invoiceAmount = Number.parseFloat(String(invoice.amount ?? 0)) || 0;

    const existingPayments = await db.collection('payments')
      .find({ invoiceId: { $in: buildIdCandidates(invoiceObjectId) } })
      .toArray();
    const currentPaid = existingPayments
      .filter((p) => p?.status === 'succeeded')
      .reduce((sum, p) => sum + (Number.parseFloat(String(p.amount ?? 0)) || 0), 0);
    const outstandingBefore = Math.max(0, invoiceAmount - currentPaid);
    if (outstandingBefore <= 0) {
      return res.status(400).json({ error: 'Hoá đơn đã được thanh toán đầy đủ' });
    }

    const body = req.body || {};
    const requestedAmountRaw = body.amount ?? outstandingBefore;
    const requestedAmount = Number.parseFloat(String(requestedAmountRaw));
    if (!Number.isFinite(requestedAmount) || requestedAmount <= 0) {
      return res.status(400).json({ error: 'Số tiền thanh toán không hợp lệ' });
    }
    const amount = Math.min(requestedAmount, outstandingBefore);

    const method = typeof body.method === 'string' && body.method.trim().length
      ? body.method.trim()
      : 'online';
    const provider = typeof body.provider === 'string' && body.provider.trim().length
      ? body.provider.trim()
      : 'user-app';
    const reference = typeof body.txnRef === 'string' && body.txnRef.trim().length
      ? body.txnRef.trim()
      : undefined;
    const processedAt = new Date();

    const paymentDoc = cleanObject({
      invoiceId: invoiceObjectId,
      provider,
      method,
      amount,
      currency: invoice.currency || booking.currency || 'VND',
      status: 'succeeded',
      txnRef: reference,
      createdAt: processedAt,
      meta: cleanObject({
        source: 'user-payment',
        actorId: userId,
      }),
    }) ?? {
      invoiceId: invoiceObjectId,
      provider,
      method,
      amount,
      currency: invoice.currency || booking.currency || 'VND',
      status: 'succeeded',
      createdAt: processedAt,
    };

    const insert = await db.collection('payments').insertOne(paymentDoc);

    const succeededContribution = paymentDoc.status === 'succeeded' ? amount : 0;
    const newTotalPaid = currentPaid + succeededContribution;
    const outstandingAfter = Math.max(0, invoiceAmount - newTotalPaid);
    const nextStatus = outstandingAfter <= 0 ? 'paid' : invoice.status;

    const updateDoc = { $set: { updatedAt: processedAt } };
    const unsetDoc = {};
    if (nextStatus !== invoice.status) {
      updateDoc.$set.status = nextStatus;
      if (nextStatus === 'paid') {
        updateDoc.$set.paidAt = invoice.paidAt instanceof Date ? invoice.paidAt : processedAt;
      } else if (invoice.paidAt) {
        unsetDoc.paidAt = '';
      }
    }
    if (Object.keys(unsetDoc).length) updateDoc.$unset = unsetDoc;
  await db.collection('invoices').updateOne({ _id: invoice._id }, updateDoc);

    await recordAudit(req, {
      actorId: userId,
      action: 'invoice.user-payment',
      resource: 'payment',
      resourceId: insert.insertedId,
      changes: paymentDoc,
    });

    const responsePayment = {
      _id: String(insert.insertedId),
      invoiceId: invoiceIdString,
      amount,
      currency: paymentDoc.currency,
      status: 'succeeded',
      method,
      provider,
      reference,
      processedAt,
    };

    try {
      await notifyStaffPaymentReceived({
        bookingDoc: booking,
        invoiceDoc: invoice,
        paymentDoc,
        actorRole: 'customer',
      });
    } catch (notificationError) {
      console.error('Failed to notify staff about customer payment', notificationError);
    }

    res.status(201).json({
      invoiceId: invoiceIdString,
      status: nextStatus,
      totalPaid: newTotalPaid,
      outstanding: outstandingAfter,
      payment: responsePayment,
    });
  } catch (e) { next(e); }
});

app.get('/api/user/profile', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const user = await db.collection('users').findOne({ _id: userId });
    if (!user) return res.status(404).json({ error: 'Tài khoản không tồn tại' });
    res.json(shapeUserProfile(user));
  } catch (e) { next(e); }
});

app.put('/api/user/profile', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const user = await db.collection('users').findOne({ _id: userId });
    if (!user) return res.status(404).json({ error: 'Tài khoản không tồn tại' });

    const body = req.body || {};
    const $set = {};
    const $unset = {};

    if (body.name !== undefined) {
      const cleanName = typeof body.name === 'string' ? body.name.trim() : '';
      if (cleanName.length) {
        $set.name = cleanName.substring(0, 120);
      } else {
        $unset.name = '';
      }
    }

    if (body.phone !== undefined) {
      const cleanPhone = typeof body.phone === 'string' ? body.phone.trim() : '';
      if (cleanPhone.length) {
        $set.phone = cleanPhone.substring(0, 30);
      } else {
        $unset.phone = '';
      }
    }

    if (body.sportsPreferences !== undefined) {
      const prefsRaw = Array.isArray(body.sportsPreferences) ? body.sportsPreferences : [];
      const prefs = [];
      for (const item of prefsRaw) {
        if (typeof item !== 'string') continue;
        const clean = item.trim();
        if (!clean) continue;
        if (prefs.includes(clean)) continue;
        prefs.push(clean.substring(0, 64));
        if (prefs.length >= 20) break;
      }
      if (prefs.length) {
        $set.sportsPreferences = prefs;
      } else {
        $unset.sportsPreferences = '';
      }
    }

    if (body.gender !== undefined) {
      const genderResult = normalizeGenderInput(body.gender);
      if (genderResult.error) {
        return res.status(400).json({ error: 'Giới tính không hợp lệ' });
      }
      if (genderResult.value) {
        $set.gender = genderResult.value;
      } else {
        $unset.gender = '';
      }
    }

    if (body.dateOfBirth !== undefined) {
      const dobResult = normalizeDateInput(body.dateOfBirth);
      if (dobResult.error) {
        return res.status(400).json({ error: 'Ngày sinh không hợp lệ' });
      }
      if (dobResult.value) {
        $set.dateOfBirth = dobResult.value;
      } else {
        $unset.dateOfBirth = '';
      }
    }

    if (body.mainSportId !== undefined) {
      const sportResult = normalizeObjectIdInput(body.mainSportId);
      if (sportResult.error) {
        return res.status(400).json({ error: 'mainSportId không hợp lệ' });
      }
      if (sportResult.value) {
        $set.mainSportId = sportResult.value;
      } else {
        $unset.mainSportId = '';
      }
    }

    if (!Object.keys($set).length && !Object.keys($unset).length) {
      return res.status(400).json({ error: 'Không có thay đổi nào được gửi lên' });
    }

    $set.updatedAt = new Date();

    const updateDoc = {};
    if (Object.keys($set).length) updateDoc.$set = $set;
    if (Object.keys($unset).length) updateDoc.$unset = $unset;

    await db.collection('users').updateOne({ _id: userId }, updateDoc);
    const updated = await db.collection('users').findOne({ _id: userId });

    await recordAudit(req, {
      actorId: userId,
      action: 'user.profile-update',
      resource: 'user',
      resourceId: userId,
      changes: sanitizeAuditData({ $set, $unset }),
    });

    res.json(shapeUserProfile(updated));
  } catch (e) { next(e); }
});

app.put('/api/user/password', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const user = await db.collection('users').findOne({ _id: userId });
    if (!user) return res.status(404).json({ error: 'Tài khoản không tồn tại' });

    const { currentPassword, newPassword } = req.body || {};
    if (typeof newPassword !== 'string' || newPassword.length < 6) {
      return res.status(400).json({ error: 'Mật khẩu mới phải có ít nhất 6 ký tự' });
    }
    if (typeof currentPassword !== 'string' || !currentPassword.length) {
      return res.status(400).json({ error: 'Vui lòng nhập mật khẩu hiện tại' });
    }

    const currentHash = user.passwordHash;
    if (!currentHash) {
      return res.status(400).json({ error: 'Tài khoản không hỗ trợ đổi mật khẩu' });
    }

    const matches = await bcrypt.compare(currentPassword, currentHash);
    if (!matches) {
      return res.status(403).json({ error: 'Mật khẩu hiện tại không đúng' });
    }
    if (currentPassword === newPassword) {
      return res.status(400).json({ error: 'Mật khẩu mới phải khác mật khẩu hiện tại' });
    }

    const passwordHash = await bcrypt.hash(String(newPassword), 10);
    await db.collection('users').updateOne(
      { _id: userId },
      { $set: { passwordHash, passwordChangedAt: new Date(), updatedAt: new Date() } },
    );

    await recordAudit(req, {
      actorId: userId,
      action: 'user.change-password',
      resource: 'user',
      resourceId: userId,
      message: 'User updated password',
    });

    res.json({ ok: true });
  } catch (e) { next(e); }
});

const MATCH_REQUEST_ALLOWED_VISIBILITIES = new Set(['public','friends','private']);
const MATCH_REQUEST_ALLOWED_STATUSES = new Set(['open','matched','cancelled','expired']);

app.post('/api/match_requests', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const body = req.body || {};
    const sportCandidates = buildIdCandidates(body.sportId);
    if (!sportCandidates.length) {
      return res.status(400).json({ error: 'sportId không hợp lệ' });
    }
    const sport = await db.collection('sports').findOne({ _id: { $in: sportCandidates } });
    if (!sport) {
      return res.status(404).json({ error: 'Môn thể thao không tồn tại' });
    }

    const start = body.desiredStart ? new Date(String(body.desiredStart)) : null;
    const end = body.desiredEnd ? new Date(String(body.desiredEnd)) : null;
    if (!(start instanceof Date && !Number.isNaN(start.valueOf()))) {
      return res.status(400).json({ error: 'Thời gian bắt đầu không hợp lệ' });
    }
    if (!(end instanceof Date && !Number.isNaN(end.valueOf()))) {
      return res.status(400).json({ error: 'Thời gian kết thúc không hợp lệ' });
    }
    if (!(start < end)) {
      return res.status(400).json({ error: 'Thời gian bắt đầu phải trước thời gian kết thúc' });
    }

    let minSkill = undefined;
    let maxSkill = undefined;
    const skillRange = body.skillRange && typeof body.skillRange === 'object' ? body.skillRange : {};
    const rawMin = skillRange.min ?? body.skillMin;
    const rawMax = skillRange.max ?? body.skillMax;
    if (rawMin !== undefined) {
      const parsed = Number.parseInt(String(rawMin), 10);
      if (Number.isNaN(parsed) || parsed < 0) {
        return res.status(400).json({ error: 'Mức kỹ năng tối thiểu không hợp lệ' });
      }
      minSkill = Math.min(parsed, 100);
    }
    if (rawMax !== undefined) {
      const parsed = Number.parseInt(String(rawMax), 10);
      if (Number.isNaN(parsed) || parsed < 0) {
        return res.status(400).json({ error: 'Mức kỹ năng tối đa không hợp lệ' });
      }
      maxSkill = Math.min(parsed, 100);
    }
    if (minSkill !== undefined && maxSkill !== undefined && minSkill > maxSkill) {
      const temp = minSkill;
      minSkill = maxSkill;
      maxSkill = temp;
    }

    const visibilityRaw = typeof body.visibility === 'string' ? body.visibility.trim().toLowerCase() : 'public';
    const visibility = MATCH_REQUEST_ALLOWED_VISIBILITIES.has(visibilityRaw) ? visibilityRaw : 'public';

    let location = undefined;
    if (body.location && typeof body.location === 'object') {
      const loc = body.location;
      if (Array.isArray(loc.coordinates) && loc.type === 'Point' && loc.coordinates.length === 2) {
        const [lng, lat] = loc.coordinates.map((value) => Number.parseFloat(String(value)));
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          location = {
            type: 'Point',
            coordinates: [lng, lat],
          };
        }
      }
    }

    const skillRangeDoc =
      minSkill === undefined && maxSkill === undefined
        ? undefined
        : cleanObject({
            min: minSkill !== undefined ? new Int32(minSkill) : undefined,
            max: maxSkill !== undefined ? new Int32(maxSkill) : undefined,
          });

    let facility = null;
    if (body.facilityId) {
      const facilityCandidates = buildIdCandidates(body.facilityId);
      if (!facilityCandidates.length) {
        return res.status(400).json({ error: 'facilityId không hợp lệ' });
      }
      facility = await db.collection('facilities').findOne({ _id: { $in: facilityCandidates } });
      if (!facility) {
        return res.status(404).json({ error: 'Cơ sở không tồn tại' });
      }
      if (facility.active === false) {
        return res.status(400).json({ error: 'Cơ sở đang tạm ngưng hoạt động' });
      }
    }

    let court = null;
    if (body.courtId) {
      const courtCandidates = buildIdCandidates(body.courtId);
      if (!courtCandidates.length) {
        return res.status(400).json({ error: 'courtId không hợp lệ' });
      }
      court = await db.collection('courts').findOne({ _id: { $in: courtCandidates } });
      if (!court || court.status === 'deleted') {
        return res.status(404).json({ error: 'Sân không tồn tại hoặc đã bị xoá' });
      }
      const courtSportId = coerceObjectId(court.sportId);
      if (courtSportId && !courtSportId.equals(sport._id)) {
        return res.status(400).json({ error: 'Sân không phù hợp với môn thể thao đã chọn' });
      }
    }

    if (!court) {
      return res.status(400).json({ error: 'Vui lòng chọn sân thi đấu' });
    }

    if (!facility) {
      facility = await fetchFacilityById(court.facilityId);
    }
    if (!facility) {
      return res.status(404).json({ error: 'Không tìm thấy cơ sở của sân đã chọn' });
    }
    const facilityId = facility._id instanceof ObjectId ? facility._id : coerceObjectId(facility._id);
    if (!facilityId) {
      return res.status(400).json({ error: 'Cơ sở không hợp lệ' });
    }
    const courtFacilityId = coerceObjectId(court.facilityId);
    if (facilityId && courtFacilityId && !facilityId.equals(courtFacilityId)) {
      return res.status(400).json({ error: 'Sân không thuộc cơ sở đã chọn' });
    }

    const availability = await checkCourtAvailability({ courtId: court._id, start, end });
    if (!availability.available) {
      return res.status(409).json({ error: 'Khung giờ này đã có lịch, vui lòng chọn thời gian khác' });
    }

    const matchMode = normalizeMatchRequestMode(body.mode);
    const hostTeamName = normalizeTeamNameInput(body.teamName ?? body.hostTeam?.teamName);

    const teamSizeValue = coerceNumber(body.teamSize ?? sport.teamSize);
    const normalizedTeamSize = teamSizeValue ? Math.max(1, Math.min(20, Math.round(teamSizeValue))) : null;

    if (matchMode === 'team') {
      if (!normalizedTeamSize || normalizedTeamSize < 2) {
        return res.status(400).json({ error: 'team_size_required', message: 'Vui lòng nhập số người mỗi đội (tối thiểu 2).' });
      }
    }

    let participantLimitValue = null;
    const rawLimit = body.participantLimit ?? body.playerCount ?? body.maxPlayers;
    if (rawLimit !== undefined && rawLimit !== null && rawLimit !== '') {
      const parsed = Number.parseInt(String(rawLimit), 10);
      if (Number.isNaN(parsed) || parsed < 2) {
        return res.status(400).json({ error: 'Số người tham gia tối đa không hợp lệ' });
      }
      participantLimitValue = Math.max(2, normalizedTeamSize);
    } else if (normalizedTeamSize) {
      participantLimitValue = Math.max(2, normalizedTeamSize);
    } else {
      participantLimitValue = 2;
    }

    const notes = typeof body.notes === 'string' && body.notes.trim().length
      ? body.notes.trim().substring(0, 500)
      : null;

    const doc = {
      creatorId: userId,
      sportId: sport._id,
      facilityId: facilityId,
      courtId: court._id,
      desiredStart: start,
      desiredEnd: end,
      visibility,
      status: 'open',
      participants: [userId],
      teams: {
        teamA: [userId],
        teamB: [],
      },
      mode: matchMode,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    if (matchMode === 'team') {
      doc.hostTeam = {
        captainUserId: userId,
      };
      if (hostTeamName) doc.hostTeam.teamName = hostTeamName;
      doc.guestTeam = {
        captainUserId: null,
        teamName: null,
      };
    }

    if (skillRangeDoc) doc.skillRange = skillRangeDoc;
    if (normalizedTeamSize) doc.teamSize = new Int32(normalizedTeamSize);
    if (participantLimitValue !== null) doc.participantLimit = new Int32(participantLimitValue);
    if (location) doc.location = location;
    if (notes) doc.notes = notes;

    const insert = await db.collection('match_requests').insertOne(doc);

    await recordAudit(req, {
      actorId: userId,
      action: 'match_request.create',
      resource: 'match_request',
      resourceId: insert.insertedId,
      changes: sanitizeAuditData(doc),
    });

    if (matchMode === 'team') {
      try {
        const startLabel = start.toLocaleString('vi-VN', { hour12: false });
        const endLabel = end.toLocaleString('vi-VN', { hour12: false });
        const segments = [];
        if (sport?.name) segments.push(`Môn ${sport.name}`);
        if (facility?.name) segments.push(`tại ${facility.name}`);
        if (court?.name) segments.push(`sân ${court.name}`);
        segments.push(`${startLabel} - ${endLabel}`);
        const message = segments.join(' | ');
        await notifyMatchParticipants({ ...doc, _id: insert.insertedId }, {
          title: 'Đã tạo lời mời ghép đội',
          message: message || 'Bạn đã tạo lời mời thi đấu đội - đội.',
          data: { matchRequestId: insert.insertedId, mode: 'team' },
        });
      } catch (notificationError) {
        console.error('Failed to notify host team about new match request', notificationError);
      }
    }

    const [shaped] = await fetchMatchRequests({
      filter: { _id: insert.insertedId },
      limit: 1,
      currentUserId: userId,
    });

    res.status(201).json(shaped);
  } catch (e) { next(e); }
});

app.get('/api/match_requests', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const { status, sportId, limit } = req.query || {};
    const filter = { visibility: 'public' };

    if (status) {
      const cleanStatus = String(status).trim().toLowerCase();
      if (MATCH_REQUEST_ALLOWED_STATUSES.has(cleanStatus)) {
        filter.status = cleanStatus;
      }
    }
    if (!filter.status) filter.status = 'open';

    if (sportId) {
      const candidates = buildIdCandidates(sportId);
      if (candidates.length) {
        filter.sportId = { $in: candidates }; // $in with strings/oid is fine
      }
    }

    const limitValue = limit ? Number.parseInt(String(limit), 10) : 20;
    const shaped = await fetchMatchRequests({
      filter,
      limit: Number.isFinite(limitValue) ? Math.max(1, Math.min(100, limitValue)) : 20,
      currentUserId: userId,
    });

    res.json(shaped);
  } catch (e) { next(e); }
});

app.put('/api/match_requests/:id/join', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const candidates = buildIdCandidates(req.params.id);
    if (!candidates.length) return res.status(404).json({ error: 'Lời mời không tồn tại' });

    const requestDoc = await db.collection('match_requests').findOne({ _id: { $in: candidates } });
    if (!requestDoc) return res.status(404).json({ error: 'Lời mời không tồn tại' });

    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const matchMode = normalizeMatchRequestMode(requestDoc.mode);

    if (matchMode === 'team') {
      const hostCaptainId = coerceObjectId(requestDoc.hostTeam?.captainUserId ?? requestDoc.creatorId);
      if (hostCaptainId && hostCaptainId.equals(userId)) {
        return res.status(400).json({ error: 'Bạn không thể tham gia với vai trò đội đối thủ cho lời mời này.' });
      }

      const guestCaptainId = coerceObjectId(requestDoc.guestTeam?.captainUserId);
      if (guestCaptainId && guestCaptainId.equals(userId)) {
        const [existingTeamRequest] = await fetchMatchRequests({
          filter: { _id: requestDoc._id },
          limit: 1,
          currentUserId: userId,
        });
        return res.json(existingTeamRequest ?? sanitizeAuditData(requestDoc));
      }
      if (guestCaptainId) {
        return res.status(409).json({ error: 'Lời mời này đã có đội đối thủ tham gia' });
      }

      const currentStatus = typeof requestDoc.status === 'string' ? requestDoc.status.trim().toLowerCase() : 'open';
      if (currentStatus !== 'open') {
        return res.status(400).json({ error: 'Lời mời này không còn mở' });
      }

      const guestTeamName = normalizeTeamNameInput(body.teamName ?? body.guestTeam?.teamName);

      const overlappingCaptain = await db.collection('match_requests').findOne({
        _id: { $ne: requestDoc._id },
        mode: 'team',
        status: { $in: ['open', 'matched'] },
        $or: [
          { 'hostTeam.captainUserId': userId },
          { 'guestTeam.captainUserId': userId },
        ],
        desiredStart: { $lt: requestDoc.desiredEnd },
        desiredEnd: { $gt: requestDoc.desiredStart },
      });
      if (overlappingCaptain) {
        return res.status(409).json({ error: 'Bạn đang là đội trưởng của một lời mời khác trong khung giờ này' });
      }

      const now = new Date();
      const setPayload = {
        'guestTeam.captainUserId': userId,
        'guestTeam.teamName': guestTeamName ?? null,
        status: 'matched',
        updatedAt: now,
      };

      const updateResult = await db.collection('match_requests').findOneAndUpdate(
        {
          _id: requestDoc._id,
          $or: [
            { 'guestTeam.captainUserId': null },
            { 'guestTeam.captainUserId': { $exists: false } },
          ],
        },
        {
          $set: setPayload,
          $addToSet: { participants: userId, 'teams.teamB': userId },
        },
        { returnDocument: 'after' },
      );

      const updatedDoc = updateResult?.value ?? await db.collection('match_requests').findOne({ _id: requestDoc._id });
      if (!updatedDoc) {
        return res.status(404).json({ error: 'Lời mời không tồn tại' });
      }

      await recordAudit(req, {
        actorId: userId,
        action: 'match_request.join',
        resource: 'match_request',
        resourceId: requestDoc._id,
        changes: { guestCaptainId: userId, mode: 'team' },
      });

      try {
        const [sportDoc, facilityDoc, courtDoc] = await Promise.all([
          fetchSportById(updatedDoc.sportId ?? requestDoc.sportId),
          fetchFacilityById(updatedDoc.facilityId ?? requestDoc.facilityId),
          fetchCourtById(updatedDoc.courtId ?? requestDoc.courtId),
        ]);
        const startLabel = coerceDateValue(updatedDoc.desiredStart)?.toLocaleString('vi-VN', { hour12: false }) ?? '';
        const endLabel = coerceDateValue(updatedDoc.desiredEnd)?.toLocaleString('vi-VN', { hour12: false }) ?? '';
        const parts = [];
        if (sportDoc?.name) parts.push(`Môn ${sportDoc.name}`);
        if (facilityDoc?.name) parts.push(`tại ${facilityDoc.name}`);
        if (courtDoc?.name) parts.push(`sân ${courtDoc.name}`);
        if (startLabel && endLabel) parts.push(`${startLabel} - ${endLabel}`);
        const message = parts.join(' | ');
        await notifyMatchParticipants(updatedDoc, {
          title: 'Đã có đội đối thủ tham gia',
          message: message || 'Đội đối thủ đã nhận lời ghép trận của bạn.',
          data: { matchRequestId: updatedDoc._id, mode: 'team' },
        });
      } catch (notificationError) {
        console.error('Failed to notify teams about guest join', notificationError);
      }

      const [teamModeResponse] = await fetchMatchRequests({
        filter: { _id: requestDoc._id },
        limit: 1,
        currentUserId: userId,
      });

      return res.json(teamModeResponse ?? sanitizeAuditData(updatedDoc));
    }

    const teamChoice = normalizeTeamChoice(body.team ?? body.teamCode ?? body.teamId);
    if (teamChoice.error) {
      return res.status(400).json({ error: 'Lựa chọn đội không hợp lệ' });
    }

    const currentParticipantsRaw = Array.isArray(requestDoc.participants) ? requestDoc.participants : [];
    const participantIds = currentParticipantsRaw
      .map((value) => coerceObjectId(value))
      .filter((value) => value instanceof ObjectId);

    const toObjectIdArray = (value) => {
      const source = Array.isArray(value)
        ? value
        : (value && typeof value === 'object' && Array.isArray(value.members) ? value.members : []);
      const seen = new Set();
      const result = [];
      for (const entry of source) {
        const oid = coerceObjectId(entry);
        if (!oid) continue;
        const key = oid.toHexString();
        if (seen.has(key)) continue;
        seen.add(key);
        result.push(oid);
      }
      return result;
    };

    let teamAIds = toObjectIdArray(requestDoc.teams?.teamA);
    let teamBIds = toObjectIdArray(requestDoc.teams?.teamB);

    if (!teamAIds.length && !teamBIds.length && participantIds.length) {
      const seen = new Set();
      teamAIds = participantIds.filter((oid) => {
        const key = oid.toHexString();
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
    }

    const isInTeamA = teamAIds.some((oid) => oid.equals(userId));
    const isInTeamB = teamBIds.some((oid) => oid.equals(userId));
    let existingTeam = null;
    if (isInTeamA) existingTeam = 'teamA';
    else if (isInTeamB) existingTeam = 'teamB';

    const alreadyJoined = existingTeam !== null || participantIds.some((oid) => oid.equals(userId));

    const creatorId = coerceObjectId(requestDoc.creatorId);
    if (creatorId && creatorId.equals(userId) && !existingTeam) {
      existingTeam = 'teamA';
    }

    if (alreadyJoined && existingTeam && (!teamChoice.provided || teamChoice.value === null || teamChoice.value === 'auto' || teamChoice.value === existingTeam)) {
      const [shapedExisting] = await fetchMatchRequests({
        filter: { _id: requestDoc._id },
        limit: 1,
        currentUserId: userId,
      });
      return res.json(shapedExisting);
    }

    if (requestDoc.status && requestDoc.status !== 'open' && !(alreadyJoined && existingTeam)) {
      return res.status(400).json({ error: 'Lời mời này không còn mở' });
    }

    const limitValue = coerceNumber(requestDoc.participantLimit);
    if (!alreadyJoined && limitValue && participantIds.length >= limitValue) {
      return res.status(409).json({ error: 'Lời mời đã đủ người tham gia' });
    }

    let targetTeam = null;
    if (teamChoice.value === 'teamA' || teamChoice.value === 'teamB') {
      targetTeam = teamChoice.value;
    } else if (teamChoice.value === 'auto' || teamChoice.value === null) {
      targetTeam = existingTeam ?? (teamAIds.length <= teamBIds.length ? 'teamA' : 'teamB');
    } else if (!teamChoice.provided) {
      targetTeam = existingTeam ?? (teamAIds.length <= teamBIds.length ? 'teamA' : 'teamB');
    }
    if (!targetTeam) targetTeam = 'teamA';

    if (existingTeam && existingTeam === targetTeam && alreadyJoined) {
      const [shapedExisting] = await fetchMatchRequests({
        filter: { _id: requestDoc._id },
        limit: 1,
        currentUserId: userId,
      });
      return res.json(shapedExisting);
    }

    const teamCapacity = resolveTeamCapacity(requestDoc);
    const projectedCounts = {
      teamA: teamAIds.length - (existingTeam === 'teamA' ? 1 : 0),
      teamB: teamBIds.length - (existingTeam === 'teamB' ? 1 : 0),
    };

    if (teamCapacity && projectedCounts[targetTeam] >= teamCapacity) {
      return res.status(409).json({ error: 'Đội đã đủ người tham gia' });
    }

    const now = new Date();

    await db.collection('match_requests').updateOne(
      { _id: requestDoc._id },
      { $pull: { 'teams.teamA': userId, 'teams.teamB': userId } },
    );

    const addToSetOps = {
      participants: userId,
    };
    addToSetOps[`teams.${targetTeam}`] = userId;

    const updateResult = await db.collection('match_requests').findOneAndUpdate(
      { _id: requestDoc._id },
      { $addToSet: addToSetOps, $set: { updatedAt: now } },
      { returnDocument: 'after' },
    );

    const updatedDoc = updateResult?.value ?? updateResult ?? null;
    if (!updatedDoc) return res.status(404).json({ error: 'Lời mời không tồn tại' });

    await recordAudit(req, {
      actorId: userId,
      action: 'match_request.join',
      resource: 'match_request',
      resourceId: requestDoc._id,
      changes: { participantId: userId, team: targetTeam },
    });

    let finalDoc = updatedDoc;
    const participantCount = Array.isArray(updatedDoc.participants) ? updatedDoc.participants.length : 0;
    const filled = limitValue ? participantCount >= limitValue : false;
    if (filled) {
      finalDoc = await ensureMatchRequestBooking(updatedDoc, { req });
    } else if (updatedDoc.status !== 'open') {
      await db.collection('match_requests').updateOne(
        { _id: updatedDoc._id },
        { $set: { status: 'open', updatedAt: new Date() } },
      );
      finalDoc = await db.collection('match_requests').findOne({ _id: updatedDoc._id });
    }

    const [shaped] = await fetchMatchRequests({
      filter: { _id: requestDoc._id },
      limit: 1,
      currentUserId: userId,
    });

    res.json(shaped ?? sanitizeAuditData(finalDoc));
  } catch (e) { next(e); }
});

app.put('/api/match_requests/:id/cancel', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const userId = getAppUserObjectId(req);
    if (!userId) return res.status(401).json({ error: 'Unauthenticated' });
    const candidates = buildIdCandidates(req.params.id);
    if (!candidates.length) return res.status(404).json({ error: 'Lời mời không tồn tại' });

    const requestDoc = await db.collection('match_requests').findOne({ _id: { $in: candidates } });
    if (!requestDoc) return res.status(404).json({ error: 'Lời mời không tồn tại' });

    const creatorId = coerceObjectId(requestDoc.creatorId);
    const isCreator = creatorId ? creatorId.equals(userId) : false;
    const isAdmin = req.appUser?.role === 'admin';
    const cancelActorLabel = isCreator ? 'Người tạo' : 'Quản trị viên';

    if (!isCreator && !isAdmin) {
      return res.status(403).json({ error: 'Bạn chỉ có thể hủy lời mời do bạn tạo.' });
    }

    if (requestDoc.status === 'cancelled') {
      const [shapedExisting] = await fetchMatchRequests({
        filter: { _id: requestDoc._id },
        limit: 1,
        currentUserId: userId,
      });
      return res.json(shapedExisting ?? sanitizeAuditData(requestDoc));
    }

    const now = new Date();
    const cancelReasonCode = isCreator ? 'manual_cancel' : 'manual_cancel';
    const cancelledByRole = isCreator ? 'customer' : 'admin';
    const updateFields = {
      status: 'cancelled',
      cancelledAt: now,
      cancelledBy: userId,
      cancelledByRole,
      cancelledByUserId: userId,
      cancelReasonCode,
      cancelReasonText: isCreator ? 'Người tạo hủy lời mời' : 'Quản trị viên hủy lời mời',
      cancelledReason: isCreator ? 'creator_cancelled' : 'admin_cancelled',
      updatedAt: now,
    };

    if (requestDoc.bookingStatus !== 'cancelled') {
      updateFields.bookingStatus = 'cancelled';
    }

    await db.collection('match_requests').updateOne(
      { _id: requestDoc._id },
      { $set: updateFields },
    );

    const bookingId = coerceObjectId(requestDoc.matchedBookingId);
    if (bookingId) {
      await db.collection('bookings').updateOne(
        { _id: bookingId },
        {
          $set: {
            status: 'cancelled',
            cancelledAt: now,
            cancelledBy: userId,
            cancelledByRole,
            cancelledByUserId: userId,
            cancelReasonCode,
            cancelReasonText: isCreator ? 'Người tạo hủy lời mời' : 'Quản trị viên hủy lời mời',
            cancelledReason: 'match_request_cancelled',
            updatedAt: now,
          },
        },
      );
    }

    await recordAudit(req, {
      actorId: userId,
      action: 'match_request.cancel',
      resource: 'match_request',
      resourceId: requestDoc._id,
      changes: { status: 'cancelled', cancelledAt: now },
    });

    const refreshed = await db.collection('match_requests').findOne({ _id: requestDoc._id });
    if (refreshed) {
      await notifyMatchParticipants(refreshed, {
        title: 'Lời mời thi đấu đã bị hủy',
        message: `${cancelActorLabel} đã hủy lời mời thi đấu này.`,
        data: { matchRequestId: refreshed._id },
      });
      await notifyStaffMatchRequest(refreshed, {
        title: 'Lời mời thi đấu đã bị hủy',
        message: `${cancelActorLabel} đã hủy lời mời này và không còn hiệu lực.`,
        data: { matchRequestId: refreshed._id },
      });
    }

    const [shaped] = await fetchMatchRequests({
      filter: { _id: requestDoc._id },
      limit: 1,
      currentUserId: userId,
    });

    res.json(shaped ?? sanitizeAuditData(refreshed ?? requestDoc));
  } catch (e) { next(e); }
});

app.get('/api/user/notifications', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const customerId = getAppUserObjectId(req);
    if (!customerId) return res.status(401).json({ error: 'Unauthenticated' });
    const rawLimit = Number.parseInt(String(req.query?.limit ?? ''), 10);
    let limitValue = Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : 20;
    limitValue = Math.min(limitValue, 20);

    const items = await db.collection('notifications')
      .find({ recipientId: customerId })
      .sort({ createdAt: -1 })
      .limit(limitValue)
      .toArray();

    res.json(items.map((doc) => shapeNotification(doc)));
  } catch (e) { next(e); }
});

app.post('/api/user/notifications/:id/read', authMiddleware, requireVerifiedCustomer, async (req, res, next) => {
  try {
    const customerId = getAppUserObjectId(req);
    if (!customerId) return res.status(401).json({ error: 'Unauthenticated' });
    const candidates = buildIdCandidates(req.params.id);
    if (!candidates.length) return res.status(404).json({ error: 'Không tìm thấy thông báo' });

    const result = await db.collection('notifications').findOneAndUpdate(
      { _id: { $in: candidates }, recipientId: customerId },
      { $set: { status: 'read', readAt: new Date() } },
      { returnDocument: 'after' },
    );

    if (!result.value) return res.status(404).json({ error: 'Không tìm thấy thông báo' });
    res.json(shapeNotification(result.value));
  } catch (e) { next(e); }
});

app.get('/api/staff/facility', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const facilityDoc = await fetchFacilityById(facilityId);
    if (!facilityDoc) {
      return res.status(404).json({ error: 'Facility not found' });
    }

    const courts = await db.collection('courts')
      .find({ facilityId, status: { $ne: 'deleted' } })
      .sort({ name: 1 })
      .toArray();

    const courtIds = courts
      .map((court) => coerceObjectId(court._id))
      .filter((oid) => oid);

    const maintenanceMap = new Map();
    if (courtIds.length) {
      const maintenanceDocs = await db.collection('maintenance')
        .find({ courtId: { $in: courtIds }, status: { $ne: 'deleted' } })
        .sort({ start: 1 })
        .limit(1000)
        .toArray();

      for (const doc of maintenanceDocs) {
        const key = normalizeIdString(doc.courtId);
        if (!key) continue;
        const shaped = sanitizeAuditData(doc);
        const list = maintenanceMap.get(key) || [];
        list.push(shaped);
        maintenanceMap.set(key, list);
      }
    }

    const shapedCourts = courts.map((court) => {
      const courtId = normalizeIdString(court._id);
      const maintenance = maintenanceMap.get(courtId) || [];
      const amenities = normalizeStringArrayInput(court.amenities);
      return cleanObject({
        ...sanitizeAuditData(court),
        amenities,
        maintenance,
      });
    });

    res.json({
      facility: sanitizeAuditData(facilityDoc),
      courts: shapedCourts,
    });
  } catch (error) {
    next(error);
  }
});

app.put('/api/staff/facility', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const $set = {};
    const $unset = {};
    const body = req.body || {};

    if (body.name !== undefined) {
      const trimmed = String(body.name).trim();
      if (!trimmed.length) return res.status(400).json({ error: 'name cannot be empty' });
      $set.name = trimmed;
    }

    if (body.timeZone !== undefined) {
      const trimmed = String(body.timeZone).trim();
      if (!trimmed.length) return res.status(400).json({ error: 'timeZone cannot be empty' });
      $set.timeZone = trimmed;
    }

    if (body.active !== undefined) {
      $set.active = !!body.active;
    }

    if (body.address !== undefined) {
      if (body.address && typeof body.address === 'object') {
        const safe = {};
        for (const k of ['line1', 'ward', 'district', 'city', 'province', 'country', 'postalCode']) {
          if (body.address[k] !== undefined) safe[k] = String(body.address[k]);
        }
        if (body.address.lat !== undefined) safe.lat = Number(body.address.lat);
        if (body.address.lng !== undefined) safe.lng = Number(body.address.lng);
        $set.address = safe;
      } else {
        $unset.address = '';
      }
    }

    if (!Object.keys($set).length && !Object.keys($unset).length) {
      return res.status(400).json({ error: 'No changes provided' });
    }

    $set.updatedAt = new Date();
    const updateDoc = {};
    if (Object.keys($set).length) updateDoc.$set = $set;
    if (Object.keys($unset).length) updateDoc.$unset = $unset;

    const result = await db.collection('facilities').findOneAndUpdate(
      { _id: facilityId },
      updateDoc,
      { returnDocument: ReturnDocument.AFTER },
    );

    if (!result.value) {
      return res.status(404).json({ error: 'Facility not found' });
    }

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.facility-update',
      resource: 'facility',
      resourceId: facilityId,
      changes: sanitizeAuditData({ $set, $unset }),
    });

    res.json(sanitizeAuditData(result.value));
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/sports', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const includeInactive = req.query?.includeInactive === 'true';
    const filter = includeInactive ? {} : { active: { $ne: false } };

    const facilitySportIds = await db.collection('courts').distinct('sportId', {
      facilityId,
      status: { $ne: 'deleted' },
    });

    const normalizedSportIds = facilitySportIds
      .map((id) => coerceObjectId(id))
      .filter((oid) => oid);

    if (normalizedSportIds.length) {
      filter._id = { $in: normalizedSportIds };
    }

    const sports = await db.collection('sports').find(filter).sort({ name: 1 }).toArray();
    res.json(sports.map((sport) => sanitizeAuditData(sport)));
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/sports', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { name, code, teamSize, active = true } = req.body || {};
    if (!name || !code || teamSize === undefined) {
      return res.status(400).json({ error: 'name, code, teamSize required' });
    }

    const doc = {
      name: String(name).trim(),
      code: String(code).trim(),
      teamSize: Number(teamSize),
      active: !!active,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdByStaffId: staffUser._id,
    };

    const insert = await db.collection('sports').insertOne(doc);
    const saved = await db.collection('sports').findOne({ _id: insert.insertedId });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.sport.create',
      resource: 'sport',
      resourceId: insert.insertedId,
      payload: req.body,
      changes: saved,
    });

    res.status(201).json(sanitizeAuditData(saved));
  } catch (error) {
    next(error);
  }
});

app.put('/api/staff/sports/:id', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const sport = await fetchSportById(req.params.id);
    if (!sport) return res.status(404).json({ error: 'Sport not found' });

    const { name, code, teamSize, active } = req.body || {};
    const $set = { updatedAt: new Date() };

    if (name !== undefined) {
      const trimmed = String(name).trim();
      if (!trimmed.length) return res.status(400).json({ error: 'name cannot be empty' });
      $set.name = trimmed;
    }

    if (code !== undefined) {
      const trimmed = String(code).trim();
      if (!trimmed.length) return res.status(400).json({ error: 'code cannot be empty' });
      $set.code = trimmed;
    }

    if (teamSize !== undefined) {
      $set.teamSize = Number(teamSize);
    }

    if (active !== undefined) {
      $set.active = !!active;
    }

    const updateOps = { $set };
    const updated = await db.collection('sports').findOneAndUpdate(
      { _id: sport._id },
      updateOps,
      { returnDocument: ReturnDocument.AFTER },
    );

    if (!updated.value) return res.status(404).json({ error: 'Sport not found' });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.sport.update',
      resource: 'sport',
      resourceId: sport._id,
      payload: req.body,
      changes: updated.value,
    });

    res.json(sanitizeAuditData(updated.value));
  } catch (error) {
    next(error);
  }
});

app.delete('/api/staff/sports/:id', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const sport = await fetchSportById(req.params.id);
    if (!sport) return res.status(404).json({ error: 'Sport not found' });

    const result = await db.collection('sports').deleteOne({ _id: sport._id });
    if (!result.deletedCount) return res.status(404).json({ error: 'Sport not found' });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.sport.delete',
      resource: 'sport',
      resourceId: sport._id,
      payload: { id: req.params.id },
      changes: { deleted: true },
    });

    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/bookings', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const { status } = req.query || {};
    const filter = {
      facilityId,
      deletedAt: { $exists: false },
    };

    if (typeof status === 'string' && status.trim().length) {
      filter.status = status.trim().toLowerCase();
    }

    const fromDate = coerceDateValue(req.query?.from);
    const toDate = coerceDateValue(req.query?.to);
    if (fromDate || toDate) {
      filter.start = {};
      if (fromDate) filter.start.$gte = fromDate;
      if (toDate) filter.start.$lte = toDate;
    }

    const parsedLimit = Number.parseInt(req.query?.limit, 10);
    const limit = Number.isFinite(parsedLimit) ? Math.min(Math.max(parsedLimit, 1), 200) : 100;

    const pipeline = [
      { $match: filter },
      { $sort: { start: -1, _id: -1 } },
      { $limit: limit },
      { $lookup: { from: 'users', localField: 'customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'sports', localField: 'sportId', foreignField: '_id', as: 'sport' } },
      { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
    ];

    const bookings = await db.collection('bookings').aggregate(pipeline).toArray();
    res.json(bookings.map((doc) => shapeStaffBooking(doc)).filter(Boolean));
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/bookings', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const body = req.body || {};
    const sportId = coerceObjectId(body.sportId);
    const courtId = coerceObjectId(body.courtId);
    if (!sportId) return res.status(400).json({ error: 'sportId invalid' });
    if (!courtId) return res.status(400).json({ error: 'courtId invalid' });

    const court = await fetchCourtById(courtId);
    if (!court) return res.status(404).json({ error: 'Court not found' });
    if (!court.facilityId || String(court.facilityId) !== String(facilityId)) {
      return res.status(403).json({ error: 'Court does not belong to your facility' });
    }

    const s = coerceDateValue(body.start);
    const e = coerceDateValue(body.end);
    if (!(s && e && s < e)) {
      return res.status(400).json({ error: 'start and end must be valid and start < end' });
    }

    let customerId = coerceObjectId(body.customerId);
    if (!customerId) {
      const customer = body.customer && typeof body.customer === 'object' ? body.customer : {};
      const doc = cleanObject({
        role: 'customer',
        status: 'active',
        name: typeof customer.name === 'string' ? customer.name.trim() : undefined,
        phone: typeof customer.phone === 'string' ? customer.phone.trim() : undefined,
        email: typeof customer.email === 'string' ? customer.email.trim().toLowerCase() : undefined,
        createdAt: new Date(),
      });
      const insertCustomer = await db.collection('users').insertOne(doc);
      customerId = insertCustomer.insertedId;
    }

    const overlapExpr = { $or: [ { start: { $lt: e }, end: { $gt: s } } ] };
    const conflict = await db.collection('bookings').findOne({
      courtId,
      ...overlapExpr,
      status: { $in: ['pending', 'confirmed', 'completed'] },
    });
    const maintenance = await db.collection('maintenance').findOne({
      courtId,
      ...overlapExpr,
    });
    if (conflict || maintenance) {
      return res.status(409).json({ error: 'Court not available for the requested time' });
    }

    const quote = await quotePrice({
      db,
      facilityId: facilityId.toHexString(),
      sportId: sportId.toHexString(),
      courtId: courtId.toHexString(),
      start: s,
      end: e,
      currency: typeof body.currency === 'string' ? body.currency : 'VND',
      user: await db.collection('users').findOne({ _id: customerId }),
    });

    const participants = Array.isArray(body.participants)
      ? body.participants
          .map((x) => String(x).trim())
          .filter((x) => ObjectId.isValid(x))
          .map((x) => new ObjectId(x))
      : [];

    const status = body.confirm ? 'confirmed' : 'pending';
    const doc = cleanObject({
      customerId,
      facilityId,
      courtId,
      sportId,
      start: s,
      end: e,
      status,
      currency: typeof body.currency === 'string' ? body.currency : 'VND',
      participants,
      pricingSnapshot: quote,
      contactMethod: typeof body.contactMethod === 'string' ? body.contactMethod.trim() : undefined,
      note: typeof body.note === 'string' ? body.note.trim() : undefined,
      createdAt: new Date(),
      createdByStaffId: staffUser._id,
    });

    const insert = await db.collection('bookings').insertOne(doc);
    const createdBooking = { _id: insert.insertedId, ...doc };

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.booking.create',
      resource: 'booking',
      resourceId: insert.insertedId,
      payload: body,
      changes: createdBooking,
    });

    if (status === 'confirmed') {
      try {
        await ensureBookingInvoice(createdBooking);
      } catch (invoiceError) {
        console.error('Failed to ensure invoice for staff booking', insert.insertedId, invoiceError);
      }
    }

    const shaped = await db.collection('bookings').aggregate([
      { $match: { _id: insert.insertedId } },
      { $lookup: { from: 'users', localField: 'customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'sports', localField: 'sportId', foreignField: '_id', as: 'sport' } },
      { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
      { $limit: 1 },
    ]).toArray();

    res.status(201).json(shapeStaffBooking(shaped[0]));
  } catch (error) {
    next(error);
  }
});

app.patch('/api/staff/bookings/:id/status', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const bookingCandidates = buildIdCandidates(req.params.id);
    if (!bookingCandidates.length) {
      return res.status(404).json({ error: 'Lượt đặt sân không tồn tại' });
    }

    const bookingDoc = await db.collection('bookings').findOne({
      _id: { $in: bookingCandidates },
      facilityId,
      deletedAt: { $exists: false },
    });
    if (!bookingDoc) {
      return res.status(404).json({ error: 'Lượt đặt sân không tồn tại' });
    }

    const nextStatusRaw = typeof req.body?.status === 'string' ? req.body.status.trim() : '';
    const nextStatus = nextStatusRaw.toLowerCase();
    if (!nextStatus.length) {
      return res.status(400).json({ error: 'Trạng thái không hợp lệ' });
    }

    const statusUpdatedAt = new Date();
    const updateFields = { status: nextStatus, updatedAt: statusUpdatedAt };

    // Add cancellation metadata if staff is cancelling/declining
    if (nextStatus === 'cancelled') {
      updateFields.cancelledAt = statusUpdatedAt;
      updateFields.cancelledBy = staffUser._id;
      updateFields.cancelledByRole = 'staff';
      updateFields.cancelledByUserId = staffUser._id;
      updateFields.cancelReasonCode = 'staff_cancel';
      updateFields.cancelReasonText = 'Nhân viên hủy/không duyệt đặt sân';
      updateFields.cancelledReason = 'staff_cancelled';
    }

    await db.collection('bookings').updateOne(
      { _id: bookingDoc._id },
      { $set: updateFields },
    );

    const updatedBooking = { ...bookingDoc, ...updateFields };

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.booking-status-update',
      resource: 'booking',
      resourceId: bookingDoc._id,
      changes: sanitizeAuditData({
        previousStatus: bookingDoc.status ?? null,
        nextStatus,
        ...(nextStatus === 'cancelled' ? { cancelReasonCode: 'staff_cancel' } : {}),
      }),
    });

    if (nextStatus === 'confirmed') {
      try {
        await ensureBookingInvoice(updatedBooking);
      } catch (invoiceError) {
        console.error('Failed to ensure invoice for booking', bookingDoc._id, invoiceError);
      }
    } else if (nextStatus === 'cancelled') {
      try {
        await voidBookingInvoice(updatedBooking, { reason: 'staff_cancelled' });
      } catch (invoiceError) {
        console.error('Failed to void invoice for booking', bookingDoc._id, invoiceError);
      }
    }

    const decorated = await db.collection('bookings').aggregate([
      { $match: { _id: bookingDoc._id } },
      { $lookup: { from: 'users', localField: 'customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'sports', localField: 'sportId', foreignField: '_id', as: 'sport' } },
      { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
      { $limit: 1 },
    ]).toArray();

    const shaped = decorated.map((doc) => shapeStaffBooking(doc)).filter(Boolean)[0] ?? null;
    if (!shaped) {
      return res.status(404).json({ error: 'Lượt đặt sân không tồn tại' });
    }

    res.json(shaped);
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/courts/:id/maintenance', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const court = await fetchCourtById(req.params.id);
    if (!court) return res.status(404).json({ error: 'Court not found' });
    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId || String(court.facilityId) !== String(facilityId)) {
      return res.status(403).json({ error: 'Court does not belong to your facility' });
    }

    const start = coerceDateValue(req.body?.start);
    const end = coerceDateValue(req.body?.end);
    if (!(start && end && start < end)) {
      return res.status(400).json({ error: 'start and end must be valid and start < end' });
    }

    const overlapExpr = { $or: [ { start: { $lt: end }, end: { $gt: start } } ] };
    const conflict = await db.collection('bookings').findOne({
      courtId: court._id,
      ...overlapExpr,
      status: { $in: ['pending', 'confirmed', 'completed'] },
    });
    const maintenanceConflict = await db.collection('maintenance').findOne({ courtId: court._id, ...overlapExpr });
    if (conflict || maintenanceConflict) {
      return res.status(409).json({ error: 'Court not available for the requested time' });
    }

    const reasonRaw = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
    const doc = cleanObject({
      courtId: court._id,
      facilityId,
      start,
      end,
      // Mongo schema requires reason; default to a generic label when none provided.
      reason: reasonRaw || 'Maintenance',
      status: 'scheduled',
      createdAt: new Date(),
      updatedAt: new Date(),
      createdByStaffId: staffUser._id,
    });

    const insert = await db.collection('maintenance').insertOne(doc);
    const saved = { _id: insert.insertedId, ...doc };

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.maintenance.create',
      resource: 'maintenance',
      resourceId: insert.insertedId,
      payload: req.body,
      changes: saved,
    });

    res.status(201).json(sanitizeAuditData(saved));
  } catch (error) {
    next(error);
  }
});

app.put('/api/staff/maintenance/:id', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const maintenanceId = coerceObjectId(req.params.id);
    if (!maintenanceId) return res.status(404).json({ error: 'Maintenance not found' });

    const maintenanceDoc = await db.collection('maintenance').findOne({ _id: maintenanceId });
    if (!maintenanceDoc) return res.status(404).json({ error: 'Maintenance not found' });

    const court = await fetchCourtById(maintenanceDoc.courtId);
    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!court || !facilityId || String(court.facilityId) !== String(facilityId)) {
      return res.status(403).json({ error: 'Not authorized for this maintenance' });
    }

    const $set = { updatedAt: new Date() };
    const { start, end, reason, status } = req.body || {};

    const nextStart = start !== undefined ? coerceDateValue(start) : maintenanceDoc.start;
    const nextEnd = end !== undefined ? coerceDateValue(end) : maintenanceDoc.end;
    if (!(nextStart instanceof Date && nextEnd instanceof Date && nextStart < nextEnd)) {
      return res.status(400).json({ error: 'start and end must be valid and start < end' });
    }
    $set.start = nextStart;
    $set.end = nextEnd;

    if (reason !== undefined) {
      $set.reason = typeof reason === 'string' ? reason.trim() : undefined;
    }
    if (status !== undefined) {
      $set.status = String(status).trim();
    }

    const overlapExpr = { $or: [ { start: { $lt: nextEnd }, end: { $gt: nextStart } } ] };
    const conflict = await db.collection('bookings').findOne({
      courtId: court._id,
      ...overlapExpr,
      status: { $in: ['pending', 'confirmed', 'completed'] },
    });
    const maintenanceConflict = await db.collection('maintenance').findOne({
      _id: { $ne: maintenanceDoc._id },
      courtId: court._id,
      ...overlapExpr,
    });
    if (conflict || maintenanceConflict) {
      return res.status(409).json({ error: 'Court not available for the requested time' });
    }

    const result = await db.collection('maintenance').findOneAndUpdate(
      { _id: maintenanceDoc._id },
      { $set },
      { returnDocument: ReturnDocument.AFTER },
    );

    if (!result.value) return res.status(404).json({ error: 'Maintenance not found' });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.maintenance.update',
      resource: 'maintenance',
      resourceId: maintenanceDoc._id,
      payload: req.body,
      changes: result.value,
    });

    res.json(sanitizeAuditData(result.value));
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/maintenance/:id/action', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const maintenanceId = coerceObjectId(req.params.id);
    if (!maintenanceId) return res.status(404).json({ error: 'Maintenance not found' });
    const doc = await db.collection('maintenance').findOne({ _id: maintenanceId });
    if (!doc) return res.status(404).json({ error: 'Maintenance not found' });

    const court = await fetchCourtById(doc.courtId);
    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!court || !facilityId || String(court.facilityId) !== String(facilityId)) {
      return res.status(403).json({ error: 'Not authorized for this maintenance' });
    }

    const action = typeof req.body?.action === 'string' ? req.body.action.trim().toLowerCase() : '';
    if (!action) return res.status(400).json({ error: 'action required' });

    const $set = { updatedAt: new Date() };
    if (action === 'start') {
      $set.status = 'in_progress';
      $set.startedAt = new Date();
    } else if (action === 'complete' || action === 'completed') {
      $set.status = 'completed';
      $set.completedAt = new Date();
    } else if (action === 'cancel' || action === 'cancelled') {
      $set.status = 'cancelled';
      $set.cancelledAt = new Date();
    } else {
      return res.status(400).json({ error: 'Unsupported action' });
    }

    const result = await db.collection('maintenance').findOneAndUpdate(
      { _id: doc._id },
      { $set },
      { returnDocument: ReturnDocument.AFTER },
    );

    await recordAudit(req, {
      actorId: staffUser._id,
      action: `staff.maintenance.${action}`,
      resource: 'maintenance',
      resourceId: doc._id,
      payload: req.body,
      changes: result.value,
    });

    res.json(sanitizeAuditData(result.value));
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/invoices', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const invoiceMatch = {};
    if (typeof req.query?.status === 'string' && req.query.status.trim().length) {
      invoiceMatch.status = req.query.status.trim();
    }
    const issuedFrom = coerceDateValue(req.query?.from);
    const issuedTo = coerceDateValue(req.query?.to);
    if (issuedFrom || issuedTo) {
      invoiceMatch.issuedAt = {};
      if (issuedFrom) invoiceMatch.issuedAt.$gte = issuedFrom;
      if (issuedTo) invoiceMatch.issuedAt.$lte = issuedTo;
    }

    const parsedLimit = Number.parseInt(req.query?.limit, 10);
    const limit = Number.isFinite(parsedLimit) ? Math.min(Math.max(parsedLimit, 1), 200) : 100;

    const pipeline = [];
    if (Object.keys(invoiceMatch).length) {
      pipeline.push({ $match: invoiceMatch });
    }

    pipeline.push(
      {
        $lookup: {
          from: 'bookings',
          let: { bookingId: '$bookingId' },
          pipeline: [
            { $match: { $expr: { $eq: ['$_id', '$$bookingId'] } } },
            { $match: { facilityId } },
          ],
          as: 'booking',
        },
      },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $lookup: { from: 'users', localField: 'booking.customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'booking.courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'payments', localField: '_id', foreignField: 'invoiceId', as: 'payments' } },
      {
        $addFields: {
          bookingCurrency: '$booking.currency',
        },
      },
      {
        $sort: {
          issuedAt: -1,
          _id: -1,
        },
      },
      { $limit: limit },
    );

    const invoices = await db.collection('invoices').aggregate(pipeline).toArray();
    const shaped = invoices.map((doc) => shapeStaffInvoice(doc)).filter(Boolean);

    const inactiveStatuses = new Set(['void', 'cancelled', 'canceled', 'refunded']);
    const summary = shaped.reduce((acc, invoice) => {
      acc.invoiceCount += 1;
      const statusKey = typeof invoice?.status === 'string' ? invoice.status.trim().toLowerCase() : '';
      const isInactive = inactiveStatuses.has(statusKey);
      const amountContribution = isInactive ? 0 : (invoice?.amount ?? 0);
      const paidContribution = isInactive ? 0 : (invoice?.totalPaid ?? 0);
      const outstandingContribution = isInactive ? 0 : (invoice?.outstanding ?? 0);
      acc.totalInvoiced += amountContribution;
      acc.totalPaid += paidContribution;
      acc.totalOutstanding += outstandingContribution;
      acc.totalRevenue += paidContribution;
      return acc;
    }, {
      invoiceCount: 0,
      totalInvoiced: 0,
      totalPaid: 0,
      totalOutstanding: 0,
      totalRevenue: 0,
    });

    res.json({ invoices: shaped, summary });
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/invoices/:id/remind', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const invoiceCandidates = buildIdCandidates(req.params.id);
    if (!invoiceCandidates.length) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const invoiceDoc = await db.collection('invoices').findOne({ _id: { $in: invoiceCandidates } });
    if (!invoiceDoc) return res.status(404).json({ error: 'Hoá đơn không tồn tại' });

    const bookingId = coerceObjectId(invoiceDoc.bookingId);
    if (!bookingId) return res.status(404).json({ error: 'Hoá đơn không hợp lệ' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) return res.status(403).json({ error: 'Staff user is not assigned to any facility' });

    const bookingDoc = await db.collection('bookings').findOne({ _id: bookingId, facilityId });
    if (!bookingDoc) return res.status(404).json({ error: 'Hoá đơn không tồn tại' });

    const customerId = coerceObjectId(bookingDoc.customerId);
    if (customerId) {
      await createNotifications({
        userIds: [customerId],
        title: 'Nhắc thanh toán',
        message: req.body?.note || 'Vui lòng thanh toán hoá đơn đặt sân',
        data: {
          invoiceId: normalizeIdString(invoiceDoc._id),
          bookingId: normalizeIdString(bookingDoc._id),
          type: 'invoice-reminder',
        },
      });
    }

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.invoice.remind',
      resource: 'invoice',
      resourceId: invoiceDoc._id,
      payload: req.body,
    });

    const shaped = await db.collection('invoices').aggregate([
      { $match: { _id: invoiceDoc._id } },
      {
        $lookup: {
          from: 'bookings',
          let: { bookingId: '$bookingId' },
          pipeline: [
            { $match: { $expr: { $eq: ['$_id', '$$bookingId'] } } },
            { $match: { facilityId } },
          ],
          as: 'booking',
        },
      },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $lookup: { from: 'users', localField: 'booking.customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'booking.courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'payments', localField: '_id', foreignField: 'invoiceId', as: 'payments' } },
      { $limit: 1 },
    ]).toArray();

    res.json(shapeStaffInvoice(shaped[0]));
  } catch (error) {
    next(error);
  }
});

app.patch('/api/staff/invoices/:id/status', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const invoiceCandidates = buildIdCandidates(req.params.id);
    if (!invoiceCandidates.length) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const invoiceDoc = await db.collection('invoices').findOne({ _id: { $in: invoiceCandidates } });
    if (!invoiceDoc) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const bookingId = coerceObjectId(invoiceDoc.bookingId);
    if (!bookingId) {
      return res.status(404).json({ error: 'Hoá đơn không hợp lệ' });
    }

    const bookingDoc = await db.collection('bookings').findOne({ _id: bookingId, facilityId });
    if (!bookingDoc) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const invoiceIdCandidates = buildIdCandidates(
      (invoiceDoc._id && typeof invoiceDoc._id.toHexString === 'function')
        ? invoiceDoc._id.toHexString()
        : invoiceDoc._id,
    );
    if (!invoiceIdCandidates.some((candidate) => candidate instanceof ObjectId && candidate.equals(invoiceDoc._id))) {
      invoiceIdCandidates.push(invoiceDoc._id);
    }
    const invoiceAmountValue = normalizePaymentAmount(invoiceDoc.amount ?? bookingDoc.amount ?? bookingDoc.total ?? 0);
    let pendingPaymentDoc = null;
    const $set = {};
    const $unset = {};

    if (body.status !== undefined) {
      if (typeof body.status !== 'string' || !body.status.trim().length) {
        return res.status(400).json({ error: 'Trạng thái không hợp lệ' });
      }
      $set.status = body.status.trim();
    }

    const paidAtInput = normalizeDateInput(body.paidAt);
    if (paidAtInput.provided && paidAtInput.error) {
      return res.status(400).json({ error: 'paidAt không hợp lệ' });
    }
    const paidAtProvided = paidAtInput.provided === true;
    const paidProvided = body.paid !== undefined;

    if (paidProvided) {
      if (typeof body.paid !== 'boolean') {
        return res.status(400).json({ error: 'paid phải là true/false' });
      }
      $set.paid = body.paid;
      if (body.paid) {
        if (paidAtProvided) {
          if (!(paidAtInput.value instanceof Date)) {
            return res.status(400).json({ error: 'paidAt phải là ngày hợp lệ khi paid = true' });
          }
          $set.paidAt = paidAtInput.value;
        } else if (invoiceDoc.paidAt instanceof Date) {
          $set.paidAt = invoiceDoc.paidAt;
        } else {
          $set.paidAt = new Date();
        }
        delete $unset.paidAt;
      } else {
        $unset.paidAt = '';
        delete $set.paidAt;
      }
    }

    if (!paidProvided && paidAtProvided) {
      if (paidAtInput.value instanceof Date) {
        $set.paidAt = paidAtInput.value;
        delete $unset.paidAt;
      } else {
        $unset.paidAt = '';
        delete $set.paidAt;
      }
    }

    if (body.paid === true) {
      const existingPayments = await db.collection('payments')
        .find({ invoiceId: { $in: invoiceIdCandidates } })
        .toArray();
      const { totalPaid: currentPaid } = computePaymentTotals(existingPayments);
      const outstandingBefore = Math.max(0, invoiceAmountValue - currentPaid);
      if (outstandingBefore > 0) {
        const now = new Date();
        pendingPaymentDoc = cleanObject({
          invoiceId: invoiceDoc._id,
          provider: typeof body.paymentProvider === 'string' && body.paymentProvider.trim().length
            ? body.paymentProvider.trim()
            : 'staff-app',
          method: typeof body.paymentMethod === 'string' && body.paymentMethod.trim().length
            ? body.paymentMethod.trim()
            : 'manual',
          amount: outstandingBefore,
          currency: invoiceDoc.currency || bookingDoc.currency || 'VND',
          status: 'succeeded',
          createdAt: now,
          processedAt: now,
          meta: cleanObject({
            source: 'staff.mark-paid',
            actorId: staffUser._id,
            note: typeof body.paymentNote === 'string' && body.paymentNote.trim().length
              ? body.paymentNote.trim().substring(0, 240)
              : undefined,
          }),
        }) || null;
      }
    }

    if (!Object.keys($set).length && !Object.keys($unset).length) {
      return res.status(400).json({ error: 'Không có thay đổi nào được gửi lên' });
    }

    $set.updatedAt = new Date();

    const updateDoc = {};
    if (Object.keys($set).length) updateDoc.$set = $set;
    if (Object.keys($unset).length) updateDoc.$unset = $unset;

    await db.collection('invoices').updateOne({ _id: invoiceDoc._id }, updateDoc);

    if (pendingPaymentDoc) {
      const insertResult = await db.collection('payments').insertOne(pendingPaymentDoc);
      pendingPaymentDoc._id = insertResult.insertedId;
      await recordAudit(req, {
        actorId: staffUser._id,
        action: 'staff.manual-payment',
        resource: 'payment',
        resourceId: insertResult.insertedId,
        changes: sanitizeAuditData(pendingPaymentDoc),
      });
    }

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.invoice-status-update',
      resource: 'invoice',
      resourceId: invoiceDoc._id,
      changes: sanitizeAuditData({ $set, $unset }),
    });

    const decorated = await db.collection('invoices').aggregate([
      { $match: { _id: invoiceDoc._id } },
      {
        $lookup: {
          from: 'bookings',
          let: { bookingId: '$bookingId' },
          pipeline: [
            { $match: { $expr: { $eq: ['$_id', '$$bookingId'] } } },
            { $match: { facilityId } },
          ],
          as: 'booking',
        },
      },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $lookup: { from: 'users', localField: 'booking.customerId', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'courts', localField: 'booking.courtId', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'payments', localField: '_id', foreignField: 'invoiceId', as: 'payments' } },
      { $addFields: { bookingCurrency: '$booking.currency' } },
      { $limit: 1 },
    ]).toArray();

    const shaped = decorated.map((doc) => shapeStaffInvoice(doc)).filter(Boolean)[0] ?? null;
    if (!shaped) {
      return res.status(404).json({ error: 'Hoá đơn không tồn tại' });
    }

    res.json(shaped);
  } catch (error) {
    next(error);
  }
});

// =============================================================================
// STAFF REPORTS - Analytics endpoints for "Báo cáo thống kê" dashboard
// =============================================================================

const BOOKING_REVENUE_STATUSES = new Set(['confirmed', 'completed', 'matched', 'paid']);
const BOOKING_ACTIVE_STATUSES = new Set(['pending', 'confirmed', 'completed', 'matched', 'paid']);

function parseReportRange(req) {
  const now = new Date();
  let to = coerceDateValue(req?.query?.to) ?? now;
  let from = coerceDateValue(req?.query?.from);
  if (!from) {
    // Default to last 7 days
    from = new Date(to.getTime() - 6 * 24 * 60 * 60 * 1000);
  }
  if (from > to) {
    const swap = from;
    from = to;
    to = swap;
  }
  return { from, to };
}

function resolveReportFacilityId(req, staffUser) {
  // Staff must have a facilityId assigned
  const staffFacilityId = coerceObjectId(staffUser?.facilityId);
  const queryFacilityId = coerceObjectId(req?.query?.facilityId);

  // If query facilityId is provided, validate it matches the staff's assigned facility
  if (queryFacilityId) {
    if (!staffFacilityId || !queryFacilityId.equals(staffFacilityId)) {
      return { error: { status: 403, message: 'Không có quyền truy cập cơ sở này' } };
    }
    return { facilityId: queryFacilityId };
  }

  if (!staffFacilityId) {
    return { error: { status: 403, message: 'Nhân viên chưa được gán cơ sở' } };
  }

  return { facilityId: staffFacilityId };
}

app.get('/api/staff/reports/summary', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { facilityId, error } = resolveReportFacilityId(req, staffUser);
    if (error) return res.status(error.status).json({ error: error.message });

    const { from, to } = parseReportRange(req);
    const bookingMatch = {
      facilityId,
      deletedAt: { $exists: false },
      start: { $gte: from, $lte: to },
    };

    const revenueStatuses = Array.from(BOOKING_REVENUE_STATUSES);
    const amountExpr = { $ifNull: ['$total', { $ifNull: ['$pricingSnapshot.total', '$pricingSnapshot.subtotal'] }] };
    const topLimit = 5;

    const [report] = await db.collection('bookings').aggregate([
      { $match: bookingMatch },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
          amountForRevenue: amountExpr,
        },
      },
      {
        $facet: {
          totals: [
            {
              $group: {
                _id: null,
                bookingsTotal: { $sum: 1 },
                revenueTotal: {
                  $sum: {
                    $cond: [
                      { $in: ['$statusLower', revenueStatuses] },
                      '$amountForRevenue',
                      0,
                    ],
                  },
                },
                cancelledCount: {
                  $sum: { $cond: [{ $eq: ['$statusLower', 'cancelled'] }, 1, 0] },
                },
                pendingCount: {
                  $sum: { $cond: [{ $eq: ['$statusLower', 'pending'] }, 1, 0] },
                },
                confirmedCount: {
                  $sum: { $cond: [{ $eq: ['$statusLower', 'confirmed'] }, 1, 0] },
                },
              },
            },
          ],
          bookingsByStatus: [
            { $group: { _id: '$statusLower', count: { $sum: 1 } } },
            { $project: { _id: 0, status: { $ifNull: ['$_id', ''] }, count: 1 } },
          ],
          revenueBySport: [
            { $match: { $expr: { $in: ['$statusLower', revenueStatuses] } } },
            {
              $group: {
                _id: '$sportId',
                revenue: { $sum: '$amountForRevenue' },
                count: { $sum: 1 },
              },
            },
            { $lookup: { from: 'sports', localField: '_id', foreignField: '_id', as: 'sport' } },
            { $unwind: { path: '$sport', preserveNullAndEmptyArrays: true } },
            {
              $project: {
                _id: 0,
                sportId: { $cond: [{ $ifNull: ['$_id', false] }, { $toString: '$_id' }, null] },
                sportName: '$sport.name',
                revenue: { $ifNull: ['$revenue', 0] },
                count: 1,
              },
            },
          ],
          topCourts: [
            { $match: { $expr: { $in: ['$statusLower', revenueStatuses] } } },
            {
              $group: {
                _id: '$courtId',
                revenue: { $sum: '$amountForRevenue' },
                bookingsCount: { $sum: 1 },
              },
            },
            { $sort: { bookingsCount: -1, revenue: -1, _id: 1 } },
            { $limit: topLimit },
            { $lookup: { from: 'courts', localField: '_id', foreignField: '_id', as: 'court' } },
            { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
            { $lookup: { from: 'facilities', localField: 'court.facilityId', foreignField: '_id', as: 'facility' } },
            { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
            {
              $project: {
                _id: 0,
                courtId: { $cond: [{ $ifNull: ['$_id', false] }, { $toString: '$_id' }, null] },
                courtName: '$court.name',
                facilityName: '$facility.name',
                bookingsCount: 1,
                revenue: 1,
              },
            },
          ],
        },
      },
    ]).toArray();

    const totals = report?.totals?.[0] ?? {};
    const bookingsTotal = totals.bookingsTotal ?? 0;
    const revenueTotal = totals.revenueTotal ?? 0;
    const cancelRate = bookingsTotal > 0 ? (totals.cancelledCount ?? 0) / bookingsTotal : 0;
    const pendingBookingsCount = totals.pendingCount ?? 0;
    const confirmedBookingsCount = totals.confirmedCount ?? 0;

    // Get invoice stats
    const invoicePipeline = [
      {
        $lookup: {
          from: 'bookings',
          let: { bookingId: '$bookingId' },
          pipeline: [
            {
              $match: {
                $expr: { $eq: ['$_id', '$$bookingId'] },
                facilityId,
                deletedAt: { $exists: false },
                start: { $gte: from, $lte: to },
              },
            },
          ],
          as: 'booking',
        },
      },
      { $unwind: { path: '$booking', preserveNullAndEmptyArrays: false } },
      { $lookup: { from: 'payments', localField: '_id', foreignField: 'invoiceId', as: 'payments' } },
    ];

    const invoiceDocs = await db.collection('invoices').aggregate(invoicePipeline).toArray();
    const shapedInvoices = invoiceDocs.map((doc) => shapeStaffInvoice(doc)).filter(Boolean);
    const inactiveInvoiceStatuses = new Set(['void', 'cancelled', 'canceled', 'refunded']);
    const invoicesTotal = shapedInvoices.length;
    let unpaidInvoicesCount = 0;
    let unpaidAmountTotal = 0;
    for (const invoice of shapedInvoices) {
      const status = typeof invoice.status === 'string' ? invoice.status.trim().toLowerCase() : '';
      const outstanding = Number.isFinite(invoice.outstanding) ? invoice.outstanding : Math.max(0, (invoice.amount ?? 0) - (invoice.totalPaid ?? 0));
      if (inactiveInvoiceStatuses.has(status)) continue;
      if (outstanding > 0) {
        unpaidInvoicesCount += 1;
        unpaidAmountTotal += outstanding;
      }
    }

    // Cancellation analytics for summary
    const cancelReasonLabels = {
      customer_cancel: 'Khách hàng hủy đặt sân',
      staff_cancel: 'Nhân viên hủy/không duyệt đặt sân',
      auto_pending_timeout: 'Tự động hủy do quá thời gian chờ duyệt',
      court_unavailable: 'Sân không khả dụng',
      overlapped_booking: 'Hủy do sân đã được đặt trùng khung giờ',
      payment_failed: 'Thanh toán thất bại',
      not_enough_players_at_start: 'Hủy do không đủ người khi đến giờ bắt đầu',
      manual_cancel: 'Hủy thủ công',
      other: 'Lý do khác',
      unknown: 'Không rõ',
    };

    const [cancellationReport] = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          $or: [
            { cancelledAt: { $gte: from, $lte: to } },
            { start: { $gte: from, $lte: to }, status: 'cancelled' },
          ],
        },
      },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
          reasonCodeNorm: { $ifNull: ['$cancelReasonCode', 'unknown'] },
        },
      },
      { $match: { statusLower: 'cancelled' } },
      {
        $facet: {
          total: [{ $count: 'count' }],
          topReasons: [
            { $group: { _id: '$reasonCodeNorm', count: { $sum: 1 } } },
            { $sort: { count: -1 } },
            { $limit: 5 },
            { $project: { _id: 0, code: '$_id', count: 1 } },
          ],
          topCancelledCourts: [
            {
              $group: {
                _id: '$courtId',
                cancelledCount: { $sum: 1 },
              },
            },
            { $sort: { cancelledCount: -1 } },
            { $limit: 5 },
            { $lookup: { from: 'courts', localField: '_id', foreignField: '_id', as: 'court' } },
            { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
            {
              $project: {
                _id: 0,
                courtId: { $cond: [{ $ifNull: ['$_id', false] }, { $toString: '$_id' }, null] },
                courtName: { $ifNull: ['$court.name', 'Không rõ'] },
                cancelledCount: 1,
              },
            },
          ],
        },
      },
    ]).toArray();

    const cancelledBookings = cancellationReport?.total?.[0]?.count ?? (totals.cancelledCount ?? 0);

    // Add cancel rate per court
    const topCancelledCourts = (cancellationReport?.topCancelledCourts ?? []).map((court) => {
      const courtTotalBookings = report?.topCourts?.find((c) => c.courtId === court.courtId)?.bookingsCount ?? court.cancelledCount;
      const courtCancelRate = courtTotalBookings > 0 ? court.cancelledCount / courtTotalBookings : 0;
      return { ...court, cancelRate: courtCancelRate };
    });

    const topReasons = (cancellationReport?.topReasons ?? []).map((item) => ({
      code: item.code || 'unknown',
      text: cancelReasonLabels[item.code] ?? cancelReasonLabels.unknown,
      count: item.count ?? 0,
    }));

    // Get active courts (non-cancelled bookings with revenue)
    const topActiveCourts = (report?.topCourts ?? []).slice(0, 5).map((court) => ({
      courtId: court.courtId,
      courtName: court.courtName,
      bookingsCount: court.bookingsCount,
      revenue: court.revenue,
    }));

    res.json({
      range: { from: from.toISOString(), to: to.toISOString() },
      kpis: {
        revenueTotal,
        bookingsTotal,
        invoicesTotal,
        unpaidInvoicesCount,
        unpaidAmountTotal,
        cancelRate,
        pendingBookingsCount,
        confirmedBookingsCount,
      },
      breakdown: {
        bookingsByStatus: report?.bookingsByStatus ?? [],
        revenueBySport: report?.revenueBySport ?? [],
        topCourts: report?.topCourts ?? [],
      },
      cancellations: {
        cancelledBookings,
        cancelRate,
        topReasons,
        topCancelledCourts,
        topActiveCourts,
      },
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/reports/revenue-daily', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { facilityId, error } = resolveReportFacilityId(req, staffUser);
    if (error) return res.status(error.status).json({ error: error.message });

    const { from, to } = parseReportRange(req);
    const revenueStatuses = Array.from(BOOKING_REVENUE_STATUSES);
    const amountExpr = { $ifNull: ['$total', { $ifNull: ['$pricingSnapshot.total', '$pricingSnapshot.subtotal'] }] };

    const docs = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          start: { $gte: from, $lte: to },
        },
      },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
          amountForRevenue: amountExpr,
        },
      },
      { $match: { statusLower: { $in: revenueStatuses } } },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$start' } },
          revenue: { $sum: '$amountForRevenue' },
          bookingsCount: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
      { $project: { _id: 0, date: '$_id', revenue: { $ifNull: ['$revenue', 0] }, bookingsCount: 1 } },
    ]).toArray();

    res.json(docs);
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/reports/peak-hours', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { facilityId, error } = resolveReportFacilityId(req, staffUser);
    if (error) return res.status(error.status).json({ error: error.message });

    const { from, to } = parseReportRange(req);
    const activeStatuses = Array.from(BOOKING_ACTIVE_STATUSES);

    const docs = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          start: { $gte: from, $lte: to },
        },
      },
      { $addFields: { statusLower: { $toLower: { $ifNull: ['$status', ''] } } } },
      { $match: { statusLower: { $in: activeStatuses } } },
      {
        $group: {
          _id: { $hour: '$start' },
          bookingsCount: { $sum: 1 },
        },
      },
      { $sort: { _id: 1 } },
      { $project: { _id: 0, hour: '$_id', bookingsCount: 1 } },
    ]).toArray();

    res.json(docs);
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/reports/top-courts', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { facilityId, error } = resolveReportFacilityId(req, staffUser);
    if (error) return res.status(error.status).json({ error: error.message });

    const { from, to } = parseReportRange(req);
    const revenueStatuses = Array.from(BOOKING_REVENUE_STATUSES);
    const amountExpr = { $ifNull: ['$total', { $ifNull: ['$pricingSnapshot.total', '$pricingSnapshot.subtotal'] }] };
    const parsedLimit = Number.parseInt(req?.query?.limit, 10);
    const limit = Number.isFinite(parsedLimit) ? Math.min(Math.max(parsedLimit, 1), 20) : 5;

    const docs = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          start: { $gte: from, $lte: to },
        },
      },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
          amountForRevenue: amountExpr,
        },
      },
      { $match: { statusLower: { $in: revenueStatuses } } },
      {
        $group: {
          _id: '$courtId',
          revenue: { $sum: '$amountForRevenue' },
          bookingsCount: { $sum: 1 },
        },
      },
      { $sort: { bookingsCount: -1, revenue: -1, _id: 1 } },
      { $limit: limit },
      { $lookup: { from: 'courts', localField: '_id', foreignField: '_id', as: 'court' } },
      { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
      { $lookup: { from: 'facilities', localField: 'court.facilityId', foreignField: '_id', as: 'facility' } },
      { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
      {
        $project: {
          _id: 0,
          courtId: { $cond: [{ $ifNull: ['$_id', false] }, { $toString: '$_id' }, null] },
          courtName: '$court.name',
          facilityName: '$facility.name',
          bookingsCount: 1,
          revenue: 1,
        },
      },
    ]).toArray();

    res.json(docs);
  } catch (error) {
    next(error);
  }
});

// Cancellations analytics endpoint
app.get('/api/staff/reports/cancellations', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { facilityId, error } = resolveReportFacilityId(req, staffUser);
    if (error) return res.status(error.status).json({ error: error.message });

    const { from, to } = parseReportRange(req);

    // Cancellation reason code labels (Vietnamese)
    const cancelReasonLabels = {
      customer_cancel: 'Khách hàng hủy đặt sân',
      staff_cancel: 'Nhân viên hủy/không duyệt đặt sân',
      auto_pending_timeout: 'Tự động hủy do quá thời gian chờ duyệt',
      court_unavailable: 'Sân không khả dụng',
      overlapped_booking: 'Hủy do sân đã được đặt trùng khung giờ',
      payment_failed: 'Thanh toán thất bại',
      not_enough_players_at_start: 'Hủy do không đủ người khi đến giờ bắt đầu',
      manual_cancel: 'Hủy thủ công',
      other: 'Lý do khác',
      unknown: 'Không rõ',
    };

    // Aggregate bookings cancellations
    const bookingsCancelAgg = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          $or: [
            { cancelledAt: { $gte: from, $lte: to } },
            { start: { $gte: from, $lte: to }, status: 'cancelled' },
          ],
        },
      },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
          roleNorm: { $ifNull: [{ $toLower: '$cancelledByRole' }, 'unknown'] },
          reasonCodeNorm: { $ifNull: ['$cancelReasonCode', 'unknown'] },
        },
      },
      { $match: { statusLower: 'cancelled' } },
      {
        $facet: {
          total: [{ $count: 'count' }],
          byRole: [
            { $group: { _id: '$roleNorm', count: { $sum: 1 } } },
            { $project: { _id: 0, role: '$_id', count: 1 } },
            { $sort: { count: -1 } },
          ],
          byReason: [
            { $group: { _id: '$reasonCodeNorm', count: { $sum: 1 } } },
            { $project: { _id: 0, code: '$_id', count: 1 } },
            { $sort: { count: -1 } },
          ],
          byCourt: [
            {
              $group: {
                _id: '$courtId',
                cancelledCount: { $sum: 1 },
              },
            },
            { $lookup: { from: 'courts', localField: '_id', foreignField: '_id', as: 'court' } },
            { $unwind: { path: '$court', preserveNullAndEmptyArrays: true } },
            { $lookup: { from: 'facilities', localField: 'court.facilityId', foreignField: '_id', as: 'facility' } },
            { $unwind: { path: '$facility', preserveNullAndEmptyArrays: true } },
            {
              $project: {
                _id: 0,
                courtId: { $cond: [{ $ifNull: ['$_id', false] }, { $toString: '$_id' }, null] },
                courtName: { $ifNull: ['$court.name', 'Không rõ'] },
                facilityName: { $ifNull: ['$facility.name', ''] },
                cancelledCount: 1,
              },
            },
            { $sort: { cancelledCount: -1, courtName: 1 } },
          ],
        },
      },
    ]).toArray();

    const bookingsReport = bookingsCancelAgg[0] ?? {};
    const cancelledBookings = bookingsReport.total?.[0]?.count ?? 0;

    // Get total bookings for cancel rate calculation per court
    const totalBookingsPerCourt = await db.collection('bookings').aggregate([
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          start: { $gte: from, $lte: to },
        },
      },
      {
        $group: {
          _id: '$courtId',
          totalBookings: { $sum: 1 },
        },
      },
    ]).toArray();
    const totalBookingsMap = new Map(totalBookingsPerCourt.map((d) => [d._id?.toHexString?.() ?? String(d._id), d.totalBookings]));

    // Aggregate match requests cancellations
    const matchRequestsCancelAgg = await db.collection('match_requests').aggregate([
      {
        $match: {
          facilityId,
          $or: [
            { cancelledAt: { $gte: from, $lte: to } },
            { desiredStart: { $gte: from, $lte: to }, status: 'cancelled' },
          ],
        },
      },
      {
        $addFields: {
          statusLower: { $toLower: { $ifNull: ['$status', ''] } },
        },
      },
      { $match: { statusLower: 'cancelled' } },
      { $count: 'count' },
    ]).toArray();

    const cancelledMatchRequests = matchRequestsCancelAgg[0]?.count ?? 0;

    // Format byRole
    const byRole = (bookingsReport.byRole ?? []).map((item) => ({
      role: item.role || 'unknown',
      count: item.count ?? 0,
    }));

    // Format byReason with Vietnamese labels
    const byReason = (bookingsReport.byReason ?? []).map((item) => ({
      code: item.code || 'unknown',
      text: cancelReasonLabels[item.code] ?? cancelReasonLabels.unknown,
      count: item.count ?? 0,
    }));

    // Format byCourt with cancel rates
    const byCourt = (bookingsReport.byCourt ?? []).map((item) => {
      const courtKey = item.courtId;
      const totalBookings = totalBookingsMap.get(courtKey) ?? item.cancelledCount;
      const cancelRate = totalBookings > 0 ? item.cancelledCount / totalBookings : 0;
      return {
        ...item,
        totalBookings,
        cancelRate,
      };
    });

    res.json({
      range: { from: from.toISOString(), to: to.toISOString() },
      totals: {
        cancelledBookings,
        cancelledMatchRequests,
      },
      byRole,
      byReason,
      byCourt,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/profile', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });
    const facilityDoc = staffUser.facilityId ? await fetchFacilityById(staffUser.facilityId) : null;
    res.json(shapeStaffProfileResponse(staffUser, facilityDoc));
  } catch (error) {
    next(error);
  }
});

app.put('/api/staff/profile', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const body = req.body || {};
    const $set = {};
    const $unset = {};

    const handleField = (field, maxLength = 120) => {
      if (body[field] === undefined) return;
      const value = typeof body[field] === 'string' ? body[field].trim() : '';
      if (value.length) {
        $set[field] = value.substring(0, maxLength);
        delete $unset[field];
      } else {
        $unset[field] = '';
        delete $set[field];
      }
    };

    handleField('name', 120);
    handleField('email', 160);
    handleField('phone', 40);

    if (!Object.keys($set).length && !Object.keys($unset).length) {
      return res.status(400).json({ error: 'Không có thay đổi nào được gửi lên' });
    }

    $set.updatedAt = new Date();

    const updateDoc = {};
    if (Object.keys($set).length) updateDoc.$set = $set;
    if (Object.keys($unset).length) updateDoc.$unset = $unset;

    let result = await db.collection('users').findOneAndUpdate(
      { _id: staffUser._id, role: 'staff' },
      updateDoc,
      { returnDocument: ReturnDocument.AFTER },
    );

    // Fallback for legacy accounts missing role flag
    if (!result.value) {
      result = await db.collection('users').findOneAndUpdate(
        { _id: staffUser._id, status: { $ne: 'deleted' } },
        updateDoc,
        { returnDocument: ReturnDocument.AFTER },
      );
    }

    if (!result.value) {
      return res.status(404).json({ error: 'Staff account not found' });
    }

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.profile-update',
      resource: 'user',
      resourceId: staffUser._id,
      changes: sanitizeAuditData({ $set, $unset }),
    });

    req.staffUser = result.value;
    const facilityDoc = result.value.facilityId ? await fetchFacilityById(result.value.facilityId) : null;
    res.json(shapeStaffProfileResponse(result.value, facilityDoc));
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/profile/change-password', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { currentPassword, newPassword } = req.body || {};
    if (typeof newPassword !== 'string' || newPassword.length < 6) {
      return res.status(400).json({ error: 'Mật khẩu mới phải có ít nhất 6 ký tự' });
    }
    if (typeof currentPassword !== 'string' || !currentPassword.length) {
      return res.status(400).json({ error: 'Vui lòng nhập mật khẩu hiện tại' });
    }

    const currentHash = staffUser.passwordHash;
    if (!currentHash) {
      return res.status(400).json({ error: 'Tài khoản không hỗ trợ đổi mật khẩu' });
    }

    const matches = await bcrypt.compare(currentPassword, currentHash);
    if (!matches) {
      return res.status(403).json({ error: 'Mật khẩu hiện tại không đúng' });
    }
    if (currentPassword === newPassword) {
      return res.status(400).json({ error: 'Mật khẩu mới phải khác mật khẩu hiện tại' });
    }

    const passwordHash = await bcrypt.hash(String(newPassword), 10);
    await db.collection('users').updateOne(
      { _id: staffUser._id },
      { $set: { passwordHash, passwordChangedAt: new Date(), updatedAt: new Date() } },
    );

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.change-password',
      resource: 'user',
      resourceId: staffUser._id,
      message: 'Staff user updated password',
    });

    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/customers', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) {
      return res.status(403).json({ error: 'Staff user is not assigned to any facility' });
    }

    const parsedLimit = Number.parseInt(req.query?.limit, 10);
    const limit = Number.isFinite(parsedLimit) ? Math.min(Math.max(parsedLimit, 1), 200) : 50;

    const pipeline = [
      {
        $match: {
          facilityId,
          deletedAt: { $exists: false },
          customerId: { $exists: true, $ne: null },
        },
      },
      {
        $group: {
          _id: '$customerId',
          lastBookingAt: { $max: '$start' },
          totalBookings: { $sum: 1 },
          bookings: {
            $push: {
              _id: '$_id',
              start: '$start',
              end: '$end',
              status: '$status',
              total: {
                $ifNull: [
                  '$total',
                  { $ifNull: ['$pricingSnapshot.total', 0] },
                ],
              },
              currency: {
                $ifNull: [
                  '$currency',
                  { $ifNull: ['$pricingSnapshot.currency', 'VND'] },
                ],
              },
            },
          },
        },
      },
      {
        $project: {
          lastBookingAt: 1,
          totalBookings: 1,
          bookings: { $slice: ['$bookings', 5] },
        },
      },
      { $sort: { lastBookingAt: -1 } },
      { $limit: limit },
      { $lookup: { from: 'users', localField: '_id', foreignField: '_id', as: 'customer' } },
      { $unwind: { path: '$customer', preserveNullAndEmptyArrays: true } },
    ];

    const docs = await db.collection('bookings').aggregate(pipeline).toArray();
    const customers = docs.map((doc) => {
      const contact = shapeStaffCustomer(doc.customer) || {
        _id: normalizeIdString(doc._id),
      };
      const bookings = Array.isArray(doc.bookings)
        ? doc.bookings.map((booking) => cleanObject({
          _id: normalizeIdString(booking._id),
          id: normalizeIdString(booking._id),
          start: booking.start ?? null,
          end: booking.end ?? null,
          status: booking.status ?? null,
          total: normalizePaymentAmount(booking.total ?? 0),
          currency: typeof booking.currency === 'string' ? booking.currency : 'VND',
        }))
        : [];
      return cleanObject({
        id: contact._id,
        _id: contact._id,
        name: contact.name ?? contact.email ?? contact.phone ?? 'Khách hàng',
        email: contact.email ?? null,
        phone: contact.phone ?? null,
        lastBookingAt: doc.lastBookingAt ?? null,
        totalBookings: doc.totalBookings ?? bookings.length,
        bookings,
      });
    });

    res.json({ customers });
  } catch (error) {
    next(error);
  }
});

app.post('/api/staff/customers/:id/messages', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const customerId = coerceObjectId(req.params.id);
    if (!customerId) return res.status(404).json({ error: 'Customer not found' });

    const customer = await db.collection('users').findOne({ _id: customerId });
    if (!customer) return res.status(404).json({ error: 'Customer not found' });

    const message = typeof req.body?.message === 'string' ? req.body.message.trim() : '';
    if (!message.length) return res.status(400).json({ error: 'message is required' });

    await createNotifications({
      userIds: [customerId],
      title: 'Tin nhắn từ nhân viên',
      message,
      data: { type: 'staff-message', staffId: normalizeIdString(staffUser._id) },
    });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.customer.message',
      resource: 'user',
      resourceId: customerId,
      payload: { message },
    });

    res.status(201).json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.get('/api/staff/notifications', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { status, limit } = req.query || {};
    const { orClauses } = buildStaffNotificationClauses(staffUser);
    const filter = { $or: orClauses };
    if (status) {
      const normalized = String(status).trim().toLowerCase();
      if (normalized === 'unread' || normalized === 'read') {
        filter.status = normalized;
      }
    }
    let limitValue = Number.parseInt(String(limit ?? ''), 10);
    if (!Number.isFinite(limitValue) || limitValue <= 0) limitValue = 50;
    limitValue = Math.min(limitValue, 200);

    const docs = await db.collection('notifications')
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(limitValue)
      .toArray();
    res.json(docs.map((doc) => shapeNotification(doc)));
  } catch (e) { next(e); }
});

app.post('/api/staff/notifications/:id/read', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });
    const candidates = buildIdCandidates(req.params.id);
    if (!candidates.length) return res.status(404).json({ error: 'Không tìm thấy thông báo' });

    const { orClauses } = buildStaffNotificationClauses(staffUser);
    const now = new Date();
    const updateDoc = { status: 'read', readAt: now };
    const query = { _id: { $in: candidates }, $or: orClauses };
    const result = await db.collection('notifications').findOneAndUpdate(
      query,
      { $set: updateDoc },
      { returnDocument: 'after' },
    );

    if (!result.value) {
      const debugDoc = await db.collection('notifications').findOne({ _id: { $in: candidates } });
      if (debugDoc && notificationMatchesStaff(debugDoc, staffUser)) {
        if (debugDoc.status !== 'read' || !(debugDoc.readAt instanceof Date)) {
          const refreshed = await db.collection('notifications').findOneAndUpdate(
            { _id: debugDoc._id },
            { $set: updateDoc },
            { returnDocument: 'after' },
          );
          const resolved = refreshed.value ?? { ...debugDoc, status: 'read', readAt: now };
          return res.json(shapeNotification(resolved));
        }
        return res.json(shapeNotification(debugDoc));
      }
      console.warn('[staff][notifications] mark-read miss', { candidates, orClauses, query, debugDoc });
      return res.status(404).json({ error: 'Không tìm thấy thông báo' });
    }
    res.json(shapeNotification(result.value));
  } catch (e) { next(e); }
});

app.post('/api/staff/notifications/mark-all-read', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const { orClauses } = buildStaffNotificationClauses(staffUser);

    const filter = {
      $or: orClauses,
      status: { $ne: 'read' },
    };

    const result = await db.collection('notifications').updateMany(
      filter,
      { $set: { status: 'read', readAt: new Date() } },
    );

    res.json({ updated: result.modifiedCount ?? 0 });
  } catch (e) { next(e); }
});

// --- Admin Bookings ---
// List bookings with optional filters
app.get('/api/admin/bookings', async (req, res, next) => {
  try {
    const { facilityId, courtId, sportId, userId, status, from, to, includeDeleted } = req.query || {};
    const filter = (includeDeleted === 'true') ? {} : { deletedAt: { $exists: false } };
    if (facilityId) filter.facilityId = new ObjectId(String(facilityId));
    if (courtId) filter.courtId = new ObjectId(String(courtId));
    if (sportId) filter.sportId = new ObjectId(String(sportId));
    if (userId) filter.customerId = new ObjectId(String(userId));
    if (status) filter.status = String(status);
    if (from || to) {
      filter.start = {};
      if (from) filter.start.$gte = new Date(String(from));
      if (to) filter.start.$lte = new Date(String(to));
    }
    const list = await db.collection('bookings').find(filter).sort({ start: -1 }).limit(1000).toArray();
    res.json(list);
  } catch (e) { next(e); }
});

// Update a booking (recompute price, check conflicts)
app.put('/api/admin/bookings/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const current = await db.collection('bookings').findOne(filter);
    if (!current) return res.status(404).json({ error: 'Not found' });

    // Prepare next state
    const next = { ...current };
    const body = req.body || {};
    if (body.customerId) next.customerId = new ObjectId(String(body.customerId));
    if (body.facilityId) next.facilityId = new ObjectId(String(body.facilityId));
    if (body.courtId) next.courtId = new ObjectId(String(body.courtId));
    if (body.sportId) next.sportId = new ObjectId(String(body.sportId));
    if (body.currency) next.currency = String(body.currency);
    if (body.participants !== undefined) {
      const arr = Array.isArray(body.participants) ? body.participants : [];
      next.participants = arr
        .map((x) => String(x).trim())
        .filter((x) => x.length > 0 && ObjectId.isValid(x))
        .map((x) => new ObjectId(x));
    }
    let clearVoucher = false;
    if (body.voucherId !== undefined) {
      const v = String(body.voucherId).trim();
      if (v.length === 0) {
        delete next.voucherId;
        clearVoucher = true;
      } else {
        next.voucherId = new ObjectId(v);
      }
    }
    if (body.status) next.status = String(body.status);
    if (body.start) next.start = new Date(String(body.start));
    if (body.end) next.end = new Date(String(body.end));

    // Validate timeframe
    if (!(next.start < next.end)) return res.status(400).json({ error: 'start must be < end' });

    // Conflict check (ignore this booking itself)
    const overlapExpr = { $or: [ { start: { $lt: next.end }, end: { $gt: next.start } } ] };
    const conflict = await db.collection('bookings').findOne({
      _id: { $ne: current._id },
      courtId: next.courtId,
      ...overlapExpr,
      status: { $in: ['pending','confirmed','completed'] },
    });
    const maintenance = await db.collection('maintenance').findOne({
      courtId: next.courtId,
      ...overlapExpr,
    });
    if (conflict || maintenance) return res.status(409).json({ error: 'Court not available for the requested time' });

    // Recompute price
    const user = await db.collection('users').findOne({ _id: next.customerId });
    const quote = await quotePrice({ db, facilityId: String(next.facilityId), sportId: String(next.sportId), courtId: String(next.courtId), start: next.start, end: next.end, currency: next.currency || 'VND', user });

    const update = {
      customerId: next.customerId,
      facilityId: next.facilityId,
      courtId: next.courtId,
      sportId: next.sportId,
      start: next.start,
      end: next.end,
      currency: next.currency || 'VND',
      participants: Array.isArray(next.participants) ? next.participants : [],
      pricingSnapshot: quote,
      status: next.status || current.status,
      updatedAt: new Date(),
    };
    if (next.voucherId) {
      update.voucherId = next.voucherId;
    } else {
      delete update.voucherId;
    }
    const updateDoc = { $set: update };
    if (clearVoucher) {
      updateDoc.$unset = { voucherId: '' };
    }
    const r = await db.collection('bookings').findOneAndUpdate(filter, updateDoc, { returnDocument: 'after' });
    await recordAudit(req, {
      action: 'booking.update',
      resource: 'booking',
      resourceId: r.insertedId,
      payload: {
        facilityId: payload.facilityId,
        courtId: payload.courtId,
        sportId: payload.sportId,
        customerId: payload.customerId,
        start: payload.start,
        end: payload.end,
        status: payload.status,
      },
    });
    res.json(r.value);
  } catch (e) { next(e); }
});

// Delete (soft delete) a booking
app.delete('/api/admin/bookings/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const existing = await db.collection('bookings').findOne(filter);
    if (!existing) return res.status(404).json({ error: 'Not found' });

    const update = {
      status: 'cancelled',
      updatedAt: new Date(),
      deletedAt: new Date(),
      cancelledReason: 'admin_deleted',
    };

    await db.collection('bookings').updateOne({ _id: existing._id }, { $set: update });
    await recordAudit(req, {
      action: 'delete.hard',
      resource: 'user',
      resourceId: existing._id,
      payload: { id: idParam },
      changes: update,
    });
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// --- Admin APIs (no auth for demo; protect in production) ---
// SPORTS CRUD
app.get('/api/admin/sports', async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const filter = includeInactive ? {} : { active: { $ne: false } };
    const items = await db.collection('sports').find(filter).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

app.post('/api/admin/sports', async (req, res, next) => { 
  try {
    const { name, code, teamSize, active = true } = req.body || {};
    if (!name || !code || !teamSize) return res.status(400).json({ error: 'name, code, teamSize required' });
    const doc = { name, code, teamSize: Number(teamSize), active: !!active };
    const r = await db.collection('sports').insertOne(doc);
    await recordAudit(req, {
      action: 'create',
      resource: 'sport',
      resourceId: r.insertedId,
      payload: req.body,
      changes: doc,
    });
    res.status(201).json({ _id: r.insertedId, ...doc });
  } catch (e) { next(e); }
});

app.put('/api/admin/sports/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const $set = {};
    for (const k of ['name','code','teamSize','active']) if (req.body?.[k] !== undefined) $set[k] = req.body[k];
    if ('teamSize' in $set) $set.teamSize = Number($set.teamSize);
    const r = await db.collection('sports').findOneAndUpdate(filter, { $set }, { returnDocument: 'after' });
    if (!r.value) return res.status(404).json({ error: 'Not found' });
    await recordAudit(req, {
      action: 'update',
      resource: 'sport',
      resourceId: r.value._id,
      payload: req.body,
      changes: r.value,
    });
    res.json(r.value);
  } catch (e) { next(e); }
});

app.delete('/api/admin/sports/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const r = await db.collection('sports').deleteOne(filter);
    if (!r.deletedCount) return res.status(404).json({ error: 'Not found' });
    await recordAudit(req, {
      action: 'delete',
      resource: 'sport',
      resourceId: idParam,
      payload: { id: idParam },
    });
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// COURTS management
app.get('/api/admin/facilities/:id/courts', async (req, res, next) => {
  try {
    const facilityId = new ObjectId(req.params.id);
    const items = await db.collection('courts').find({ facilityId, status: { $ne: 'deleted' } }).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

app.post('/api/admin/courts', async (req, res, next) => {
  try {
    const { facilityId, sportId, name, code, status = 'active' } = req.body || {};
    if (!facilityId || !sportId || !name) {
      return res.status(400).json({ error: 'facilityId, sportId, name required' });
    }
    const statusValue = String(status);
    if (!COURT_ALLOWED_STATUSES.has(statusValue)) {
      return res.status(400).json({ error: 'Invalid court status' });
    }

    const sport = await fetchSportById(sportId);
    if (!sport) return res.status(404).json({ error: 'Sport not found' });

    const facility = await fetchFacilityById(facilityId);
    if (!facility) return res.status(404).json({ error: 'Facility not found' });

    const actorId = getAppUserObjectId(req) ?? SYSTEM_ACTOR_ID;
    const doc = {
      facilityId: facility._id,
      sportId: sport._id,
      name: String(name).trim(),
      status: statusValue,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: actorId,
    };
    if (code !== undefined) {
      const trimmed = String(code).trim();
      if (trimmed) doc.code = trimmed;
    }

    const insert = await db.collection('courts').insertOne(doc);
    const saved = await db.collection('courts').findOne({ _id: insert.insertedId });

    await recordAudit(req, {
      action: 'court.create',
      resource: 'court',
      resourceId: insert.insertedId,
      payload: req.body,
      changes: saved,
    });

    res.status(201).json(saved);
  } catch (e) { next(e); }
});

app.put('/api/admin/courts/:id', async (req, res, next) => {
  try {
    const { id } = req.params;
    const court = await fetchCourtById(id);
    if (!court) {
      console.warn('[admin.courts:update] court not found', { requestedId: id });
      return res.status(404).json({ error: 'Not found', reason: 'court_missing' });
    }

    const { name, code, sportId, status, facilityId } = req.body || {};
    const $set = { updatedAt: new Date() };
    const $unset = {};

    if (name !== undefined) {
      const trimmed = String(name).trim();
      if (!trimmed) return res.status(400).json({ error: 'name cannot be empty' });
      $set.name = trimmed;
    }

    if (code !== undefined) {
      const trimmed = String(code).trim();
      if (trimmed) {
        $set.code = trimmed;
      } else {
        $unset.code = '';
      }
    }

    if (sportId !== undefined) {
      const sport = await fetchSportById(sportId);
      if (!sport) {
        console.warn('[admin.courts:update] sport not found', {
          courtId: court._id,
          requestedSportId: sportId,
        });
        return res.status(404).json({ error: 'Sport not found' });
      }
      $set.sportId = sport._id;
    }

    if (facilityId !== undefined) {
      const facility = await fetchFacilityById(facilityId);
      if (!facility) {
        console.warn('[admin.courts:update] facility not found', {
          courtId: court._id,
          requestedFacilityId: facilityId,
        });
        return res.status(404).json({ error: 'Facility not found' });
      }
      $set.facilityId = facility._id;
    }

    if (status !== undefined) {
      const statusValue = String(status);
      if (!COURT_ALLOWED_STATUSES.has(statusValue)) {
        return res.status(400).json({ error: 'Invalid court status' });
      }
      $set.status = statusValue;
    }

    const hasMeaningfulSet = Object.keys($set).filter((k) => k !== 'updatedAt').length > 0;
    if (!hasMeaningfulSet && Object.keys($unset).length === 0) {
      return res.status(400).json({ error: 'No updates provided' });
    }

    const updateOps = {};
    if (Object.keys($set).length) updateOps.$set = $set;
    if (Object.keys($unset).length) updateOps.$unset = $unset;

    const filter = { _id: court._id };
    const updateResult = await db.collection('courts').findOneAndUpdate(
      filter,
      updateOps,
      { returnDocument: ReturnDocument.AFTER }
    );

    const updatedCourt = updateResult.value;
    if (!updatedCourt) {
      console.warn('[admin.courts:update] update returned empty result', {
        courtId: court._id,
        updates: updateOps,
      });
      return res.status(404).json({ error: 'Not found', reason: 'update_failed' });
    }

    await recordAudit(req, {
      action: 'court.update',
      resource: 'court',
      resourceId: updatedCourt._id,
      payload: req.body,
      changes: updatedCourt,
    });

    res.json(updatedCourt);
  } catch (e) { next(e); }
});

app.delete('/api/staff/courts/:id', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const court = await fetchCourtById(req.params.id);
    if (!court) return res.status(404).json({ error: 'Not found' });
    if (String(court.facilityId) !== String(staffUser.facilityId)) {
      return res.status(403).json({ error: 'Not authorized for this court' });
    }

    const result = await db.collection('courts').findOneAndUpdate(
      { _id: court._id },
      { $set: { status: 'deleted', updatedAt: new Date() } },
      { returnDocument: 'after' }
    );

    if (!result.value) return res.status(404).json({ error: 'Not found' });

    await recordAudit(req, {
      action: 'court.delete',
      resource: 'court',
      resourceId: court._id,
      payload: { id: req.params.id },
      changes: result.value,
    });

    res.json({ ok: true });
  } catch (e) { next(e); }
});

app.post('/api/staff/courts', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId) return res.status(403).json({ error: 'Staff user is not assigned to any facility' });

    const { sportId, name, code, status = 'active' } = req.body || {};
    if (!sportId || !name) return res.status(400).json({ error: 'sportId and name are required' });
    if (!COURT_ALLOWED_STATUSES.has(String(status))) {
      return res.status(400).json({ error: 'Invalid court status' });
    }

    const sport = await fetchSportById(sportId);
    if (!sport) return res.status(404).json({ error: 'Sport not found' });

    const doc = {
      facilityId,
      sportId: sport._id,
      name: String(name).trim(),
      status: String(status),
      createdAt: new Date(),
      updatedAt: new Date(),
      createdByStaffId: staffUser._id,
    };
    if (code !== undefined) {
      const trimmed = String(code).trim();
      if (trimmed.length) doc.code = trimmed;
    }

    const insert = await db.collection('courts').insertOne(doc);
    const saved = await db.collection('courts').findOne({ _id: insert.insertedId });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.court.create',
      resource: 'court',
      resourceId: insert.insertedId,
      payload: req.body,
      changes: saved,
    });

    res.status(201).json(saved);
  } catch (e) { next(e); }
});

app.put('/api/staff/courts/:id', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const court = await fetchCourtById(req.params.id);
    if (!court) return res.status(404).json({ error: 'Not found' });

    const facilityId = coerceObjectId(staffUser.facilityId);
    if (!facilityId || String(court.facilityId) !== String(facilityId)) {
      return res.status(403).json({ error: 'Not authorized for this court' });
    }

    const { name, code, sportId, status } = req.body || {};
    const $set = { updatedAt: new Date() };
    const $unset = {};

    if (name !== undefined) {
      const trimmed = String(name).trim();
      if (!trimmed.length) return res.status(400).json({ error: 'name cannot be empty' });
      $set.name = trimmed;
    }

    if (code !== undefined) {
      const trimmed = String(code).trim();
      if (trimmed.length) {
        $set.code = trimmed;
      } else {
        $unset.code = '';
      }
    }

    if (sportId !== undefined) {
      const sport = await fetchSportById(sportId);
      if (!sport) return res.status(404).json({ error: 'Sport not found' });
      $set.sportId = sport._id;
    }

    if (status !== undefined) {
      const statusValue = String(status);
      if (!COURT_ALLOWED_STATUSES.has(statusValue)) {
        return res.status(400).json({ error: 'Invalid court status' });
      }
      $set.status = statusValue;
    }

    const updateOps = {};
    if (Object.keys($set).length) updateOps.$set = $set;
    if (Object.keys($unset).length) updateOps.$unset = $unset;

    if (!Object.keys(updateOps).length) {
      return res.status(400).json({ error: 'No updates provided' });
    }

    const result = await db.collection('courts').findOneAndUpdate(
      { _id: court._id },
      updateOps,
      { returnDocument: ReturnDocument.AFTER },
    );

    if (!result.value) return res.status(404).json({ error: 'Not found' });

    await recordAudit(req, {
      actorId: staffUser._id,
      action: 'staff.court.update',
      resource: 'court',
      resourceId: court._id,
      payload: req.body,
      changes: result.value,
    });

    res.json(result.value);
  } catch (e) { next(e); }
});

app.patch('/api/admin/courts/:id/status', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const { status } = req.body || {};
    if (!status) return res.status(400).json({ error: 'status required' });
    const r = await db.collection('courts').findOneAndUpdate(filter, { $set: { status } }, { returnDocument: 'after' });
    if (!r.value) return res.status(404).json({ error: 'Not found' });
    await recordAudit(req, {
      action: 'update-status',
      resource: 'court',
      resourceId: r.value._id,
      payload: req.body,
      changes: r.value,
    });
    res.json(r.value);
  } catch (e) { next(e); }
});

// Soft delete court (mark status='deleted')
app.delete('/api/admin/courts/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const candidates = [];
    if (ObjectId.isValid(idParam)) candidates.push({ _id: new ObjectId(idParam) });
    candidates.push({ _id: idParam });

    // Try sequentially to improve diagnosability across legacy IDs
    for (const f of candidates) {
      const r = await db.collection('courts').findOneAndUpdate(
        f,
        { $set: { status: 'deleted', updatedAt: new Date() } },
        { returnDocument: 'after' }
      );
      if (r.value) {
        await recordAudit(req, {
          action: 'delete',
          resource: 'court',
          resourceId: r.value._id,
          payload: { id: idParam },
          changes: { status: 'deleted' },
        });
        return res.json({ ok: true });
      }
    }
    return res.status(404).json({ error: 'Not found' });
  } catch (e) { next(e); }
});

// PRICE PROFILES
app.get('/api/admin/price-profiles', async (req, res, next) => {
  try {
    const { facilityId, sportId, courtId } = req.query;
    const filter = {};
    if (facilityId) filter.facilityId = new ObjectId(facilityId);
    if (sportId) filter.sportId = new ObjectId(sportId);
    if (courtId) filter.courtId = new ObjectId(courtId);
    const items = await db.collection('price_profiles').find(filter).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

app.get('/api/staff/price-profiles', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const facilityCandidates = buildIdCandidates(staffUser.facilityId);
    if (!facilityCandidates.length) {
      return res.status(403).json({ error: 'No facility assigned' });
    }

    const filter = {
      facilityId: facilityCandidates.length === 1
        ? facilityCandidates[0]
        : { $in: facilityCandidates },
    };

    const { facilityId, sportId, courtId } = req.query || {};
    if (facilityId) {
      const requestedSet = buildComparableIdSet(facilityId);
      const staffFacilitySet = buildComparableIdSet(staffUser.facilityId);
      let overlap = false;
      for (const id of requestedSet) {
        if (staffFacilitySet.has(id)) {
          overlap = true;
          break;
        }
      }
      if (!overlap) {
        return res.status(403).json({ error: 'Không có quyền cập nhật bảng giá cho cơ sở này' });
      }
    }

    const sportCandidates = sportId ? buildIdCandidates(sportId) : [];
    if (sportCandidates.length === 1) {
      filter.sportId = sportCandidates[0];
    } else if (sportCandidates.length > 1) {
      filter.sportId = { $in: sportCandidates };
    }

    const courtCandidates = courtId ? buildIdCandidates(courtId) : [];
    if (courtCandidates.length === 1) {
      filter.courtId = courtCandidates[0];
    } else if (courtCandidates.length > 1) {
      filter.courtId = { $in: courtCandidates };
    }

    const items = await db.collection('price_profiles')
      .find(filter)
      .sort({ name: 1 })
      .toArray();
    res.json(items);
  } catch (e) { next(e); }
});

// FACILITIES management (minimal)
app.get('/api/admin/facilities', async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const filter = includeInactive ? {} : { active: { $ne: false } };
    const items = await db.collection('facilities').find(filter).sort({ name: 1 }).toArray();
    res.json(items);
  } catch (e) { next(e); }
});

app.post('/api/admin/facilities', async (req, res, next) => {
  try {
    const { name, timeZone = 'Asia/Ho_Chi_Minh', active = true, address } = req.body || {};
    if (!name) return res.status(400).json({ error: 'name required' });
    const doc = { name, timeZone, active, address: {} };
    if (address && typeof address === 'object') {
      // Whitelist simple string fields for address
      const safe = {};
      for (const k of ['line1','ward','district','city','province','country','postalCode']) {
        if (address[k] !== undefined) safe[k] = String(address[k]);
      }
      // Optional coordinates if provided
      if (address.lat !== undefined) safe.lat = Number(address.lat);
      if (address.lng !== undefined) safe.lng = Number(address.lng);
      doc.address = safe;
    }
    const r = await db.collection('facilities').insertOne(doc);
    await recordAudit(req, {
      action: 'create',
      resource: 'facility',
      resourceId: r.insertedId,
      payload: req.body,
      changes: doc,
    });
    res.status(201).json({ _id: r.insertedId, ...doc });
  } catch (e) { next(e); }
});

// Update facility
app.put('/api/admin/facilities/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const $set = {};
    const $unset = {};
    if (typeof req.body.name === 'string') $set.name = req.body.name;
    if (typeof req.body.timeZone === 'string') $set.timeZone = req.body.timeZone;
    if (req.body.active !== undefined) $set.active = !!req.body.active;
    if (req.body.address !== undefined) {
      const addr = req.body.address;
      if (addr && typeof addr === 'object') {
        const safe = {};
        for (const k of ['line1','ward','district','city','province','country','postalCode']) {
          if (addr[k] !== undefined) safe[k] = String(addr[k]);
        }
        if (addr.lat !== undefined) safe.lat = Number(addr.lat);
        if (addr.lng !== undefined) safe.lng = Number(addr.lng);
        $set.address = safe;
      } else {
        $unset.address = '';
      }
    }
    const r = await db.collection('facilities').findOneAndUpdate(filter, { $set, $unset }, { returnDocument: 'after' });
    if (!r.value) return res.status(404).json({ error: 'Not found' });
    await recordAudit(req, {
      action: 'update',
      resource: 'facility',
      resourceId: r.value._id,
      payload: req.body,
      changes: r.value,
    });
    res.json(r.value);
  } catch (e) { next(e); }
});

app.post('/api/admin/price-profiles', async (req, res, next) => {
  try {
    const body = req.body || {};
    const doc = {
      ...body,
      facilityId: body.facilityId ? new ObjectId(body.facilityId) : undefined,
      sportId: body.sportId ? new ObjectId(body.sportId) : undefined,
      courtId: body.courtId ? new ObjectId(body.courtId) : undefined,
    };
    const r = await db.collection('price_profiles').insertOne(doc);
    await recordAudit(req, {
      action: 'create',
      resource: 'price_profile',
      resourceId: r.insertedId,
      payload: req.body,
      changes: doc,
    });
    res.status(201).json({ _id: r.insertedId, ...doc });
  } catch (e) { next(e); }
});

app.put('/api/admin/price-profiles/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const filter = ObjectId.isValid(idParam)
      ? { $or: [ { _id: new ObjectId(idParam) }, { _id: idParam } ] }
      : { _id: idParam };
    const body = { ...req.body };
    if (body.facilityId) body.facilityId = new ObjectId(body.facilityId);
    if (body.sportId) body.sportId = new ObjectId(body.sportId);
    if (body.courtId) body.courtId = new ObjectId(body.courtId);
    const r = await db.collection('price_profiles').findOneAndUpdate(filter, { $set: body }, { returnDocument: 'after' });
    if (!r.value) return res.status(404).json({ error: 'Not found' });
    await recordAudit(req, {
      action: 'update',
      resource: 'price_profile',
      resourceId: r.value._id,
      payload: req.body,
      changes: r.value,
    });
    res.json(r.value);
  } catch (e) { next(e); }
});

app.post('/api/admin/price-profiles/upsert', async (req, res, next) => {
  try {
    const body = req.body || {};
    console.log('[upsert] Received body:', JSON.stringify(body, null, 2));
    
    // Build key for upsert (ObjectIds)
    const key = {};
    if (body.facilityId) key.facilityId = new ObjectId(body.facilityId);
    if (body.sportId) key.sportId = new ObjectId(body.sportId);
    if (body.courtId) key.courtId = new ObjectId(body.courtId);
    console.log('[upsert] Key:', key);

    // Sanitize rules
    const sanitizeRule = (r) => {
      const rr = { ...r };
      if (Array.isArray(rr.daysOfWeek)) {
        rr.daysOfWeek = rr.daysOfWeek.map((d) => Number(d)).filter((d) => d >= 0 && d <= 6);
      }
      if (rr.value !== undefined) rr.value = Number(rr.value);
      if (rr.rateType !== 'multiplier' && rr.rateType !== 'fixed') rr.rateType = 'multiplier';
      if (typeof rr.startTime !== 'string') rr.startTime = '00:00';
      if (typeof rr.endTime !== 'string') rr.endTime = '24:00';
      return rr;
    };

    // Build sanitized doc for $set – only include defined fields
    const baseRate = parseFloat(body.baseRatePerHour ?? 0);
    const doc = {
      currency: typeof body.currency === 'string' ? body.currency : 'VND',
      // Force BSON double by adding epsilon to integers (MongoDB driver serializes whole numbers as int)
      baseRatePerHour: baseRate + (baseRate === Math.floor(baseRate) ? 0.000001 : 0),
      rules: Array.isArray(body.rules) ? body.rules.map(sanitizeRule) : [],
      updatedAt: new Date(),
    };
    // Add optional ObjectIds only if they exist in key (MUST be ObjectId, not string)
    if (key.facilityId) doc.facilityId = key.facilityId;
    if (key.sportId) doc.sportId = key.sportId;
    if (key.courtId) doc.courtId = key.courtId;
    // taxPercent must be 0-100 (user enters %, not basis points) AND must be double (not int)
    if (body.taxPercent !== undefined) {
      const tax = parseFloat(body.taxPercent);
      const clamped = Math.max(0, Math.min(100, tax));
      // Force BSON double type by adding tiny epsilon (MongoDB driver serializes integers as int32/int64)
      doc.taxPercent = clamped + (clamped === Math.floor(clamped) ? 0.000001 : 0);
      console.log('[upsert] taxPercent conversion:', { input: body.taxPercent, parsed: tax, clamped, final: doc.taxPercent, type: typeof doc.taxPercent });
    }
    if (body.active !== undefined) doc.active = !!body.active;

    console.log('[upsert] Doc to $set (before insert):', doc);

    const r = await db.collection('price_profiles').findOneAndUpdate(
      key,
      { $set: doc, $setOnInsert: { createdAt: new Date() } },
      { upsert: true, returnDocument: 'after' }
    );
    const updated = r.value || (await db.collection('price_profiles').findOne(key));
    console.log('[upsert] Result:', updated);
    await recordAudit(req, {
      action: 'upsert',
      resource: 'price_profile',
      resourceId: updated?._id || `${key.facilityId || ''}:${key.sportId || ''}:${key.courtId || ''}`,
      payload: body,
      changes: updated,
    });
    res.json(updated);
  } catch (e) {
    console.error('[upsert] Error:', e);
    // If it's a MongoDB validation error, log the detailed schema violations
    if (e.code === 121 && e.errInfo?.details?.schemaRulesNotSatisfied) {
      console.error('[upsert] Schema validation details:', JSON.stringify(e.errInfo.details.schemaRulesNotSatisfied, null, 2));
    }
    next(e);
  }
});

app.post('/api/staff/price-profiles/upsert', async (req, res, next) => {
  try {
    const staffUser = await fetchStaffUser(req);
    if (!staffUser) return res.status(401).json({ error: 'Unauthenticated' });

    const staffFacilitySet = buildComparableIdSet(staffUser.facilityId);
    if (!staffFacilitySet.size) {
      return res.status(403).json({ error: 'No facility assigned' });
    }

    const body = { ...(req.body || {}) };
    const requestedFacilityId = body.facilityId ?? staffUser.facilityId;
    const requestedFacilitySet = buildComparableIdSet(requestedFacilityId);
    let hasAccess = false;
    for (const id of requestedFacilitySet) {
      if (staffFacilitySet.has(id)) {
        hasAccess = true;
        break;
      }
    }
    if (!hasAccess) {
      return res.status(403).json({ error: 'Không có quyền cập nhật bảng giá cho cơ sở này' });
    }

    const key = {};
    const facilityObjectId = coerceObjectId(requestedFacilityId);
    if (!facilityObjectId) {
      return res.status(400).json({ error: 'facilityId invalid' });
    }
    key.facilityId = facilityObjectId;
    body.facilityId = facilityObjectId;

    if (body.sportId) {
      const sportObjectId = coerceObjectId(body.sportId);
      if (!sportObjectId) {
        return res.status(400).json({ error: 'sportId invalid' });
      }
      key.sportId = sportObjectId;
      body.sportId = sportObjectId;
    }
    if (body.courtId) {
      const courtObjectId = coerceObjectId(body.courtId);
      if (!courtObjectId) {
        return res.status(400).json({ error: 'courtId invalid' });
      }
      key.courtId = courtObjectId;
      body.courtId = courtObjectId;
    }

    const sanitizeRule = (r) => {
      const rr = { ...r };
      if (Array.isArray(rr.daysOfWeek)) {
        rr.daysOfWeek = rr.daysOfWeek.map((d) => Number(d)).filter((d) => d >= 0 && d <= 6);
      }
      if (rr.value !== undefined) rr.value = Number(rr.value);
      if (rr.rateType !== 'multiplier' && rr.rateType !== 'fixed') rr.rateType = 'multiplier';
      if (typeof rr.startTime !== 'string') rr.startTime = '00:00';
      if (typeof rr.endTime !== 'string') rr.endTime = '24:00';
      return rr;
    };

    const baseRate = parseFloat(body.baseRatePerHour ?? 0);
    const doc = {
      currency: typeof body.currency === 'string' ? body.currency : 'VND',
      baseRatePerHour: baseRate + (baseRate === Math.floor(baseRate) ? 0.000001 : 0),
      rules: Array.isArray(body.rules) ? body.rules.map(sanitizeRule) : [],
      updatedAt: new Date(),
      facilityId: facilityObjectId,
    };
    if (key.sportId) doc.sportId = key.sportId;
    if (key.courtId) doc.courtId = key.courtId;
    if (body.taxPercent !== undefined) {
      const tax = parseFloat(body.taxPercent);
      const clamped = Math.max(0, Math.min(100, tax));
      doc.taxPercent = clamped + (clamped === Math.floor(clamped) ? 0.000001 : 0);
    }
    if (body.active !== undefined) doc.active = !!body.active;

    const r = await db.collection('price_profiles').findOneAndUpdate(
      key,
      { $set: doc, $setOnInsert: { createdAt: new Date(), createdByStaffId: staffUser._id } },
      { upsert: true, returnDocument: 'after' }
    );
    const updated = r.value || (await db.collection('price_profiles').findOne(key));
    await recordAudit(req, {
      action: 'staff-upsert',
      resource: 'price_profile',
      resourceId: updated?._id || `${key.facilityId || ''}:${key.sportId || ''}:${key.courtId || ''}`,
      payload: body,
      changes: updated,
    });
    res.json(updated);
  } catch (e) {
    next(e);
  }
});

app.get('/api/admin/audit-logs', async (req, res, next) => {
  try {
    const { action, resource, actorId, limit, since, until } = req.query || {};
    const filter = {};
    if (action) filter.action = String(action);
    if (resource) filter.resource = String(resource);
    if (actorId) filter['actor.id'] = String(actorId);
    if (since || until) {
      filter.createdAt = {};
      if (since) {
        const d = new Date(String(since));
        if (!Number.isNaN(d.getTime())) filter.createdAt.$gte = d;
      }
      if (until) {
        const d = new Date(String(until));
        if (!Number.isNaN(d.getTime())) filter.createdAt.$lte = d;
      }
      if (Object.keys(filter.createdAt).length === 0) delete filter.createdAt;
    }
    let lim = Number(limit ?? 100);
    if (!Number.isFinite(lim) || lim <= 0) lim = 100;
    lim = Math.min(lim, 500);
    const logs = await db.collection('audit_logs').find(filter).sort({ createdAt: -1 }).limit(lim).toArray();
    res.json(logs);
  } catch (e) { next(e); }
});

// ADMIN: create user (admin/staff/customer) – admin only
// USERS (admin)
app.get('/api/admin/users', async (req, res, next) => {
  try {
    const { role, status, q } = req.query || {};
    const filter = {};
    if (role) filter.role = String(role);
    if (status) filter.status = String(status);
    if (q) {
      const s = String(q);
      filter.$or = [
        { email: { $regex: s, $options: 'i' } },
        { name: { $regex: s, $options: 'i' } },
        { phone: { $regex: s, $options: 'i' } },
      ];
    }
    const users = await db.collection('users').find(filter, { projection: { passwordHash: 0 } }).sort({ createdAt: -1 }).limit(500).toArray();
    res.json(users);
  } catch (e) { next(e); }
});

app.post('/api/admin/users', async (req, res, next) => {
  try {
    const {
      email,
      password,
      name,
      role = 'customer',
      status = 'active',
      facilityId,
      gender,
      dateOfBirth,
      mainSportId,
    } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'email and password required' });
    const allowedRoles = ['customer','staff','admin'];
    if (!allowedRoles.includes(role)) return res.status(400).json({ error: 'invalid role' });
    if (role === 'staff' && !facilityId) {
      return res.status(400).json({ error: 'facilityId required for staff' });
    }
    const existing = await db.collection('users').findOne({ email: String(email).toLowerCase() });
    if (existing) return res.status(409).json({ error: 'Email already exists' });

    const genderResult = normalizeGenderInput(gender);
    if (genderResult.provided && genderResult.error) {
      return res.status(400).json({ error: 'Giới tính không hợp lệ' });
    }

    const dobResult = normalizeDateInput(dateOfBirth);
    if (dobResult.provided && dobResult.error) {
      return res.status(400).json({ error: 'Ngày sinh không hợp lệ' });
    }

    const mainSportResult = normalizeObjectIdInput(mainSportId);
    if (mainSportResult.provided && mainSportResult.error) {
      return res.status(400).json({ error: 'mainSportId không hợp lệ' });
    }

    const passwordHash = await bcrypt.hash(String(password), 10);
    const doc = {
      email: String(email).toLowerCase(),
      name: typeof name === 'string' ? name : undefined,
      role,
      status,
      passwordHash,
      createdAt: new Date(),
    };
    if (role === 'staff') doc.facilityId = new ObjectId(String(facilityId));
    if (genderResult.provided && genderResult.value) doc.gender = genderResult.value;
    if (dobResult.provided && dobResult.value) doc.dateOfBirth = dobResult.value;
    if (mainSportResult.provided && mainSportResult.value) doc.mainSportId = mainSportResult.value;
    try {
      const r = await db.collection('users').insertOne(doc);
      const inserted = await db.collection('users').findOne(
        { _id: r.insertedId },
        { projection: { passwordHash: 0 } },
      );
      const response = shapeAuthUser(inserted) ?? {
        _id: r.insertedId,
        email: doc.email,
        name: doc.name,
        role: doc.role,
        status: doc.status,
        phone: doc.phone ?? null,
        facilityId: doc.facilityId ?? null,
        gender: doc.gender ?? null,
        dateOfBirth: doc.dateOfBirth ?? null,
        mainSportId: doc.mainSportId ?? null,
      };
      await recordAudit(req, {
        action: 'create',
        resource: 'user',
        resourceId: r.insertedId,
        payload: { email, role, status, facilityId },
        changes: response,
      });
      res.status(201).json(response);
    } catch (e) {
      // Handle unique constraint: one staff per facility
      if (e && e.code === 11000) {
        return res.status(409).json({ error: 'Duplicate key', message: 'Each facility can only have one staff' });
      }
      throw e;
    }
  } catch (e) { next(e); }
});

app.put('/api/admin/users/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const { name, phone, role, status, resetPassword, facilityId, gender, dateOfBirth, mainSportId } = req.body || {};
    const candidates = buildIdCandidates(idParam);
    let current;
    for (const candidate of candidates) {
      current = await db.collection('users').findOne({ _id: candidate });
      if (current) break;
    }
    if (!current) {
      current = await db.collection('users').findOne({ _id: idParam });
    }
    if (!current) {
      console.warn('[admin.users:update] user not found', { idParam, candidates });
      return res.status(404).json({ error: 'Not found' });
    }
    const filter = { _id: current._id };
    const $set = {};
    const $unset = {};
    if (typeof name === 'string') $set.name = name;
    if (phone !== undefined) {
      if (phone === null || (typeof phone === 'string' && !phone.trim().length)) {
        $unset.phone = '';
      } else if (typeof phone === 'string') {
        $set.phone = phone;
      } else {
        return res.status(400).json({ error: 'Số điện thoại không hợp lệ' });
      }
    }
    if (typeof role === 'string' && ['customer','staff','admin'].includes(role)) $set.role = role;
    if (typeof status === 'string' && ['active','blocked','deleted'].includes(status)) $set.status = status;
    if (facilityId !== undefined) {
      if (facilityId === null || facilityId === '') {
        $unset.facilityId = '';
      } else {
        const facilityObjectId = coerceObjectId(facilityId);
        if (!facilityObjectId) {
          return res.status(400).json({ error: 'Invalid facilityId' });
        }
        $set.facilityId = facilityObjectId;
      }
    }
    if (typeof resetPassword === 'string' && resetPassword.length >= 6) {
      $set.passwordHash = await bcrypt.hash(resetPassword, 10);
    }

    if (gender !== undefined) {
      const genderResult = normalizeGenderInput(gender);
      if (genderResult.error) {
        return res.status(400).json({ error: 'Giới tính không hợp lệ' });
      }
      if (genderResult.value) {
        $set.gender = genderResult.value;
      } else {
        $unset.gender = '';
      }
    }

    if (dateOfBirth !== undefined) {
      const dobResult = normalizeDateInput(dateOfBirth);
      if (dobResult.error) {
        return res.status(400).json({ error: 'Ngày sinh không hợp lệ' });
      }
      if (dobResult.value) {
        $set.dateOfBirth = dobResult.value;
      } else {
        $unset.dateOfBirth = '';
      }
    }

    if (mainSportId !== undefined) {
      const sportResult = normalizeObjectIdInput(mainSportId);
      if (sportResult.error) {
        return res.status(400).json({ error: 'mainSportId không hợp lệ' });
      }
      if (sportResult.value) {
        $set.mainSportId = sportResult.value;
      } else {
        $unset.mainSportId = '';
      }
    }
    // Validate staff must have facilityId
    const nextRole = (typeof role === 'string' ? role : current.role);
    const nextFacility = (facilityId !== undefined) ? facilityId : current.facilityId;
    if (nextRole === 'staff' && !nextFacility && !$set.facilityId) {
      return res.status(400).json({ error: 'facilityId required for staff' });
    }
    if (Object.keys($set).length === 0 && Object.keys($unset).length === 0) return res.status(400).json({ error: 'No valid fields' });
    $set.updatedAt = new Date();
    try {
      const updateDoc = { };
      if (Object.keys($set).length) updateDoc.$set = $set;
      if (Object.keys($unset).length) updateDoc.$unset = $unset;
      const result = await db.collection('users').updateOne(filter, updateDoc);
      if (!result.matchedCount) {
        console.warn('[admin.users:update] update matchedCount=0', {
          idParam,
          canonicalId: current._id,
          canonicalType: current._id?.constructor?.name,
        });
        return res.status(404).json({ error: 'Not found' });
      }
      const updated = await db.collection('users').findOne({ _id: current._id }, { projection: { passwordHash: 0 } });
      if (!updated) {
        console.warn('[admin.users:update] updated doc missing after updateOne', {
          idParam,
          canonicalId: current._id,
          canonicalType: current._id?.constructor?.name,
        });
        return res.status(404).json({ error: 'Not found' });
      }
      await recordAudit(req, {
        action: 'update',
        resource: 'user',
        resourceId: current._id,
        payload: req.body,
        changes: updated,
      });
      res.json(updated);
    } catch (e) {
      if (e && e.code === 11000) {
        return res.status(409).json({ error: 'Duplicate key', message: 'Each facility can only have one staff' });
      }
      throw e;
    }
  } catch (e) { next(e); }
});

app.delete('/api/admin/users/:id', async (req, res, next) => {
  try {
    const idParam = String(req.params.id);
    const candidates = buildIdCandidates(idParam);
    const filter = buildIdMatchFilter(idParam);
    const objectCandidateCount = candidates.filter((candidate) => candidate instanceof ObjectId).length;
    logDeleteDebug({ stage: 'start', idParam, filter, candidates, objectCandidateCount });

    const deleteWithFilter = async (query) => db.collection('users').findOneAndDelete(query, {
      projection: { passwordHash: 0 },
    });

    let result = await deleteWithFilter(filter);
    if (result?.value) {
      logDeleteDebug({ stage: 'match.initial', idParam, matchedId: result.value?._id });
    }

    if (!result?.value && candidates.length) {
      const canonicalHexes = [];
      for (const candidate of candidates) {
        if (candidate instanceof ObjectId) {
          canonicalHexes.push(candidate.toHexString().toLowerCase());
        } else if (typeof candidate === 'string') {
          const trimmed = candidate.trim();
          if (/^[0-9a-fA-F]{24}$/.test(trimmed)) {
            canonicalHexes.push(trimmed.toLowerCase());
          }
        }
      }
      const uniqueHexes = Array.from(new Set(canonicalHexes));
      if (uniqueHexes.length) {
        result = await deleteWithFilter({
          $expr: {
            $in: [
              { $toString: '$_id' },
              uniqueHexes,
            ],
          },
        });
        if (result?.value) {
          logDeleteDebug({ stage: 'match.expr', idParam, matchedId: result.value?._id, uniqueHexes });
        }
      }
    }

    if (!result?.value && /^[0-9a-fA-F]{6,}$/.test(idParam)) {
      const regex = new RegExp(escapeRegex(idParam), 'i');
      result = await deleteWithFilter({ _id: { $regex: regex } });
      if (result?.value) {
        logDeleteDebug({ stage: 'match.regex', idParam });
      }
    }

    if (!result?.value) {
      logDeleteDebug({ stage: 'not_found', idParam });
      console.warn('[admin.users:delete] user not found', { idParam });
      return res.status(404).json({ error: 'Not found' });
    }

    await recordAudit(req, {
      action: 'delete.hard',
      resource: 'user',
      resourceId: result.value._id,
      payload: { id: idParam },
      changes: { removed: true },
    });

    res.json({ deleted: true, user: result.value });
  } catch (e) { next(e); }
});

app.use((req, res, next) => {
  res.status(404).json({
    error: 'Not found',
    method: req.method,
    path: req.originalUrl,
  });
});

app.use((err, req, res, next) => {
  console.error(err);
  const payload = { error: 'Internal Server Error' };
  if (err?.message) payload.message = err.message;
  if (err?.name) payload.name = err.name;
  if (err?.code) payload.code = err.code;
  if (err?.errInfo) payload.details = err.errInfo;
  res.status(500).json(payload);
});

const PORT = process.env.PORT || 3000;

connectMongo()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      // Bind to 0.0.0.0 so cloud hosts (Render, etc.) can reach the process.
      console.log(`Server is running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to start server due to MongoDB error', err);
    process.exit(1);
  });
