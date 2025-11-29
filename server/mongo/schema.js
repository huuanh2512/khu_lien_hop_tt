// Run with: mongosh --file mongo/schema.js
use('test');

// 2) sports (giữ nguyên)
try { db.createCollection("sports", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "code", "teamSize"],
      properties: {
        name: { bsonType: "string" },
        code: { bsonType: "string" },
        teamSize: { bsonType: ["int","long"], minimum: 1 },
        equipment: { bsonType: "array", items: { bsonType: "string" } },
        active: { bsonType: "bool" }
      }
    }
  }
}); } catch {}
db.sports.createIndex({ code: 1 }, { unique: true });

// 3) facilities (giữ nguyên)
try { db.createCollection("facilities", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name","address","timeZone"],
      properties: {
        name: { bsonType: "string" },
        address: { bsonType: "object" },
        timeZone: { bsonType: "string" },
        openingHours: { bsonType: "array" },
        amenities: { bsonType: "array", items: { bsonType: "string" } },
        geo: {
          bsonType: "object",
          properties: {
            type: { enum: ["Point"] },
            coordinates: { bsonType: "array", items: { bsonType: "double" }, minItems: 2, maxItems: 2 }
          }
        },
        active: { bsonType: "bool" }
      }
    }
  }
}); } catch {}
db.facilities.createIndex({ geo: "2dsphere" });

// 4) users  ✅ SỬA TẠI ĐÂY: thêm facilityId + ràng buộc role=staff phải có facilityId
try { db.createCollection("users", {
  validator: {
    $and: [
      {
        $jsonSchema: {
          bsonType: "object",
          required: ["email","role","status"],
          properties: {
            email: { bsonType: "string" },
            phone: { bsonType: "string" },
            name:  { bsonType: "string" },
            role:  { enum: ["admin","staff","customer"] },
            status:{ enum: ["active","blocked","deleted"] },
            // mới thêm: staff sẽ trỏ về facility quản lý (1–1)
            facilityId: { bsonType: "objectId" },
            sportsPreferences: { bsonType: "array", items: { bsonType: "objectId" } },
            skill: {
              bsonType: "array",
              items: {
                bsonType: "object",
                required: ["sportId","level"],
                properties: {
                  sportId: { bsonType: "objectId" },
                  level:   { bsonType: "int", minimum: 1, maximum: 10 },
                  elo:     { bsonType: ["int","long"] }
                }
              }
            },
            homeLocation: {
              bsonType: "object",
              properties: {
                type: { enum: ["Point"] },
                coordinates: { bsonType: "array", items: { bsonType: "double" }, minItems: 2, maxItems: 2 }
              }
            },
            membership: {
              bsonType: "object",
              properties: {
                tier: { enum: ["none","silver","gold","platinum"] },
                validUntil: { bsonType: "date" }
              }
            },
            createdAt: { bsonType: "date" }
          }
        }
      },
      // Điều kiện ép: nếu role = 'staff' thì facilityId phải là ObjectId
      { $or: [ { role: { $ne: "staff" } }, { facilityId: { $type: "objectId" } } ] }
    ]
  }
}); } catch {}

// Index người dùng
db.users.createIndex({ email: 1 }, { unique: true });
db.users.createIndex({ role: 1 });

// ✅ Unique partial index đảm bảo: mỗi facility CHỈ có 1 staff
db.users.createIndex(
  { facilityId: 1 },
  { unique: true, partialFilterExpression: { role: "staff", facilityId: { $type: "objectId" } } }
);

// (tùy chọn) hỗ trợ tra cứu staff theo facility nhanh
db.users.createIndex({ role: 1, facilityId: 1 });

db.users.createIndex({ homeLocation: "2dsphere" });

// 5) courts (sân) — đã đúng 1 facility có nhiều sân, và mỗi sân thuộc 1 sport
try { db.createCollection("courts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["facilityId","sportId","name","status"],
      properties: {
        facilityId: { bsonType: "objectId" }, // 1–N với facilities
        sportId:    { bsonType: "objectId" }, // N–1 với sports
        name:       { bsonType: "string" },
        code:       { bsonType: "string" },
        indoor:     { bsonType: "bool" },
        surface:    { bsonType: "string" },
        size:       { bsonType: "string" },
        priceProfileId: { bsonType: "objectId" },
        status: { enum: ["active","maintenance","inactive"] },
        meta:   { bsonType: "object" }
      }
    }
  }
}); } catch {}

db.courts.createIndex({ facilityId: 1, sportId: 1 });
// (khuyến nghị) tránh trùng tên sân trong cùng facility
db.courts.createIndex({ facilityId: 1, name: 1 }, { unique: true });
db.courts.createIndex({ priceProfileId: 1 });

// 6) price_profiles (giữ nguyên)
try { db.createCollection("price_profiles", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["currency","baseRatePerHour","rules"],
      properties: {
        name: { bsonType: "string" },
        facilityId: { bsonType: "objectId" },
        sportId: { bsonType: "objectId" },
        courtId: { bsonType: "objectId" },
        currency: { bsonType: "string" },
        baseRatePerHour: { bsonType: ["double","int","long"], minimum: 0 },
        rules: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              daysOfWeek: { bsonType: "array", items: { bsonType: "int", minimum: 0, maximum: 6 } },
              startTime:  { bsonType: "string" },
              endTime:    { bsonType: "string" },
              rateType:   { enum: ["multiplier","fixed"] },
              value:      { bsonType: ["double","int","long"] }
            }
          }
        },
        membershipDiscounts: {
          bsonType: "array",
          items: {
            bsonType: "object",
            properties: {
              tier: { enum: ["silver","gold","platinum"] },
              percentOff: { bsonType: "double", minimum: 0, maximum: 100 }
            }
          }
        },
        taxPercent: { bsonType: "double", minimum: 0, maximum: 100 },
        active: { bsonType: "bool" }
      }
    }
  }
}); } catch {}
db.price_profiles.createIndex({ facilityId: 1, sportId: 1, courtId: 1 });

// 7) maintenance (giữ nguyên)
try { db.createCollection("maintenance", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["courtId","start","end","reason"],
      properties: {
        courtId: { bsonType: "objectId" },
        start:   { bsonType: "date" },
        end:     { bsonType: "date" },
        reason:  { bsonType: "string" }
      }
    }
  }
}); } catch {}
db.maintenance.createIndex({ courtId: 1, start: 1, end: 1 });

// 8) vouchers (giữ nguyên)
try { db.createCollection("vouchers", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["code","type","value","status"],
      properties: {
        code: { bsonType: "string" },
        type: { enum: ["percent","fixed"] },
        value: { bsonType: ["double","int","long"], minimum: 0 },
        applicableSports: { bsonType: "array", items: { bsonType: "objectId" } },
        applicableFacilityIds: { bsonType: "array", items: { bsonType: "objectId" } },
        minSpend: { bsonType: ["double","int","long"], minimum: 0 },
        startDate: { bsonType: "date" },
        endDate:   { bsonType: "date" },
        status: { enum: ["active","expired","disabled"] }
      }
    }
  }
}); } catch {}
db.vouchers.createIndex({ code: 1 }, { unique: true });
db.vouchers.createIndex({ status: 1, endDate: 1 });

// 9) bookings (giữ nguyên)
try { db.createCollection("bookings", {
  validator: {
    $and: [
      {
        $jsonSchema: {
          bsonType: "object",
          required: ["customerId","facilityId","courtId","sportId","start","end","status","pricingSnapshot","currency"],
          properties: {
            customerId: { bsonType: "objectId" },
            facilityId: { bsonType: "objectId" },
            courtId:    { bsonType: "objectId" },
            sportId:    { bsonType: "objectId" },
            matchRequestId: { bsonType: "objectId" },
            start: { bsonType: "date" },
            end:   { bsonType: "date" },
            status:{ enum: ["pending","confirmed","cancelled","completed","no_show","refunded"] },
            participants: { bsonType: "array", items: { bsonType: "objectId" } },
            voucherId: { bsonType: "objectId" },
            currency:  { bsonType: "string" },
            pricingSnapshot: {
              bsonType: "object",
              required: ["baseRatePerHour","ruleApplied","subtotal","discount","tax","total"],
              properties: {
                baseRatePerHour: { bsonType: ["double","int","long"] },
                ruleApplied:     { bsonType: "object" },
                durationMinutes: { bsonType: ["int","long"] },
                subtotal:        { bsonType: ["double","int","long"] },
                discount:        { bsonType: ["double","int","long"] },
                tax:             { bsonType: ["double","int","long"] },
                total:           { bsonType: ["double","int","long"] }
              }
            },
            createdBy: { bsonType: "objectId" },
            createdAt: { bsonType: "date" }
          }
        }
      },
      { $expr: { $lt: ["$start", "$end"] } }
    ]
  }
}); } catch {}
db.bookings.createIndex({ courtId: 1, start: 1, end: 1 });
db.bookings.createIndex({ customerId: 1, start: 1 });
db.bookings.createIndex({ status: 1, start: 1 });

// 10) invoices (giữ nguyên)
try { db.createCollection("invoices", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["bookingId","amount","currency","status"],
      properties: {
        bookingId: { bsonType: "objectId" },
        amount:    { bsonType: ["double","int","long"] },
        currency:  { bsonType: "string" },
        status:    { enum: ["unpaid","paid","void","refunded"] },
        issuedAt:  { bsonType: "date" }
      }
    }
  }
}); } catch {}
db.invoices.createIndex({ bookingId: 1 }, { unique: true });
db.invoices.createIndex({ status: 1 });

// 11) payments (giữ nguyên)
try { db.createCollection("payments", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["invoiceId","provider","method","amount","status","createdAt"],
      properties: {
        invoiceId: { bsonType: "objectId" },
        provider:  { bsonType: "string" },
        method:    { bsonType: "string" },
        amount:    { bsonType: ["double","int","long"] },
        currency:  { bsonType: "string" },
        status:    { enum: ["initiated","succeeded","failed","refunded","chargeback"] },
        txnRef:    { bsonType: "string" },
        createdAt: { bsonType: "date" },
        meta:      { bsonType: "object" }
      }
    }
  }
}); } catch {}
db.payments.createIndex({ invoiceId: 1 });
db.payments.createIndex({ txnRef: 1 }, { unique: true, sparse: true });

// 12) match_requests (giữ nguyên)
try { db.createCollection("match_requests", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["creatorId","sportId","desiredStart","desiredEnd","status","visibility"],
      properties: {
        creatorId:   { bsonType: "objectId" },
        sportId:     { bsonType: "objectId" },
        facilityId:  { bsonType: "objectId" },
        courtId:     { bsonType: "objectId" },
        desiredStart:{ bsonType: "date" },
        desiredEnd:  { bsonType: "date" },
        skillRange: {
          bsonType: "object",
          properties: { min: { bsonType: "int" }, max: { bsonType: "int" } }
        },
        teamSize: { bsonType: "int" },
        location: {
          bsonType: "object",
          properties: {
            type: { enum: ["Point"] },
            coordinates: { bsonType: "array", items: { bsonType: "double" }, minItems: 2, maxItems: 2 }
          }
        },
        radiusKm: { bsonType: "double" },
        visibility: { enum: ["public","friends","private"] },
        status: { enum: ["open","matched","cancelled","expired"] },
        bookingStatus: { bsonType: "string" },
        matchedBookingId: { bsonType: "objectId" },
        createdAt: { bsonType: "date" }
      }
    }
  }
}); } catch {}
db.match_requests.createIndex({ sportId: 1, desiredStart: 1 });
db.match_requests.createIndex({ location: "2dsphere" });

// 13) notifications (mới)
try { db.createCollection("notifications", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["title","status","createdAt"],
      properties: {
        recipientId:  { bsonType: "objectId" },
        recipientRole: { bsonType: "string" },
        facilityId:   { bsonType: "objectId" },
        title:        { bsonType: "string" },
        message:      { bsonType: "string" },
        data:         { bsonType: "object" },
        status:       { enum: ["unread","read"] },
        createdAt:    { bsonType: "date" },
        readAt:       { bsonType: "date" }
      }
    }
  }
}); } catch {}
db.notifications.createIndex({ recipientId: 1, createdAt: -1 });
db.notifications.createIndex({ recipientRole: 1, facilityId: 1, createdAt: -1 });

// 14) audit_logs (giữ nguyên)
try { db.createCollection("audit_logs", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["actorId","action","target","at"],
      properties: {
        actorId: { bsonType: "objectId" },
        action:  { bsonType: "string" },
        target:  { bsonType: "object" },
        changes: { bsonType: "object" },
        at:      { bsonType: "date" }
      }
    }
  }
}); } catch {}
db.audit_logs.createIndex({ at: 1 });
