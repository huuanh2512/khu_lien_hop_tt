import { MongoClient } from 'mongodb';

const uri = process.env.MONGO_URI || 'mongodb+srv://huuanh2512_db_user:251224hanh@hnauuh.ei7ouzm.mongodb.net/?retryWrites=true&w=majority&appName=hnAuuH';
const dbName = process.env.DB_NAME || 'test';

const client = new MongoClient(uri);

try {
  await client.connect();
  const db = client.db(dbName);
  const doc = await db.collection('facilities').findOne({ name: 'Khu liên hợp ABC' });
  console.log(doc);
} catch (err) {
  console.error(err);
} finally {
  await client.close();
}
