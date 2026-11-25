const Shipment = require('../models/Shipment');
const Promotion = require('../models/Promotion');
const DeliveryAgent = require('../models/DeliveryAgent');
const { generateTrackingId, generateDeliveryOtp } = require('../utils/generateTrackingId');
const calculateDeliveryPrice = require('../utils/calculateDeliveryPrice');
const { uploadBufferToCloudinary } = require('../config/cloudinary');
const { sendPushNotification } = require('../services/notificationService');

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
      durationMinutes = 35,
      deliveryType = 'standard',
      scheduledPickupAt,
      paymentMethod = 'online',
      promoCode = '',
    } = payload;

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

    const hoursToAdd = deliveryType === 'same_day' ? 4 : deliveryType === 'express' ? 24 : 48;
    const estimatedDelivery = new Date(Date.now() + hoursToAdd * 3600 * 1000);

    // 1. Prefer nearest online & available partner within 25 km
    let nearestAgent = await DeliveryAgent.findOne({
      isOnline: true,
      isAvailable: true,
      kycStatus: 'approved',
      currentLocation: {
        $near: {
          $geometry: { type: 'Point', coordinates: pickupLocation.coordinates },
          $maxDistance: 25000,
        },
      },
    });

    // 2. Fallback: pick any online & available partner so emulator / cross-city tests auto-assign
    if (!nearestAgent) {
      nearestAgent = await DeliveryAgent.findOne({
        isOnline: true,
        isAvailable: true,
        kycStatus: 'approved',
      }).sort({ updatedAt: -1 });
    }

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
      durationMinutes,
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
    const shipment = await Shipment.findOne({ trackingId: req.params.trackingId.toUpperCase() }).populate(
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
