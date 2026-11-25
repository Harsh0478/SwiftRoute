const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema(
  {
    recipientId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
    recipientModel: { type: String, enum: ['User', 'DeliveryAgent'], required: true },
    title: { type: String, required: true },
    body: { type: String, required: true },
    type: {
      type: String,
      enum: ['shipment_update', 'pickup', 'delivery', 'payment', 'promo'],
      default: 'shipment_update',
    },
    shipmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Shipment', default: null },
    isRead: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Notification', notificationSchema);
