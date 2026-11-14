/**
 * Service catalog and pricing. Prices are decided ONLY on the server;
 * the apps display what /v1/catalog returns and never send a price.
 */

export const VEHICLE_TYPES = ['bike', 'scooter', 'auto', 'car', 'truck'] as const;
export type VehicleType = (typeof VEHICLE_TYPES)[number];

export const ISSUES = ['puncture', 'battery', 'wont_start', 'brake_clutch_chain', 'other'] as const;
export type Issue = (typeof ISSUES)[number];

const VISIT_FEE_RUPEES: Record<VehicleType, number> = {
  bike: 149,
  scooter: 149,
  auto: 199,
  car: 249,
  truck: 399,
};

export const VEHICLE_LABELS: Record<VehicleType, string> = {
  bike: 'Bike',
  scooter: 'Scooter',
  auto: 'Auto',
  car: 'Car',
  truck: 'Truck / LCV',
};

export const ISSUE_LABELS: Record<Issue, string> = {
  puncture: 'Puncture',
  battery: 'Battery / Jumpstart',
  wont_start: "Won't start",
  brake_clutch_chain: 'Brake / Clutch / Chain',
  other: 'Other problem',
};

export function visitFeePaise(vehicle: VehicleType): number {
  return VISIT_FEE_RUPEES[vehicle] * 100;
}

/** Maximum a partner may add as a single extra charge (₹20,000). */
export const MAX_CHARGE_PAISE = 2_000_000;
/** Maximum total extra charges on one booking (₹50,000). */
export const MAX_TOTAL_EXTRA_PAISE = 5_000_000;

export function catalog() {
  return {
    currency: 'INR',
    vehicles: VEHICLE_TYPES.map((id) => ({
      id,
      label: VEHICLE_LABELS[id],
      visitFeePaise: visitFeePaise(id),
    })),
    issues: ISSUES.map((id) => ({ id, label: ISSUE_LABELS[id] })),
  };
}
