const jwt = require('jsonwebtoken');
const User = require('../models/User');
const DeliveryAgent = require('../models/DeliveryAgent');

const protect = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, message: 'Not authorized, missing token' });
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET);

    if (decoded.role === 'agent') {
      const agent = await DeliveryAgent.findById(decoded.id);
      if (!agent) return res.status(401).json({ success: false, message: 'Agent not found' });
      req.user = { id: agent._id, role: 'agent', doc: agent };
    } else {
      const user = await User.findById(decoded.id);
      if (!user) return res.status(401).json({ success: false, message: 'User not found' });
      req.user = { id: user._id, role: user.role, doc: user };
    }

    next();
  } catch (error) {
    return res.status(401).json({ success: false, message: 'Access token expired or invalid' });
  }
};

const authorizeRoles = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return res.status(403).json({ success: false, message: `Role '${req.user?.role}' is not authorized` });
  }
  next();
};

module.exports = { protect, authorizeRoles };
