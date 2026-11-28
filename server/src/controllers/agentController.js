const jwt = require('jsonwebtoken');
const DeliveryAgent = require('../models/DeliveryAgent');
const Shipment = require('../models/Shipment');
const User = require('../models/User');
const { uploadBufferToCloudinary } = require('../config/cloudinary');
const { sendPushNotification } = require('../services/notificationService');
const {
  ACTIVE_STATUSES,
  syncAgentAvailability,
  findNextAvailableAgent,
  offerShipmentToAgent,
} = require('../services/dispatchService');

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

    // Check if this partner already has an active/pending shipment so GPS pings never mark them free mid-order
    const activeCount = await Shipment.countDocuments({
      deliveryAgentId: req.user.id,
      shipmentStatus: { $in: ACTIVE_STATUSES },
    });

    const update = {
      isOnline,
      isAvailable: isOnline ? activeCount === 0 : true,
      lastSeenAt: isOnline ? new Date() : null,
    };
    if (lat !== undefined && lng !== undefined) {
      update.currentLocation = { type: 'Point', coordinates: [Number(lng), Number(lat)] };
    }
    const agent = await DeliveryAgent.findByIdAndUpdate(req.user.id, update, { new: true });

    // Only offer 1 waiting unassigned shipment if this partner has zero active orders
    let offeredCount = 0;
    if (isOnline && agent && activeCount === 0) {
      const nextWaiting = await Shipment.findOne({
        deliveryAgentId: null,
        shipmentStatus: 'Assigning Courier...',
        declinedAgentIds: { $ne: agent._id },
      }).sort({ createdAt: 1 });

      if (nextWaiting) {
        await offerShipmentToAgent(req.app.get('io'), nextWaiting, agent, agent._id);
        offeredCount = 1;
      }
    }

    const refreshedAgent = await DeliveryAgent.findById(req.user.id);
    res.json({
      success: true,
      agent: refreshedAgent || agent,
      claimedCount: offeredCount,
      hasActiveOrder: activeCount > 0 || offeredCount > 0,
    });
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

exports.acceptShipment = async (req, res, next) => {
  try {
    const shipment = await Shipment.findOne({
      _id: req.params.id,
      deliveryAgentId: req.user.id,
    });
    if (!shipment) {
      return res.status(404).json({ success: false, message: 'Assigned shipment not found' });
    }
    if (shipment.shipmentStatus !== 'Assigning Courier...') {
      return res.status(400).json({
        success: false,
        message: `Shipment is already ${shipment.shipmentStatus}`,
      });
    }

    const agent = await DeliveryAgent.findById(req.user.id);
    shipment.shipmentStatus = 'Order Confirmed';
    shipment.trackingHistory.push({
      status: 'Order Confirmed',
      title: 'Order Accepted by Partner',
      description: `Courier partner ${agent?.name || 'Partner'} accepted your order.`,
      updatedBy: req.user.id,
    });
    await shipment.save();

    await DeliveryAgent.findByIdAndUpdate(req.user.id, { isAvailable: false });

    const populated = await Shipment.findById(shipment._id)
      .populate('customerId', 'name phone avatarUrl')
      .populate('deliveryAgentId', 'name phone avatarUrl vehicleType vehicleNumber rating');

    req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', populated || shipment);

    const customer = await User.findById(shipment.customerId);
    if (customer) {
      await sendPushNotification({
        recipient: customer,
        recipientModel: 'User',
        title: 'Partner Accepted Order',
        body: `${agent?.name || 'Your courier partner'} accepted package #${shipment.trackingId}.`,
        type: 'shipment_update',
        shipmentId: shipment._id,
      });
    }

    res.json({ success: true, shipment: populated || shipment });
  } catch (err) {
    next(err);
  }
};

exports.declineShipment = async (req, res, next) => {
  try {
    const shipment = await Shipment.findOne({
      _id: req.params.id,
      deliveryAgentId: req.user.id,
    });
    if (!shipment) {
      return res.status(404).json({ success: false, message: 'Assigned shipment not found' });
    }
    if (shipment.shipmentStatus !== 'Assigning Courier...') {
      return res.status(400).json({
        success: false,
        message: 'Only pending offers can be declined before acceptance',
      });
    }

    const decliningAgent = await DeliveryAgent.findById(req.user.id);
    if (!shipment.declinedAgentIds.some((id) => String(id) === String(req.user.id))) {
      shipment.declinedAgentIds.push(req.user.id);
    }
    shipment.deliveryAgentId = null;
    shipment.shipmentStatus = 'Assigning Courier...';
    shipment.trackingHistory.push({
      status: 'Assigning Courier...',
      title: 'Reassigning Partner',
      description: `${decliningAgent?.name || 'Partner'} could not take this order. Searching for next available partner.`,
      updatedBy: req.user.id,
    });
    await shipment.save();

    // Unlock the declining partner if they have no other active shipments
    await syncAgentAvailability(req.user.id);

    // Immediately try to offer to the next free nearby partner
    const nextAgent = await findNextAvailableAgent(shipment.pickupLocation.coordinates, {
      excludeAgentIds: shipment.declinedAgentIds,
      allowDevFallback: true,
    });

    if (nextAgent) {
      await offerShipmentToAgent(req.app.get('io'), shipment, nextAgent, req.user.id);
    } else {
      req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', shipment);
    }

    res.json({
      success: true,
      reassigned: Boolean(nextAgent),
      shipment,
    });
  } catch (err) {
    next(err);
  }
};

exports.updateShipmentStatus = async (req, res, next) => {
  try {
    const { status, description, deliveryOtp } = req.body;
    const shipment = await Shipment.findOne({ _id: req.params.id, deliveryAgentId: req.user.id }).select('+deliveryOtp');
    if (!shipment) return res.status(404).json({ success: false, message: 'Assigned shipment not found' });

    if (shipment.shipmentStatus === 'Assigning Courier...') {
      return res.status(400).json({
        success: false,
        message: 'Please accept the order before updating delivery status.',
      });
    }

    if (status === 'Delivered' && shipment.deliveryOtp && shipment.deliveryOtp !== deliveryOtp) {
      return res.status(400).json({ success: false, message: 'Invalid receiver delivery OTP' });
    }

    const defaultDescriptions = {
      'Going to Collect Package': 'Partner is heading to pickup location to collect the package.',
      'Package Picked Up': 'Package has been collected from the sender.',
      'In Transit': 'Package is in transit toward the destination.',
      'Out for Delivery': 'Partner is out for final delivery to the receiver.',
      Delivered: 'Package delivered and verified with receiver OTP.',
    };

    shipment.shipmentStatus = status;
    shipment.trackingHistory.push({
      status,
      title: status,
      description: description || defaultDescriptions[status] || `Package status updated to ${status}`,
      updatedBy: req.user.id,
    });

    if (status === 'Delivered') {
      if (shipment.paymentMethod === 'cod') shipment.paymentStatus = 'paid';
      await DeliveryAgent.findByIdAndUpdate(req.user.id, {
        $inc: { totalDeliveries: 1, totalEarnings: Math.round(shipment.shippingCost * 0.75) },
      });
    }

    await shipment.save();

    if (status === 'Delivered' || status === 'Cancelled') {
      await syncAgentAvailability(req.user.id);
    }

    const populated = await Shipment.findById(shipment._id)
      .populate('customerId', 'name phone avatarUrl')
      .populate('deliveryAgentId', 'name phone avatarUrl vehicleType vehicleNumber rating');

    req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', populated || shipment);

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

    res.json({ success: true, shipment: populated || shipment });
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
