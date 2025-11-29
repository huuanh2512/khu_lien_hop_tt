// Pricing calculation helper based on price_profiles + voucher + membership + tax
import { ObjectId } from 'mongodb';

function timeToMinutes(t) {
  // 'HH:MM' -> minutes since 00:00
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}

function getDayOfWeek(date) {
  // 0 = Sunday .. 6 = Saturday
  return date.getDay();
}

export async function quotePrice({ db, facilityId, sportId, courtId, start, end, currency, user }) {
  const profile = await db.collection('price_profiles').findOne({
    $or: [
      { courtId: new ObjectId(courtId) },
      { courtId: { $exists: false } },
    ],
    facilityId: new ObjectId(facilityId),
    sportId: new ObjectId(sportId),
    active: { $ne: false },
  });

  if (!profile) {
    // fallback: no profile
    const durationMin = Math.max(0, Math.round((end - start) / 60000));
    const baseRate = 0;
    const subtotal = (baseRate / 60) * durationMin;
    return {
      baseRatePerHour: baseRate,
      ruleApplied: {},
      durationMinutes: durationMin,
      subtotal,
      discount: 0,
      tax: 0,
      total: subtotal,
      currency,
    };
  }

  const baseRate = Number(profile.baseRatePerHour || 0);
  const durationMin = Math.max(0, Math.round((end - start) / 60000));
  const dow = getDayOfWeek(start);
  const startMin = start.getHours() * 60 + start.getMinutes();
  const endMin = end.getHours() * 60 + end.getMinutes();

  // find first matched rule
  let appliedRule = null;
  if (Array.isArray(profile.rules)) {
    for (const r of profile.rules) {
      const okDow = Array.isArray(r.daysOfWeek) ? r.daysOfWeek.includes(dow) : true;
      const st = r.startTime ? timeToMinutes(r.startTime) : 0;
      const et = r.endTime ? timeToMinutes(r.endTime) : 24 * 60;
      const overlap = startMin < et && endMin > st; // simple overlap
      if (okDow && overlap) {
        appliedRule = r; break;
      }
    }
  }

  let hourly = baseRate;
  if (appliedRule) {
    if (appliedRule.rateType === 'multiplier') {
      hourly = baseRate * Number(appliedRule.value || 1);
    } else if (appliedRule.rateType === 'fixed') {
      hourly = Number(appliedRule.value || baseRate);
    }
  }

  const subtotal = (hourly / 60) * durationMin;

  // Membership discount
  let membershipPercent = 0;
  if (user?.membership?.tier && Array.isArray(profile.membershipDiscounts)) {
    const md = profile.membershipDiscounts.find(d => d.tier === user.membership.tier);
    if (md?.percentOff) membershipPercent = Number(md.percentOff);
  }

  // Voucher discount (validated outside)
  // This helper expects caller to pass voucherPercent if needed in future; for now only membership

  const membershipDiscount = subtotal * (membershipPercent / 100);
  const discounted = Math.max(0, subtotal - membershipDiscount);

  const taxPercent = Number(profile.taxPercent || 0);
  const tax = discounted * (taxPercent / 100);
  const total = discounted + tax;

  return {
    baseRatePerHour: baseRate,
  ruleApplied: appliedRule ? { ...appliedRule } : {},
    durationMinutes: durationMin,
    subtotal: Number(subtotal.toFixed(2)),
    discount: Number(membershipDiscount.toFixed(2)),
    tax: Number(tax.toFixed(2)),
    total: Number(total.toFixed(2)),
    currency,
  };
}
