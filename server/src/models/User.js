import { MongoClient, ObjectId } from 'mongodb';

const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017';
const DB_NAME = process.env.DB_NAME || 'test';

let client;
let clientPromise;

function normalizeEmail(value) {
  if (!value || typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed.length) return null;
  return trimmed.toLowerCase();
}

async function getClient() {
  if (client && client.topology && client.topology.isConnected()) {
    return client;
  }

  if (!clientPromise) {
    client = new MongoClient(MONGO_URI, { maxPoolSize: 5 });
    clientPromise = client.connect().catch((err) => {
      clientPromise = undefined;
      throw err;
    });
  }

  await clientPromise;
  return client;
}

async function getCollection() {
  const currentClient = await getClient();
  return currentClient.db(DB_NAME).collection('users');
}

async function findOne(filter) {
  const col = await getCollection();
  return col.findOne(filter);
}

async function create(doc) {
  const col = await getCollection();
  const now = new Date();
  const payload = {
    role: 'customer',
    status: 'active',
    createdAt: now,
    ...doc,
    status: doc?.status ?? 'active',
    createdAt: doc?.createdAt ?? now,
  };
  if (payload.email) {
    payload.email = normalizeEmail(payload.email) ?? payload.email;
  }
  const result = await col.insertOne(payload);
  return { _id: result.insertedId, ...payload };
}

async function updateFirebaseUid(userId, firebaseUid) {
  if (!userId) return null;
  const col = await getCollection();
  const _id = userId instanceof ObjectId ? userId : new ObjectId(String(userId));
  await col.updateOne(
    { _id },
    { $set: { firebaseUid, updatedAt: new Date() } },
  );
  return col.findOne({ _id });
}

async function updateById(userId, updates = {}) {
  if (!userId) return null;
  const col = await getCollection();
  const _id = userId instanceof ObjectId ? userId : new ObjectId(String(userId));
  const $set = { ...updates, updatedAt: new Date() };
  if (Object.prototype.hasOwnProperty.call($set, 'email')) {
    $set.email = normalizeEmail($set.email) ?? $set.email;
  }
  await col.updateOne({ _id }, { $set });
  return col.findOne({ _id });
}

const User = { findOne, create, updateFirebaseUid, updateById, normalizeEmail };

export default User;
