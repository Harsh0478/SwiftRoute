const Shipment = require('../models/Shipment');
const DeliveryAgent = require('../models/DeliveryAgent');
const { sendPushNotification } = require('./notificationService');

const NEARBY_COURIER_RADIUS_KM = 18;
const ACTIVE_STATUSES = [
  'Assigning Courier...',
  'Order Confirmed',
  'Going to Collect Package',
  'Package Picked Up',
  'Processing at Facility',
  'In Transit',
  'Out for Delivery',
];

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

async function getBusyAgentIds() {
  const busy = await Shipment.distinct('deliveryAgentId', {
    deliveryAgentId: { $ne: null },
    shipmentStatus: { $in: ACTIVE_STATUSES },
  });
  return busy.filter(Boolean);
}

async function syncAgentAvailability(agentId) {
  if (!agentId) return true;
  const activeCount = await Shipment.countDocuments({
    deliveryAgentId: agentId,
    shipmentStatus: { $in: ACTIVE_STATUSES },
  });
  const isAvailable = activeCount === 0;
  await DeliveryAgent.findByIdAndUpdate(agentId, { isAvailable });
  return isAvailable;
}

async function findNearbyAvailableAgents(
  pickupCoords,
  { radiusKm = NEARBY_COURIER_RADIUS_KM, excludeAgentIds = [] } = {}
) {
  const [pickupLng, pickupLat] = pickupCoords;
  const maxMeters = radiusKm * 1000;
  const activeThreshold = new Date(Date.now() - 3 * 60 * 1000);
  const busyAgentIds = await getBusyAgentIds();
  const excluded = [...busyAgentIds, ...excludeAgentIds];

  const baseFilter = {
    _id: { $nin: excluded },
    isOnline: true,
    isAvailable: true,
    kycStatus: 'approved',
    lastSeenAt: { $gte: activeThreshold },
  };

  try {
    const agents = await DeliveryAgent.find({
      ...baseFilter,
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
    const onlineAgents = await DeliveryAgent.find(baseFilter);
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

async function findNextAvailableAgent(
  pickupCoords,
  { radiusKm = NEARBY_COURIER_RADIUS_KM, excludeAgentIds = [], allowDevFallback = true } = {}
) {
  const nearby = await findNearbyAvailableAgents(pickupCoords, { radiusKm, excludeAgentIds });
  if (nearby.length > 0) {
    return nearby[0].agent;
  }

  if (!allowDevFallback) return null;

  const activeThreshold = new Date(Date.now() - 3 * 60 * 1000);
  const busyAgentIds = await getBusyAgentIds();
  const excluded = [...busyAgentIds, ...excludeAgentIds];

  return DeliveryAgent.findOne({
    _id: { $nin: excluded },
    isOnline: true,
    isAvailable: true,
    kycStatus: 'approved',
    lastSeenAt: { $gte: activeThreshold },
  }).sort({ lastSeenAt: -1 });
}

async function offerShipmentToAgent(io, shipment, agent, updatedBy) {
  shipment.deliveryAgentId = agent._id;
  shipment.shipmentStatus = 'Assigning Courier...';
  shipment.trackingHistory.push({
    status: 'Assigning Courier...',
    title: 'Partner Assigned — Awaiting Acceptance',
    description: `Assigned to courier partner ${agent.name}. Waiting for partner to accept.`,
    updatedBy: updatedBy || agent._id,
  });
  await shipment.save();

  await DeliveryAgent.findByIdAndUpdate(agent._id, { isAvailable: false });

  const populated = await Shipment.findById(shipment._id)
    .populate('customerId', 'name phone avatarUrl')
    .populate('deliveryAgentId', 'name phone avatarUrl vehicleType vehicleNumber rating');

  io?.to(`user:${agent._id}`).emit('agent:new_assignment', populated || shipment);
  io?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', populated || shipment);

  await sendPushNotification({
    recipient: agent,
    recipientModel: 'DeliveryAgent',
    title: 'New Delivery Request',
    body: `Package #${shipment.trackingId} is ready in ${shipment.pickupLocation?.city || 'your area'}. Tap to accept.`,
    type: 'pickup',
    shipmentId: shipment._id,
  });

  return populated || shipment;
}

module.exports = {
  NEARBY_COURIER_RADIUS_KM,
  ACTIVE_STATUSES,
  haversineKm,
  getBusyAgentIds,
  syncAgentAvailability,
  findNearbyAvailableAgents,
  findNextAvailableAgent,
  offerShipmentToAgent,
};
