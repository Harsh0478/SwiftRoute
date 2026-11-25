const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, index: true },
    phone: { type: String, required: true, unique: true, trim: true, index: true },
    password: { type: String, required: true, minlength: 6, select: false },
    avatarUrl: { type: String, default: '' },
    role: { type: String, enum: ['customer', 'admin', 'superadmin'], default: 'customer' },
    isVerified: { type: Boolean, default: false },
    otpCode: { type: String, select: false },
    otpExpiresAt: { type: Date, select: false },
    refreshTokenHash: { type: String, select: false },
    fcmTokens: [{ type: String }],
    savedCards: [{ brand: String, last4: String, expiry: String, tokenId: String }],
    preferences: {
      darkMode: { type: Boolean, default: false },
      pushNotifications: { type: Boolean, default: true },
    },
  },
  { timestamps: true }
);

userSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  this.password = await bcrypt.hash(this.password, 12);
  next();
});

userSchema.methods.comparePassword = function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

module.exports = mongoose.model('User', userSchema);
