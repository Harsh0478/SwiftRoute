const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const deliveryAgentSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    phone: { type: String, required: true, unique: true, trim: true },
    password: { type: String, required: true, minlength: 6, select: false },
    avatarUrl: { type: String, default: '' },
    vehicleType: { type: String, enum: ['bike', 'scooter', 'van', 'truck'], required: true },
    vehicleNumber: { type: String, required: true, uppercase: true, trim: true },
    licenseNumber: { type: String, required: true, trim: true },
    kycStatus: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'approved' },
    isOnline: { type: Boolean, default: false, index: true },
    lastSeenAt: { type: Date, default: null, index: true },
    isAvailable: { type: Boolean, default: true, index: true },
    currentLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], default: [0, 0] },
    },
    heading: { type: Number, default: 0 },
    rating: { type: Number, default: 5.0, min: 1, max: 5 },
    totalDeliveries: { type: Number, default: 0 },
    totalEarnings: { type: Number, default: 0 },
    refreshTokenHash: { type: String, select: false },
    fcmTokens: [{ type: String }],
  },
  { timestamps: true }
);

deliveryAgentSchema.index({ currentLocation: '2dsphere' });

deliveryAgentSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  this.password = await bcrypt.hash(this.password, 12);
  next();
});

deliveryAgentSchema.methods.comparePassword = function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

module.exports = mongoose.model('DeliveryAgent', deliveryAgentSchema);
