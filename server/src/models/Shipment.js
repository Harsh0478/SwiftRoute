const mongoose = require('mongoose');

const geoPointSchema = new mongoose.Schema(
  {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], required: true },
    formattedAddress: { type: String, required: true },
    city: { type: String, required: true },
    postalCode: { type: String, required: true },
  },
  { _id: false }
);

const trackingEventSchema = new mongoose.Schema(
  {
    status: {
      type: String,
      enum: [
        'Assigning Courier...',
        'Order Confirmed',
        'Package Picked Up',
        'Processing at Facility',
        'In Transit',
        'Out for Delivery',
        'Delivered',
        'Cancelled',
      ],
      required: true,
    },
    title: { type: String, required: true },
    description: { type: String, required: true },
    timestamp: { type: Date, default: Date.now },
    updatedBy: { type: mongoose.Schema.Types.ObjectId },
  },
  { _id: true }
);

const shipmentSchema = new mongoose.Schema(
  {
    trackingId: { type: String, required: true, unique: true, uppercase: true, index: true },
    customerId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    deliveryAgentId: { type: mongoose.Schema.Types.ObjectId, ref: 'DeliveryAgent', default: null, index: true },
    sender: {
      name: { type: String, required: true },
      phone: { type: String, required: true },
      instructions: { type: String, default: '' },
    },
    receiver: {
      name: { type: String, required: true },
      phone: { type: String, required: true },
      instructions: { type: String, default: '' },
    },
    packageDetails: {
      name: { type: String, required: true },
      category: {
        type: String,
        enum: ['Electronics', 'Documents', 'Apparel', 'Fragile', 'Food & Perishables', 'Other'],
        default: 'Other',
      },
      description: { type: String, default: '' },
      weightKg: { type: Number, required: true, min: 0.1 },
      dimensionsCm: {
        length: { type: Number, default: 10 },
        width: { type: Number, default: 10 },
        height: { type: Number, default: 10 },
      },
      quantity: { type: Number, default: 1, min: 1 },
      imageUrl: { type: String, default: '' },
      isFragile: { type: Boolean, default: false },
    },
    pickupLocation: { type: geoPointSchema, required: true },
    deliveryLocation: { type: geoPointSchema, required: true },
    distanceKm: { type: Number, required: true },
    durationMinutes: { type: Number, required: true },
    deliveryType: {
      type: String,
      enum: ['standard', 'express', 'same_day', 'scheduled'],
      default: 'standard',
    },
    scheduledPickupAt: { type: Date },
    pricing: {
      baseCharge: { type: Number, required: true },
      taxAmount: { type: Number, required: true },
      discountAmount: { type: Number, default: 0 },
      totalAmount: { type: Number, required: true },
      promoCode: { type: String, default: '' },
    },
    shippingCost: { type: Number, required: true },
    paymentMethod: { type: String, enum: ['online', 'cod'], default: 'online' },
    paymentStatus: { type: String, enum: ['pending', 'paid', 'failed', 'refunded'], default: 'pending' },
    shipmentStatus: {
      type: String,
      enum: [
        'Assigning Courier...',
        'Order Confirmed',
        'Package Picked Up',
        'Processing at Facility',
        'In Transit',
        'Out for Delivery',
        'Delivered',
        'Cancelled',
      ],
      default: 'Assigning Courier...',
      index: true,
    },
    estimatedDelivery: { type: Date, required: true },
    currentLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], default: [0, 0] },
    },
    deliveryOtp: { type: String, select: false },
    pickupProofUrl: { type: String, default: '' },
    deliveryProofUrl: { type: String, default: '' },
    cancellationReason: { type: String, default: '' },
    trackingHistory: [trackingEventSchema],
  },
  { timestamps: true }
);

shipmentSchema.index({ pickupLocation: '2dsphere' });
shipmentSchema.index({ deliveryLocation: '2dsphere' });
shipmentSchema.index({ currentLocation: '2dsphere' });

module.exports = mongoose.model('Shipment', shipmentSchema);
