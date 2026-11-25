const calculateDeliveryPrice = ({ distanceKm, weightKg, deliveryType, isFragile, promotion }) => {
  const baseRates = { standard: 40, express: 75, same_day: 120, scheduled: 55 };
  const perKmRate = deliveryType === 'same_day' ? 14 : deliveryType === 'express' ? 11 : 8;
  const weightSurcharge = weightKg > 2 ? (weightKg - 2) * 15 : 0;
  const fragileFee = isFragile ? 35 : 0;

  const baseCharge = Math.round((baseRates[deliveryType] || 40) + distanceKm * perKmRate + weightSurcharge + fragileFee);

  let discountAmount = 0;
  if (promotion && promotion.isActive && baseCharge >= promotion.minOrderAmount) {
    if (promotion.discountType === 'percentage') {
      discountAmount = Math.min(Math.round((baseCharge * promotion.discountValue) / 100), promotion.maxDiscountAmount);
    } else {
      discountAmount = Math.min(promotion.discountValue, baseCharge);
    }
  }

  const taxableAmount = Math.max(baseCharge - discountAmount, 0);
  const taxAmount = Math.round(taxableAmount * 0.18);
  const totalAmount = taxableAmount + taxAmount;

  return { baseCharge, discountAmount, taxAmount, totalAmount };
};

module.exports = calculateDeliveryPrice;
