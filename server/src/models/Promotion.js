const mongoose = require('mongoose');

const promotionSchema = new mongoose.Schema(
  {
    code: { type: String, required: true, unique: true, uppercase: true, trim: true },
    title: { type: String, required: true },
    description: { type: String, required: true },
    discountType: { type: String, enum: ['percentage', 'flat'], required: true },
    discountValue: { type: Number, required: true, min: 1 },
    maxDiscountAmount: { type: Number, default: 200 },
    minOrderAmount: { type: Number, default: 100 },
    validFrom: { type: Date, required: true },
    validUntil: { type: Date, required: true },
    usageLimit: { type: Number, default: 1000 },
    usedCount: { type: Number, default: 0 },
    isActive: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Promotion', promotionSchema);
