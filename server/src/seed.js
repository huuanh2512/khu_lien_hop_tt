import 'dotenv/config';
import { MongoClient } from 'mongodb';

const MONGO_URI = process.env.MONGO_URI || 'mongodb+srv://huuanh2512_db_user:251224hanh@hnauuh.ei7ouzm.mongodb.net/';
const DB_NAME = process.env.DB_NAME || 'test';

const sportsSeed = [
  { name: 'Bóng đá', code: 'SOCCER', teamSize: 11, equipment: ['ball','shoes'], active: true },
  { name: 'Bóng chuyền', code: 'VOLLEYBALL', teamSize: 6, equipment: ['ball','shoes'], active: true },
  { name: 'Cầu lông', code: 'BADMINTON', teamSize: 2, equipment: ['racket','shuttlecock'], active: true },
  { name: 'Pickleball', code: 'PICKLEBALL', teamSize: 2, equipment: ['paddle','ball'], active: true },
];

async function up() {
  const client = new MongoClient(MONGO_URI);
  await client.connect();
  const db = client.db(DB_NAME);

  // Ensure unique index
  await db.collection('sports').createIndex({ code: 1 }, { unique: true });

  for (const s of sportsSeed) {
    await db.collection('sports').updateOne({ code: s.code }, { $setOnInsert: s }, { upsert: true });
  }

  console.log('Seed done');
  await client.close();
}

up().catch((e) => { console.error(e); process.exit(1); });
