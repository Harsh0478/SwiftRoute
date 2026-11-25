const mongoose = require('mongoose');

const trackingLocationSchema = new mongoose.Schema(
  {
    shipmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Shipment', required: true, index: true },
    agentId: { type: mongoose.Schema.Types.ObjectId, ref: 'DeliveryAgent', required: true },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true },
    },
    speedKmh: { type: Number, default: 0 },
    heading: { type: Number, default: 0 },
    recordedAt: { type: Date, default: Date.now, index: true },
  },
  { collection: 'trackinglocations' }
);

trackingLocationSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('TrackingLocation', trackingLocationSchema);
