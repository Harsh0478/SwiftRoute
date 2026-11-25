const crypto = require('crypto');
const Razorpay = require('razorpay');
const Payment = require('../models/Payment');
const Shipment = require('../models/Shipment');

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID || 'rzp_test_placeholder',
  key_secret: process.env.RAZORPAY_KEY_SECRET || 'secret_placeholder',
});

exports.createPaymentOrder = async (req, res, next) => {
  try {
    const { shipmentId } = req.body;
    const shipment = await Shipment.findOne({ _id: shipmentId, customerId: req.user.id });
    if (!shipment) return res.status(404).json({ success: false, message: 'Shipment not found' });

    const order = await razorpay.orders.create({
      amount: Math.round(shipment.shippingCost * 100),
      currency: 'INR',
      receipt: shipment.trackingId,
    });

    const payment = await Payment.create({
      shipmentId: shipment._id,
      userId: req.user.id,
      razorpayOrderId: order.id,
      amount: shipment.shippingCost,
    });

    res.json({
      success: true,
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: process.env.RAZORPAY_KEY_ID,
      paymentId: payment._id,
    });
  } catch (err) {
    next(err);
  }
};

exports.verifyPayment = async (req, res, next) => {
  try {
    const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
    const expectedSignature = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (expectedSignature !== razorpay_signature) {
      return res.status(400).json({ success: false, message: 'Invalid Razorpay signature' });
    }

    const payment = await Payment.findOneAndUpdate(
      { razorpayOrderId: razorpay_order_id },
      { razorpayPaymentId: razorpay_payment_id, razorpaySignature: razorpay_signature, status: 'captured' },
      { new: true }
    );

    if (payment) {
      await Shipment.findByIdAndUpdate(payment.shipmentId, { paymentStatus: 'paid' });
    }

    res.json({ success: true, message: 'Payment verified successfully', payment });
  } catch (err) {
    next(err);
  }
};
