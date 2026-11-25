const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const User = require('../models/User');

const hashToken = (token) => crypto.createHash('sha256').update(token).digest('hex');

const signTokens = (id, role) => {
  const accessToken = jwt.sign({ id, role }, process.env.JWT_ACCESS_SECRET, {
    expiresIn: process.env.JWT_ACCESS_EXPIRES || '15m',
  });
  const refreshToken = jwt.sign({ id, role }, process.env.JWT_REFRESH_SECRET, {
    expiresIn: process.env.JWT_REFRESH_EXPIRES || '7d',
  });
  return { accessToken, refreshToken };
};

exports.register = async (req, res, next) => {
  try {
    const { name, email, phone, password } = req.body;
    const exists = await User.findOne({ $or: [{ email }, { phone }] });
    if (exists) return res.status(409).json({ success: false, message: 'Email or phone already registered' });

    const otp = String(crypto.randomInt(100000, 999999));
    const user = await User.create({
      name,
      email,
      phone,
      password,
      otpCode: otp,
      otpExpiresAt: new Date(Date.now() + 10 * 60 * 1000),
    });

    const { accessToken, refreshToken } = signTokens(user._id, user.role);
    user.refreshTokenHash = hashToken(refreshToken);
    await user.save();

    res.status(201).json({
      success: true,
      accessToken,
      refreshToken,
      user: { id: user._id, name: user.name, email: user.email, phone: user.phone, role: user.role },
    });
  } catch (err) {
    next(err);
  }
};

exports.login = async (req, res, next) => {
  try {
    const { email, password, fcmToken } = req.body;
    const user = await User.findOne({ email }).select('+password');
    if (!user || !(await user.comparePassword(password))) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const { accessToken, refreshToken } = signTokens(user._id, user.role);
    user.refreshTokenHash = hashToken(refreshToken);
    if (fcmToken && !user.fcmTokens.includes(fcmToken)) user.fcmTokens.push(fcmToken);
    await user.save();

    res.json({
      success: true,
      accessToken,
      refreshToken,
      user: { id: user._id, name: user.name, email: user.email, phone: user.phone, avatarUrl: user.avatarUrl, role: user.role },
    });
  } catch (err) {
    next(err);
  }
};

exports.refreshToken = async (req, res) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) return res.status(401).json({ success: false, message: 'Refresh token required' });

    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    const user = await User.findById(decoded.id).select('+refreshTokenHash');

    if (!user || user.refreshTokenHash !== hashToken(refreshToken)) {
      return res.status(403).json({ success: false, message: 'Refresh token revoked or invalid' });
    }

    const tokens = signTokens(user._id, user.role);
    user.refreshTokenHash = hashToken(tokens.refreshToken);
    await user.save();

    res.json({ success: true, ...tokens });
  } catch (err) {
    res.status(403).json({ success: false, message: 'Invalid refresh token' });
  }
};

exports.verifyOtp = async (req, res, next) => {
  try {
    const { email, otp } = req.body;
    const user = await User.findOne({ email }).select('+otpCode +otpExpiresAt');
    if (!user || user.otpCode !== otp || user.otpExpiresAt < new Date()) {
      return res.status(400).json({ success: false, message: 'Invalid or expired OTP' });
    }
    user.isVerified = true;
    user.otpCode = undefined;
    user.otpExpiresAt = undefined;
    await user.save();
    res.json({ success: true, message: 'Account verified successfully' });
  } catch (err) {
    next(err);
  }
};

exports.logout = async (req, res, next) => {
  try {
    await User.findByIdAndUpdate(req.user.id, { $unset: { refreshTokenHash: 1 } });
    res.json({ success: true, message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
};
