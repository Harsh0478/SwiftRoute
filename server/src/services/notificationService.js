const admin = require('../config/firebase');
const Notification = require('../models/Notification');

const sendPushNotification = async ({ recipient, recipientModel, title, body, type = 'shipment_update', shipmentId = null }) => {
  const notification = await Notification.create({
    recipientId: recipient._id,
    recipientModel,
    title,
    body,
    type,
    shipmentId,
  });

  if (recipient.fcmTokens && recipient.fcmTokens.length > 0 && admin.apps.length > 0) {
    try {
      await admin.messaging().sendEachForMulticast({
        tokens: recipient.fcmTokens,
        notification: { title, body },
        data: { type, shipmentId: shipmentId ? String(shipmentId) : '' },
      });
    } catch (err) {
      console.error('FCM multicast error:', err.message);
    }
  }

  return notification;
};

module.exports = { sendPushNotification };
