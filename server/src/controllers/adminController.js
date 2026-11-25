const User = require('../models/User');
const DeliveryAgent = require('../models/DeliveryAgent');
const Shipment = require('../models/Shipment');

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
    const shipment = await Shipment.findByIdAndUpdate(
      req.params.id,
      { deliveryAgentId: agentId, shipmentStatus: 'Order Confirmed' },
      { new: true }
    ).populate('deliveryAgentId', 'name phone avatarUrl vehicleNumber');

    req.app.get('io')?.to(`user:${agentId}`).emit('agent:new_assignment', shipment);
    req.app.get('io')?.to(`shipment:${shipment._id}`).emit('shipment:status_updated', shipment);
    res.json({ success: true, shipment });
  } catch (err) {
    next(err);
  }
};
