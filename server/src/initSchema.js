// Initializes collections, validators, and indexes per provided MongoDB schema.
import 'dotenv/config';
import { MongoClient } from 'mongodb';

const MONGO_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.MONGODB_DB_NAME || 'khu_lien_hop_tt';

if (!MONGO_URI) {
  throw new Error('MONGODB_URI is not set for initSchema');
}

async function run() {
  const client = new MongoClient(MONGO_URI);
  await client.connect();
  const db = client.db(DB_NAME);

  // Helper create or modify collection with validator
  async function ensureCollection(name, validator) {
    const exists = (await db.listCollections({ name }).toArray()).length > 0;
    if (!exists) {
      await db.createCollection(name, { validator });
    } else {
      if (validator) {
        await db.command({ collMod: name, validator });
      }
    }
  }

  // 2) sports
  await ensureCollection('sports', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['name','code','teamSize'],
      properties: {
        name: { bsonType: 'string' },
        code: { bsonType: 'string' },
        teamSize: { bsonType: ['int','long'], minimum: 1 },
        equipment: { bsonType: ['array'], items: { bsonType: 'string' } },
        active: { bsonType: 'bool' },
      },
    },
  });
  await db.collection('sports').createIndex({ code: 1 }, { unique: true });

  // 3) facilities
  await ensureCollection('facilities', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['name','address','timeZone'],
      properties: {
        name: { bsonType: 'string' },
        address: { bsonType: 'object' },
        timeZone: { bsonType: 'string' },
        openingHours: { bsonType: 'array' },
        amenities: { bsonType: 'array', items: { bsonType: 'string' } },
        geo: {
          bsonType: 'object',
          properties: {
            type: { enum: ['Point'] },
            coordinates: { bsonType: 'array', items: { bsonType: 'double' }, minItems: 2, maxItems: 2 },
          },
        },
        active: { bsonType: 'bool' },
      },
    },
  });
  await db.collection('facilities').createIndex({ geo: '2dsphere' });

  // 4) users
  await ensureCollection('users', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['email','role','status'],
      properties: {
        email: { bsonType: 'string' },
        phone: { bsonType: 'string' },
        name: { bsonType: 'string' },
        role: { enum: ['admin','staff','customer'] },
        status: { enum: ['active','blocked','deleted'] },
        sportsPreferences: { bsonType: 'array', items: { bsonType: 'objectId' } },
        skill: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['sportId','level'],
            properties: {
              sportId: { bsonType: 'objectId' },
              level: { bsonType: 'int', minimum: 1, maximum: 10 },
              elo: { bsonType: ['int','long'] },
            },
          },
        },
        homeLocation: {
          bsonType: 'object',
          properties: {
            type: { enum: ['Point'] },
            coordinates: { bsonType: 'array', items: { bsonType: 'double' }, minItems: 2, maxItems: 2 },
          },
        },
        membership: {
          bsonType: 'object',
          properties: {
            tier: { enum: ['none','silver','gold','platinum'] },
            validUntil: { bsonType: 'date' },
          },
        },
        createdAt: { bsonType: 'date' },
      },
    },
  });
  await db.collection('users').createIndex({ email: 1 }, { unique: true });
  await db.collection('users').createIndex({ role: 1 });
  await db.collection('users').createIndex({ homeLocation: '2dsphere' });

  // 5) courts
  await ensureCollection('courts', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['facilityId','sportId','name','status'],
      properties: {
        facilityId: { bsonType: 'objectId' },
        sportId: { bsonType: 'objectId' },
        name: { bsonType: 'string' },
        code: { bsonType: 'string' },
        indoor: { bsonType: 'bool' },
        surface: { bsonType: 'string' },
        size: { bsonType: 'string' },
        priceProfileId: { bsonType: 'objectId' },
        status: { enum: ['active','maintenance','inactive'] },
        meta: { bsonType: 'object' },
      },
    },
  });
  await db.collection('courts').createIndex({ facilityId: 1, sportId: 1 });
  await db.collection('courts').createIndex({ priceProfileId: 1 });

  // 6) price_profiles
  await ensureCollection('price_profiles', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['currency','baseRatePerHour','rules'],
      properties: {
        name: { bsonType: 'string' },
        facilityId: { bsonType: 'objectId' },
        sportId: { bsonType: 'objectId' },
        courtId: { bsonType: 'objectId' },
        currency: { bsonType: 'string' },
        baseRatePerHour: { bsonType: ['double','int','long'], minimum: 0 },
        rules: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            properties: {
              daysOfWeek: { bsonType: 'array', items: { bsonType: 'int', minimum: 0, maximum: 6 } },
              startTime: { bsonType: 'string' },
              endTime: { bsonType: 'string' },
              rateType: { enum: ['multiplier','fixed'] },
              value: { bsonType: ['double','int','long'] },
            },
          },
        },
        membershipDiscounts: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            properties: {
              tier: { enum: ['silver','gold','platinum'] },
              percentOff: { bsonType: 'double', minimum: 0, maximum: 100.01 },
            },
          },
        },
        taxPercent: { bsonType: 'double', minimum: 0, maximum: 100.01 },
        active: { bsonType: 'bool' },
      },
    },
  });
  await db.collection('price_profiles').createIndex({ facilityId: 1, sportId: 1, courtId: 1 });

  // 7) maintenance
  await ensureCollection('maintenance', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['courtId','start','end','reason'],
      properties: {
        courtId: { bsonType: 'objectId' },
        start: { bsonType: 'date' },
        end: { bsonType: 'date' },
        reason: { bsonType: 'string' },
      },
    },
  });
  await db.collection('maintenance').createIndex({ courtId: 1, start: 1, end: 1 });

  // 8) vouchers
  await ensureCollection('vouchers', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['code','type','value','status'],
      properties: {
        code: { bsonType: 'string' },
        type: { enum: ['percent','fixed'] },
        value: { bsonType: ['double','int','long'], minimum: 0 },
        applicableSports: { bsonType: 'array', items: { bsonType: 'objectId' } },
        applicableFacilityIds: { bsonType: 'array', items: { bsonType: 'objectId' } },
        minSpend: { bsonType: ['double','int','long'], minimum: 0 },
        startDate: { bsonType: 'date' },
        endDate: { bsonType: 'date' },
        status: { enum: ['active','expired','disabled'] },
      },
    },
  });
  await db.collection('vouchers').createIndex({ code: 1 }, { unique: true });
  await db.collection('vouchers').createIndex({ status: 1, endDate: 1 });

  // 9) bookings
  await ensureCollection('bookings', {
    $and: [
      {
        $jsonSchema: {
          bsonType: 'object',
          required: ['customerId','facilityId','courtId','sportId','start','end','status','pricingSnapshot','currency'],
          properties: {
            customerId: { bsonType: 'objectId' },
            facilityId: { bsonType: 'objectId' },
            courtId: { bsonType: 'objectId' },
            sportId: { bsonType: 'objectId' },
            matchRequestId: { bsonType: 'objectId' },
            start: { bsonType: 'date' },
            end: { bsonType: 'date' },
            status: { enum: ['pending','confirmed','cancelled','completed','no_show','refunded'] },
            participants: { bsonType: 'array', items: { bsonType: 'objectId' } },
            voucherId: { bsonType: 'objectId' },
            currency: { bsonType: 'string' },
            pricingSnapshot: {
              bsonType: 'object',
              required: ['baseRatePerHour','ruleApplied','subtotal','discount','tax','total'],
              properties: {
                baseRatePerHour: { bsonType: ['double','int','long'] },
                ruleApplied: { bsonType: 'object' },
                durationMinutes: { bsonType: ['int','long'] },
                subtotal: { bsonType: ['double','int','long'] },
                discount: { bsonType: ['double','int','long'] },
                tax: { bsonType: ['double','int','long'] },
                total: { bsonType: ['double','int','long'] },
              },
            },
            createdBy: { bsonType: 'objectId' },
            createdAt: { bsonType: 'date' },
          },
        },
      },
      { $expr: { $lt: ['$start', '$end'] } },
    ],
  });
  await db.collection('bookings').createIndex({ courtId: 1, start: 1, end: 1 });
  await db.collection('bookings').createIndex({ customerId: 1, start: 1 });
  await db.collection('bookings').createIndex({ status: 1, start: 1 });

  // 10) invoices
  await ensureCollection('invoices', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['bookingId','amount','currency','status'],
      properties: {
        bookingId: { bsonType: 'objectId' },
        amount: { bsonType: ['double','int','long'] },
        currency: { bsonType: 'string' },
        status: { enum: ['unpaid','paid','void','refunded'] },
        issuedAt: { bsonType: 'date' },
      },
    },
  });
  await db.collection('invoices').createIndex({ bookingId: 1 }, { unique: true });
  await db.collection('invoices').createIndex({ status: 1 });

  // 11) payments
  await ensureCollection('payments', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['invoiceId','provider','method','amount','status','createdAt'],
      properties: {
        invoiceId: { bsonType: 'objectId' },
        provider: { bsonType: 'string' },
        method: { bsonType: 'string' },
        amount: { bsonType: ['double','int','long'] },
        currency: { bsonType: 'string' },
        status: { enum: ['initiated','succeeded','failed','refunded','chargeback'] },
        txnRef: { bsonType: 'string' },
        createdAt: { bsonType: 'date' },
        meta: { bsonType: 'object' },
      },
    },
  });
  await db.collection('payments').createIndex({ invoiceId: 1 });
  await db.collection('payments').createIndex({ txnRef: 1 }, { unique: true, sparse: true });

  // 12) match_requests
  await ensureCollection('match_requests', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['creatorId','sportId','desiredStart','desiredEnd','status','visibility'],
      properties: {
        creatorId: { bsonType: 'objectId' },
        sportId: { bsonType: 'objectId' },
        facilityId: { bsonType: 'objectId' },
        courtId: { bsonType: 'objectId' },
        desiredStart: { bsonType: 'date' },
        desiredEnd: { bsonType: 'date' },
        skillRange: { bsonType: 'object', properties: { min: { bsonType: 'int' }, max: { bsonType: 'int' } } },
        teamSize: { bsonType: 'int' },
        location: { bsonType: 'object', properties: { type: { enum: ['Point'] }, coordinates: { bsonType: 'array', items: { bsonType: 'double' }, minItems: 2, maxItems: 2 } } },
        radiusKm: { bsonType: 'double' },
        visibility: { enum: ['public','friends','private'] },
        status: { enum: ['open','matched','cancelled','expired'] },
        bookingStatus: { bsonType: 'string' },
        matchedBookingId: { bsonType: 'objectId' },
        createdAt: { bsonType: 'date' },
      },
    },
  });
  await db.collection('match_requests').createIndex({ sportId: 1, desiredStart: 1 });
  await db.collection('match_requests').createIndex({ location: '2dsphere' });

  // 13) notifications
  await ensureCollection('notifications', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['title','status','createdAt'],
      properties: {
        recipientId: { bsonType: 'objectId' },
        recipientRole: { bsonType: 'string' },
        facilityId: { bsonType: 'objectId' },
        title: { bsonType: 'string' },
        message: { bsonType: 'string' },
        data: { bsonType: 'object' },
        status: { enum: ['unread','read'] },
        createdAt: { bsonType: 'date' },
        readAt: { bsonType: 'date' },
      },
    },
  });
  await db.collection('notifications').createIndex({ recipientId: 1, createdAt: -1 });
  await db.collection('notifications').createIndex({ recipientRole: 1, facilityId: 1, createdAt: -1 });

  // 14) audit_logs
  await ensureCollection('audit_logs', {
    $jsonSchema: {
      bsonType: 'object',
      required: ['actorId','action','target','at'],
      properties: {
        actorId: { bsonType: 'objectId' },
        action: { bsonType: 'string' },
        target: { bsonType: 'object' },
        changes: { bsonType: 'object' },
        at: { bsonType: 'date' },
      },
    },
  });
  await db.collection('audit_logs').createIndex({ at: 1 });

  console.log('Schema initialized/updated');
  await client.close();
}

run().catch((e) => { console.error(e); process.exit(1); });
