const jwt = require('jsonwebtoken');
const Shipment = require('../models/Shipment');
const DeliveryAgent = require('../models/DeliveryAgent');
const TrackingLocation = require('../models/Tracking');
const Message = require('../models/Message');

const initializeSockets = (io) => {
  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.headers?.authorization?.split(' ')[1];
      if (!token) return next(new Error('Authentication error: Token required'));
      const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET);
      socket.user = { id: decoded.id, role: decoded.role };
      next();
    } catch (err) {
      next(new Error('Authentication error: Invalid token'));
    }
  });

  io.on('connection', (socket) => {
    socket.join(`user:${socket.user.id}`);

    socket.on('shipment:join', async ({ shipmentId }, ack) => {
      try {
        const shipment = await Shipment.findById(shipmentId);
        if (!shipment) return ack?.({ ok: false, message: 'Shipment not found' });

        const isOwner = String(shipment.customerId) === String(socket.user.id);
        const isAssignedAgent = shipment.deliveryAgentId && String(shipment.deliveryAgentId) === String(socket.user.id);
        const isAdmin = ['admin', 'superadmin'].includes(socket.user.role);

        if (!isOwner && !isAssignedAgent && !isAdmin) {
          return ack?.({ ok: false, message: 'Unauthorized room access' });
        }

        socket.join(`shipment:${shipmentId}`);
        ack?.({ ok: true, shipmentId });
      } catch (err) {
        ack?.({ ok: false, message: err.message });
      }
    });

    socket.on('agent:location_update', async ({ shipmentId, lat, lng, heading = 0, speedKmh = 0 }) => {
      try {
        if (socket.user.role !== 'agent') return;
        const shipment = await Shipment.findById(shipmentId);
        if (!shipment || String(shipment.deliveryAgentId) !== String(socket.user.id)) return;

        const coordinates = [Number(lng), Number(lat)];

        await Promise.all([
          DeliveryAgent.findByIdAndUpdate(socket.user.id, {
            currentLocation: { type: 'Point', coordinates },
            heading,
          }),
          Shipment.findByIdAndUpdate(shipmentId, {
            currentLocation: { type: 'Point', coordinates },
          }),
          TrackingLocation.create({
            shipmentId,
            agentId: socket.user.id,
            location: { type: 'Point', coordinates },
            speedKmh,
            heading,
          }),
        ]);

        io.to(`shipment:${shipmentId}`).emit('shipment:location_updated', {
          shipmentId,
          lat: Number(lat),
          lng: Number(lng),
          heading,
          speedKmh,
          updatedAt: new Date().toISOString(),
        });
      } catch (err) {
        console.error('Socket location update error:', err.message);
      }
    });

    socket.on('chat:send_message', async ({ shipmentId, text = '', imageUrl = '', messageType = 'text' }, ack) => {
      try {
        const shipment = await Shipment.findById(shipmentId);
        if (!shipment) return ack?.({ ok: false, message: 'Shipment not found' });

        const isOwner = String(shipment.customerId) === String(socket.user.id);
        const isAssignedAgent = shipment.deliveryAgentId && String(shipment.deliveryAgentId) === String(socket.user.id);
        if (!isOwner && !isAssignedAgent) return ack?.({ ok: false, message: 'Forbidden' });

        const message = await Message.create({
          shipmentId,
          senderId: socket.user.id,
          senderRole: socket.user.role === 'agent' ? 'agent' : 'customer',
          messageType,
          text,
          imageUrl,
        });

        io.to(`shipment:${shipmentId}`).emit('chat:new_message', message);
        ack?.({ ok: true, message });
      } catch (err) {
        ack?.({ ok: false, message: err.message });
      }
    });

    socket.on('chat:mark_read', async ({ shipmentId }) => {
      const readerRole = socket.user.role === 'agent' ? 'agent' : 'customer';
      await Message.updateMany(
        { shipmentId, senderRole: { $ne: readerRole }, isRead: false },
        { $set: { isRead: true } }
      );
      io.to(`shipment:${shipmentId}`).emit('chat:messages_read', { shipmentId, readerRole });
    });
  });
};

module.exports = initializeSockets;
