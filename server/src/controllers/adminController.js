const User = require('../models/User');
const DeliveryAgent = require('../models/DeliveryAgent');
const Shipment = require('../models/Shipment');
const { ACTIVE_STATUSES, offerShipmentToAgent } = require('../services/dispatchService');

exports.getDashboardStats = async (req, res, next) => {
  try {
    const [totalCustomers, totalAgents, totalShipments, pendingShipments, completedShipments, cancelledShipments, revenueAgg] =
      await Promise.all([
        User.countDocuments({ role: 'customer' }),
        DeliveryAgent.countDocuments(),
        Shipment.countDocuments(),
        Shipment.countDocuments({ shipmentStatus: { $nin: ['Delivered', 'Cancelled'] } }),
        Shipment.countDocuments({ shipmentStatus: 'Delivered' }),
        Shipment.countDocuments({ shipmentStatus: 'Cancelled' }),
        Shipment.aggregate([
          { $match: { paymentStatus: 'paid' } },
          { $group: { _id: null, totalRevenue: { $sum: '$shippingCost' } } },
        ]),
      ]);

    res.json({
      success: true,
      stats: {
        totalCustomers,
        totalAgents,
        totalShipments,
        pendingShipments,
        completedShipments,
        cancelledShipments,
        totalRevenue: revenueAgg[0]?.totalRevenue || 0,
      },
    });
  } catch (err) {
    next(err);
  }
};

exports.assignAgent = async (req, res, next) => {
  try {
    const { agentId } = req.body;
    const activeCount = await Shipment.countDocuments({
      deliveryAgentId: agentId,
      shipmentStatus: { $in: ACTIVE_STATUSES },
    });
    if (activeCount > 0) {
      return res.status(400).json({
        success: false,
        message: 'Selected partner already has an active order in progress.',
      });
    }

    const [shipment, agent] = await Promise.all([
      Shipment.findById(req.params.id),
      DeliveryAgent.findById(agentId),
    ]);
    if (!shipment || !agent) {
      return res.status(404).json({ success: false, message: 'Shipment or partner not found' });
    }

    const offered = await offerShipmentToAgent(req.app.get('io'), shipment, agent, req.user.id);
    res.json({ success: true, shipment: offered });
  } catch (err) {
    next(err);
  }
};
