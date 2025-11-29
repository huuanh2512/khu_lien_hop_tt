import dotenv from 'dotenv';
import admin from 'firebase-admin';

dotenv.config();

const firebaseProjectId = process.env.FIREBASE_PROJECT_ID;
const firebaseClientEmail = process.env.FIREBASE_CLIENT_EMAIL;
let firebasePrivateKey = process.env.FIREBASE_PRIVATE_KEY;

if (firebasePrivateKey) {
  firebasePrivateKey = firebasePrivateKey.replace(/\\n/g, '\n');
}

if (!admin.apps.length) {
  if (firebaseProjectId && firebaseClientEmail && firebasePrivateKey) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: firebaseProjectId,
        clientEmail: firebaseClientEmail,
        privateKey: firebasePrivateKey,
      }),
    });
  } else {
    console.warn('Firebase Admin env vars are not fully set, skipping Firebase init');
  }
}

export default admin;
