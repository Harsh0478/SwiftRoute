const Shipment = require('../models/Shipment');
const Promotion = require('../models/Promotion');
const DeliveryAgent = require('../models/DeliveryAgent');
const { generateTrackingId, generateDeliveryOtp } = require('../utils/generateTrackingId');
const calculateDeliveryPrice = require('../utils/calculateDeliveryPrice');
const { uploadBufferToCloudinary } = require('../config/cloudinary');
const { sendPushNotification } = require('../services/notificationService');

const NEARBY_COURIER_RADIUS_KM = 18;

function haversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function calculateEstimatedDurationMinutes(distanceKm, deliveryType) {
  const safeDistance = Math.max(Number(distanceKm) || 2, 2);
  if (deliveryType === 'same_day') {
    return Math.max(45, Math.round((safeDistance / 38) * 60 + 40));
  }
  if (deliveryType === 'express') {
    const speed = safeDistance <= 30 ? 30 : 48;
    const buffer = safeDistance <= 30 ? 60 : 180;
    return Math.max(90, Math.round((safeDistance / speed) * 60 + buffer));
  }
  const speed = safeDistance <= 30 ? 22 : 32;
  const buffer = safeDistance <= 30 ? 120 : 480;
  return Math.max(150, Math.round((safeDistance / speed) * 60 + buffer));
}

async function findNearbyAgents(pickupCoords, radiusKm = NEARBY_COURIER_RADIUS_KM) {
  const [pickupLng, pickupLat] = pickupCoords;
  const maxMeters = radiusKm * 1000;

  try {
    const activeThreshold = new Date(Date.now() - 3 * 60 * 1000);
    const agents = await DeliveryAgent.find({
      isOnline: true,
      isAvailable: true,
      kycStatus: 'approved',
      lastSeenAt: { $gte: activeThreshold },
      currentLocation: {
        $near: {
          $geometry: { type: 'Point', coordinates: [Number(pickupLng), Number(pickupLat)] },
          $maxDistance: maxMeters,
        },
      },
    }).limit(10);

    return agents.map((agent) => {
      const [aLng, aLat] = agent.currentLocation?.coordinates || [0, 0];
      return {
        agent,
        distanceKm: Number(haversineKm(Number(pickupLat), Number(pickupLng), aLat, aLng).toFixed(2)),
      };
    });
  } catch (_) {
    // Fallback Haversine filter if 2dsphere index is still building
    const onlineAgents = await DeliveryAgent.find({
      isOnline: true,
      isAvailable: true,
      kycStatus: 'approved',
      lastSeenAt: { $gte: activeThreshold },
    });

    return onlineAgents
      .map((agent) => {
        const [aLng, aLat] = agent.currentLocation?.coordinates || [0, 0];
        if (aLat === 0 && aLng === 0) return null;
        const dist = haversineKm(Number(pickupLat), Number(pickupLng), aLat, aLng);
        return dist <= radiusKm ? { agent, distanceKm: Number(dist.toFixed(2)) } : null;
      })
      .filter(Boolean)
      .sort((a, b) => a.distanceKm - b.distanceKm);
  }
}

exports.checkNearbyAgents = async (req, res, next) => {
  try {
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    const requestedRadius = Number(req.query.radiusKm) || NEARBY_COURIER_RADIUS_KM;
    const radiusKm = Math.min(Math.max(requestedRadius, 15), 20);

    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ success: false, message: 'Valid lat and lng query parameters are required.' });
    }

    const nearby = await findNearbyAgents([lng, lat], radiusKm);
    const nearest = nearby[0] || null;

    res.json({
      success: true,
      available: nearby.length > 0,
      count: nearby.length,
      radiusKm,
      nearestAgent: nearest
        ? {
            id: nearest.agent._id,
            name: nearest.agent.name,
            vehicleType: nearest.agent.vehicleType,
            distanceKm: nearest.distanceKm,
          }
        : null,
    });
  } catch (err) {
    next(err);
  }
};

exports.createShipment = async (req, res, next) => {
  try {
    const payload = typeof req.body.data === 'string' ? JSON.parse(req.body.data) : req.body;
    const {
      sender,
      receiver,
      packageDetails,
      pickupLocation,
      deliveryLocation,
      distanceKm = 8.5,
      deliveryType = 'standard',
      scheduledPickupAt,
      paymentMethod = 'online',
      promoCode = '',
      developmentMode = true,
    } = payload;

    const isDevMode = developmentMode === true || developmentMode === 'true';

    if (!sender?.name?.trim() || !sender?.phone?.trim() || !pickupLocation?.formattedAddress?.trim()) {
      return res.status(400).json({
        success: false,
        message: 'Sender name, phone, and pickup address are required.',
      });
    }

    if (!receiver?.name?.trim() || !receiver?.phone?.trim() || !deliveryLocation?.formattedAddress?.trim()) {
      return res.status(400).json({
        success: false,
        message: 'Receiver name, phone, and delivery address are required.',
      });
    }

    // 1. Search for nearest online & available partner within 18 km (15-20 km radius)
    const nearby = await findNearbyAgents(pickupLocation.coordinates, NEARBY_COURIER_RADIUS_KM);
    let nearestAgent = nearby[0]?.agent || null;

    if (!isDevMode && !nearestAgent) {
      return res.status(400).json({
        success: false,
        code: 'NO_COURIER_NEARBY',
        message:
          'No delivery partner available within 18 km of pickup location. Enable Development Mode in Profile to send directly.',
      });
    }

    // 2. In Development Mode, fall back to any online & available partner so testing auto-assigns
    if (isDevMode && !nearestAgent) {
      nearestAgent = await DeliveryAgent.findOne({
        isOnline: true,
        isAvailable: true,
        kycStatus: 'approved',
        lastSeenAt: { $gte: new Date(Date.now() - 3 * 60 * 1000) },
      }).sort({ lastSeenAt: -1 });
    }

    let imageUrl = packageDetails.imageUrl || '';
    if (req.file) {
      const uploaded = await uploadBufferToCloudinary(req.file.buffer, 'swiftroute/packages');
      imageUrl = uploaded.secure_url;
    }

    let promotion = null;
    if (promoCode) {
      promotion = await Promotion.findOne({
        code: promoCode.toUpperCase(),
        isActive: true,
        validUntil: { $gte: new Date() },
      });
    }

    const pricing = calculateDeliveryPrice({
      distanceKm,
      weightKg: packageDetails.weightKg,
      deliveryType,
      isFragile: packageDetails.isFragile,
      promotion,
    });

    const calculatedMinutes = calculateEstimatedDurationMinutes(distanceKm, deliveryType);
    const estimatedDelivery = new Date(Date.now() + calculatedMinutes * 60 * 1000);

    const initialStatus = nearestAgent ? 'Order Confirmed' : 'Assigning Courier...';

    const shipment = await Shipment.create({
      trackingId: generateTrackingId(),
      customerId: req.user.id,
      deliveryAgentId: nearestAgent ? nearestAgent._id : null,
      sender,
      receiver,
      packageDetails: { ...packageDetails, imageUrl },
      pickupLocation,
      deliveryLocation,
      distanceKm,
      durationMinutes: calculatedMinutes,
      deliveryType,
      scheduledPickupAt,
      pricing: { ...pricing, promoCode: promotion ? promotion.code : '' },
      shippingCost: pricing.totalAmount,
      paymentMethod,
      paymentStatus: 'pending',
      shipmentStatus: initialStatus,
      estimatedDelivery,
      currentLocation: { type: 'Point', coordinates: pickupLocation.coordinates },
      deliveryOtp: generateDeliveryOtp(),
      trackingHistory: [
        {
          status: initialStatus,
          title: initialStatus,
          description: nearestAgent
            ? `Assigned to courier partner ${nearestAgent.name}.`
            : 'Searching for an available delivery partner near pickup.',
          updatedBy: req.user.id,
        },
      ],
    });

    if (nearestAgent) {
      req.app.get('io')?.to(`user:${nearestAgent._id}`).emit('agent:new_assignment', shipment);
      await sendPushNotification({
        recipient: nearestAgent,
        recipientModel: 'DeliveryAgent',
        title: 'New Pickup Assigned',
        body: `Package #${shipment.trackingId} is ready for pickup in ${pickupLocation.city}.`,
        type: 'pickup',
        shipmentId: shipment._id,
      });
    }

    res.status(201).json({ success: true, shipment });
  } catch (err) {
    next(err);
  }
};

exports.getCustomerShipments = async (req, res, next) => {
  try {
    const { status, search, page = 1, limit = 15 } = req.query;
    const query = { customerId: req.user.id };

    if (status && status !== 'All') {
      if (status === 'In Progress') {
        query.shipmentStatus = {
          $in: [
            'Assigning Courier...',
            'Order Confirmed',
            'Package Picked Up',
            'Processing at Facility',
            'In Transit',
            'Out for Delivery',
          ],
        };
      } else {
        query.shipmentStatus = status;
      }
    }

    if (search) {
      query.$or = [
        { trackingId: { $regex: search, $options: 'i' } },
        { 'packageDetails.name': { $regex: search, $options: 'i' } },
        { 'deliveryLocation.city': { $regex: search, $options: 'i' } },
      ];
    }

    const skip = (Number(page) - 1) * Number(limit);
    const [shipments, total] = await Promise.all([
      Shipment.find(query)
        .select('+deliveryOtp')
        .populate('deliveryAgentId', 'name phone avatarUrl vehicleType vehicleNumber rating')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(Number(limit)),
      Shipment.countDocuments(query),
    ]);

    res.json({
      success: true,
      shipments,
      pagination: { total, page: Number(page), pages: Math.ceil(total / Number(limit)) },
    });
  } catch (err) {
    next(err);
  }
};

exports.trackByTrackingId = async (req, res, next) => {
  try {
    const shipment = await Shipment.findOne({ trackingId: req.params.trackingId.toUpperCase() })
      .select('+deliveryOtp')
      .populate(
        'deliveryAgentId',
        'name phone avatarUrl vehicleType vehicleNumber rating currentLocation heading'
      );
    if (!shipment) return res.status(404).json({ success: false, message: 'Tracking ID not found' });
    res.json({ success: true, shipment });
  } catch (err) {
    next(err);
  }
};

exports.cancelShipment = async (req, res, next) => {
  try {
    const shipment = await Shipment.findOne({ _id: req.params.id, customerId: req.user.id });
    if (!shipment) return res.status(404).json({ success: false, message: 'Shipment not found' });

    if (!['Assigning Courier...', 'Order Confirmed', 'Package Picked Up'].includes(shipment.shipmentStatus)) {
      return res.status(400).json({ success: false, message: 'Shipment in transit cannot be cancelled' });
    }

    shipment.shipmentStatus = 'Cancelled';
    shipment.cancellationReason = req.body.reason || 'Cancelled by customer';
    shipment.trackingHistory.push({
      status: 'Cancelled',
      title: 'Shipment Cancelled',
      description: shipment.cancellationReason,
      updatedBy: req.user.id,
    });
    await shipment.save();

    req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', shipment);
    res.json({ success: true, shipment });
  } catch (err) {
    next(err);
  }
};
