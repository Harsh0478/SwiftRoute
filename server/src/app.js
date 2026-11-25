const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const mongoSanitize = require('express-mongo-sanitize');

const authController = require('./controllers/authController');
const shipmentController = require('./controllers/shipmentController');
const agentController = require('./controllers/agentController');
const paymentController = require('./controllers/paymentController');
const adminController = require('./controllers/adminController');
const Message = require('./models/Message');
const Address = require('./models/Address');
const TrackingLocation = require('./models/Tracking');
const Shipment = require('./models/Shipment');
const User = require('./models/User');
const DeliveryAgent = require('./models/DeliveryAgent');
const { protect, authorizeRoles } = require('./middleware/authMiddleware');
const upload = require('./middleware/uploadMiddleware');

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.CLIENT_ORIGINS?.split(',') || '*', credentials: true }));
app.use(express.json({ limit: '2mb' }));
app.use(mongoSanitize());
app.use(morgan('dev'));

const apiLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 300 });
app.use('/api', apiLimiter);

app.post('/api/auth/register', authController.register);
app.post('/api/auth/login', authController.login);
app.post('/api/auth/refresh-token', authController.refreshToken);
app.post('/api/auth/verify-otp', authController.verifyOtp);
app.post('/api/auth/logout', protect, authController.logout);

app.get('/api/users/profile', protect, (req, res) => res.json({ success: true, user: req.user.doc }));
app.put('/api/users/profile', protect, async (req, res, next) => {
  try {
    const updated = await User.findByIdAndUpdate(req.user.id, req.body, { new: true });
    res.json({ success: true, user: updated });
  } catch (err) { next(err); }
});
app.get('/api/users/addresses', protect, async (req, res) => {
  const addresses = await Address.find({ userId: req.user.id }).sort({ isDefault: -1 });
  res.json({ success: true, addresses });
});
app.post('/api/users/addresses', protect, async (req, res) => {
  const address = await Address.create({ ...req.body, userId: req.user.id });
  res.status(201).json({ success: true, address });
});
app.delete('/api/users/addresses/:id', protect, async (req, res) => {
  await Address.findOneAndDelete({ _id: req.params.id, userId: req.user.id });
  res.json({ success: true, message: 'Address deleted' });
});

app.post('/api/shipments', protect, upload.single('packageImage'), shipmentController.createShipment);
app.get('/api/shipments', protect, shipmentController.getCustomerShipments);
app.get('/api/shipments/track/:trackingId', shipmentController.trackByTrackingId);
app.put('/api/shipments/:id/cancel', protect, shipmentController.cancelShipment);

app.post('/api/agents/register', agentController.registerAgent);
app.post('/api/agents/login', agentController.loginAgent);
app.get('/api/agents/profile', protect, authorizeRoles('agent'), (req, res) => res.json({ success: true, agent: req.user.doc }));
app.put('/api/agents/availability', protect, authorizeRoles('agent'), agentController.toggleAvailability);
app.get('/api/agents/assignments', protect, authorizeRoles('agent'), agentController.getAssignments);
app.put('/api/agents/shipments/:id/status', protect, authorizeRoles('agent'), agentController.updateShipmentStatus);
app.post('/api/agents/shipments/:id/proof', protect, authorizeRoles('agent'), upload.single('proofImage'), agentController.uploadProof);

app.get('/api/tracking/:shipmentId', protect, async (req, res) => {
  const trail = await TrackingLocation.find({ shipmentId: req.params.shipmentId }).sort({ recordedAt: -1 }).limit(50);
  res.json({ success: true, trail });
});

app.post('/api/payments/create-order', protect, paymentController.createPaymentOrder);
app.post('/api/payments/verify', protect, paymentController.verifyPayment);

app.get('/api/chat/:shipmentId/messages', protect, async (req, res) => {
  const messages = await Message.find({ shipmentId: req.params.shipmentId }).sort({ createdAt: 1 });
  res.json({ success: true, messages });
});

app.get('/api/admin/dashboard', protect, authorizeRoles('admin', 'superadmin'), adminController.getDashboardStats);
app.get('/api/admin/users', protect, authorizeRoles('admin', 'superadmin'), async (req, res) => {
  const users = await User.find({ role: 'customer' }).sort({ createdAt: -1 }).limit(100);
  res.json({ success: true, users });
});
app.get('/api/admin/agents', protect, authorizeRoles('admin', 'superadmin'), async (req, res) => {
  const agents = await DeliveryAgent.find().sort({ createdAt: -1 }).limit(100);
  res.json({ success: true, agents });
});
app.get('/api/admin/shipments', protect, authorizeRoles('admin', 'superadmin'), async (req, res) => {
  const shipments = await Shipment.find().populate('customerId', 'name phone').populate('deliveryAgentId', 'name vehicleNumber').sort({ createdAt: -1 }).limit(100);
  res.json({ success: true, shipments });
});
app.put('/api/admin/shipments/:id/assign-agent', protect, authorizeRoles('admin', 'superadmin'), adminController.assignAgent);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ success: false, message: err.message || 'Internal Server Error' });
});

module.exports = app;
