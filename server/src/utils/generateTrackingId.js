const crypto = require('crypto');

const generateTrackingId = () => {
  const randomDigits = crypto.randomInt(10000000, 99999999);
  return `SR${randomDigits}`;
};

const generateDeliveryOtp = () => {
  return String(crypto.randomInt(1000, 9999));
};

module.exports = { generateTrackingId, generateDeliveryOtp };
