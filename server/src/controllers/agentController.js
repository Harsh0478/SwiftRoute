const jwt = require('jsonwebtoken');
const DeliveryAgent = require('../models/DeliveryAgent');
const Shipment = require('../models/Shipment');
const User = require('../models/User');
const { uploadBufferToCloudinary } = require('../config/cloudinary');
const { sendPushNotification } = require('../services/notificationService');

exports.registerAgent = async (req, res, next) => {
  try {
    const { name, email, phone, password, vehicleType, vehicleNumber, licenseNumber } = req.body;
    const agent = await DeliveryAgent.create({
      name,
      email,
      phone,
      password,
      vehicleType,
      vehicleNumber,
      licenseNumber,
      kycStatus: 'approved',
    });
    const accessToken = jwt.sign({ id: agent._id, role: 'agent' }, process.env.JWT_ACCESS_SECRET, { expiresIn: '1d' });
    res.status(201).json({ success: true, accessToken, agent });
  } catch (err) {
    next(err);
  }
};

exports.loginAgent = async (req, res, next) => {
  try {
    const { email, password, fcmToken } = req.body;
    const agent = await DeliveryAgent.findOne({ email }).select('+password');
    if (!agent || !(await agent.comparePassword(password))) {
      return res.status(401).json({ success: false, message: 'Invalid agent credentials' });
    }
    if (fcmToken && !agent.fcmTokens.includes(fcmToken)) {
      agent.fcmTokens.push(fcmToken);
      await agent.save();
    }
    const accessToken = jwt.sign({ id: agent._id, role: 'agent' }, process.env.JWT_ACCESS_SECRET, { expiresIn: '1d' });
    res.json({ success: true, accessToken, agent });
  } catch (err) {
    next(err);
  }
};

exports.toggleAvailability = async (req, res, next) => {
  try {
    const { isOnline, lat, lng } = req.body;
    const update = { isOnline, isAvailable: true };
    if (lat !== undefined && lng !== undefined) {
      update.currentLocation = { type: 'Point', coordinates: [Number(lng), Number(lat)] };
    }
    const agent = await DeliveryAgent.findByIdAndUpdate(req.user.id, update, { new: true });

    let claimedShipments = [];
    if (isOnline && agent) {
      const unassigned = await Shipment.find({
        deliveryAgentId: null,
        shipmentStatus: 'Assigning Courier...',
      }).sort({ createdAt: 1 });

      for (const shipment of unassigned) {
        shipment.deliveryAgentId = agent._id;
        shipment.shipmentStatus = 'Order Confirmed';
        shipment.trackingHistory.push({
          status: 'Order Confirmed',
          title: 'Order Confirmed',
          description: `Courier partner ${agent.name} accepted your pickup.`,
          updatedBy: agent._id,
        });
        await shipment.save();
        claimedShipments.push(shipment);

        req.app.get('io')?.to(`user:${agent._id}`).emit('agent:new_assignment', shipment);
        req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', shipment);
      }
    }

    res.json({ success: true, agent, claimedCount: claimedShipments.length });
  } catch (err) {
    next(err);
  }
};

exports.getAssignments = async (req, res, next) => {
  try {
    const shipments = await Shipment.find({
      deliveryAgentId: req.user.id,
      shipmentStatus: { $nin: ['Delivered', 'Cancelled'] },
    })
      .populate('customerId', 'name phone avatarUrl')
      .sort({ createdAt: -1 });
    res.json({ success: true, shipments });
  } catch (err) {
    next(err);
  }
};

exports.updateShipmentStatus = async (req, res, next) => {
  try {
    const { status, description, deliveryOtp } = req.body;
    const shipment = await Shipment.findOne({ _id: req.params.id, deliveryAgentId: req.user.id }).select('+deliveryOtp');
    if (!shipment) return res.status(404).json({ success: false, message: 'Assigned shipment not found' });

    if (status === 'Delivered' && shipment.deliveryOtp && shipment.deliveryOtp !== deliveryOtp) {
      return res.status(400).json({ success: false, message: 'Invalid receiver delivery OTP' });
    }

    shipment.shipmentStatus = status;
    shipment.trackingHistory.push({
      status,
      title: status,
      description: description || `Package status updated to ${status}`,
      updatedBy: req.user.id,
    });

    if (status === 'Delivered') {
      if (shipment.paymentMethod === 'cod') shipment.paymentStatus = 'paid';
      await DeliveryAgent.findByIdAndUpdate(req.user.id, {
        $inc: { totalDeliveries: 1, totalEarnings: Math.round(shipment.shippingCost * 0.75) },
      });
    }

    await shipment.save();

    req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', shipment);

    const customer = await User.findById(shipment.customerId);
    if (customer) {
      await sendPushNotification({
        recipient: customer,
        recipientModel: 'User',
        title: `Shipment ${status}`,
        body: `Package #${shipment.trackingId} is now ${status}.`,
        type: status === 'Delivered' ? 'delivery' : 'shipment_update',
        shipmentId: shipment._id,
      });
    }

    res.json({ success: true, shipment });
  } catch (err) {
    next(err);
  }
};

exports.uploadProof = async (req, res, next) => {
  try {
    const { proofType } = req.body;
    if (!req.file) return res.status(400).json({ success: false, message: 'Proof image is required' });

    const uploaded = await uploadBufferToCloudinary(req.file.buffer, 'swiftroute/proofs');
    const field = proofType === 'pickup' ? 'pickupProofUrl' : 'deliveryProofUrl';

    const shipment = await Shipment.findOneAndUpdate(
      { _id: req.params.id, deliveryAgentId: req.user.id },
      { $set: { [field]: uploaded.secure_url } },
      { new: true }
    );
    res.json({ success: true, proofUrl: uploaded.secure_url, shipment });
  } catch (err) {
    next(err);
  }
};
