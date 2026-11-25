const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema(
  {
    shipmentId: { type: mongoose.Schema.Types.ObjectId, ref: 'Shipment', required: true, index: true },
    senderId: { type: mongoose.Schema.Types.ObjectId, required: true },
    senderRole: { type: String, enum: ['customer', 'agent'], required: true },
    messageType: { type: String, enum: ['text', 'image', 'system'], default: 'text' },
    text: { type: String, default: '' },
    imageUrl: { type: String, default: '' },
    isRead: { type: Boolean, default: false },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Message', messageSchema);
