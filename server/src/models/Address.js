const mongoose = require('mongoose');

const addressSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    label: { type: String, enum: ['Home', 'Office', 'Warehouse', 'Other'], default: 'Home' },
    contactName: { type: String, required: true },
    contactPhone: { type: String, required: true },
    streetAddress: { type: String, required: true },
    city: { type: String, required: true },
    state: { type: String, required: true },
    postalCode: { type: String, required: true },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true },
    },
    isDefault: { type: Boolean, default: false },
  },
  { timestamps: true }
);

addressSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('Address', addressSchema);
