import { MongoClient, ObjectId } from 'mongodb';

const uri = process.env.MONGO_URI || 'mongodb+srv://huuanh2512_db_user:251224hanh@hnauuh.ei7ouzm.mongodb.net/?retryWrites=true&w=majority&appName=hnAuuH';
const dbName = process.env.DB_NAME || 'test';

const client = new MongoClient(uri);

try {
  await client.connect();
  const db = client.db(dbName);
  const filter = { _id: new ObjectId('68d65892a45287b839cebea7') };
  const updateDoc = {
    $set: {
      openingHours: [{ open: '8', close: '22' }],
      amenities: ['parking', 'locker', 'shower'],
      updatedAt: new Date(),
    },
    $unset: { description: '' },
  };
  const result = await db.collection('facilities').findOneAndUpdate(
    filter,
    updateDoc,
    { returnDocument: 'after' }
  );
  console.log('result', result);
  console.log('matched?', !!result.value);
  if (result.value) {
    console.log({
      id: result.value._id,
      openingHours: result.value.openingHours,
      amenities: result.value.amenities,
    });
  }
} catch (err) {
  console.error(err);
} finally {
  await client.close();
}
