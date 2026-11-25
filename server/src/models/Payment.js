const mongoose = require('mongoose');

const paymentSchema = new mongoose.Schema(
  {
    shipmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Shipment', required: true, index: true },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    razorpayOrderId: { type: String, required: true, unique: true, index: true },
    razorpayPaymentId: { type: String, default: '' },
    razorpaySignature: { type: String, default: '' },
    amount: { type: Number, required: true },
    currency: { type: String, default: 'INR' },
    status: { type: String, enum: ['created', 'captured', 'failed', 'refunded'], default: 'created' },
    method: { type: String, default: 'razorpay' },
    refundId: { type: String, default: '' },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Payment', paymentSchema);
