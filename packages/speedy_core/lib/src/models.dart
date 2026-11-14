class VehicleOption {
  final String id;
  final String label;
  final int visitFeePaise;

  const VehicleOption({
    required this.id,
    required this.label,
    required this.visitFeePaise,
  });

  factory VehicleOption.fromJson(Map<String, dynamic> j) => VehicleOption(
        id: j['id'] as String,
        label: j['label'] as String,
        visitFeePaise: (j['visitFeePaise'] as num).toInt(),
      );
}

class IssueOption {
  final String id;
  final String label;

  const IssueOption({
    required this.id,
    required this.label,
  });

  factory IssueOption.fromJson(Map<String, dynamic> j) => IssueOption(
        id: j['id'] as String,
        label: j['label'] as String,
      );
}

class Catalog {
  final String currency;
  final List<VehicleOption> vehicles;
  final List<IssueOption> issues;

  const Catalog({
    required this.currency,
    required this.vehicles,
    required this.issues,
  });

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        currency: (j['currency'] as String?) ?? 'INR',
        vehicles: ((j['vehicles'] as List?) ?? const [])
            .map((e) => VehicleOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        issues: ((j['issues'] as List?) ?? const [])
            .map((e) => IssueOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const Catalog fallback = Catalog(
    currency: 'INR',
    vehicles: [
      VehicleOption(id: 'bike', label: 'Bike', visitFeePaise: 14900),
      VehicleOption(id: 'scooter', label: 'Scooter', visitFeePaise: 14900),
      VehicleOption(id: 'auto', label: 'Auto', visitFeePaise: 19900),
      VehicleOption(id: 'car', label: 'Car', visitFeePaise: 24900),
      VehicleOption(id: 'truck', label: 'Truck / LCV', visitFeePaise: 39900),
    ],
    issues: [
      IssueOption(id: 'puncture', label: 'Puncture'),
      IssueOption(id: 'battery', label: 'Battery / Jumpstart'),
      IssueOption(id: 'wont_start', label: "Won't start"),
      IssueOption(id: 'brake_clutch_chain', label: 'Brake / Clutch / Chain'),
      IssueOption(id: 'other', label: 'Other problem'),
    ],
  );
}

class BookingCharge {
  final String id;
  final String description;
  final int amountPaise;
  final String status; // pending | approved | rejected

  const BookingCharge({
    required this.id,
    required this.description,
    required this.amountPaise,
    required this.status,
  });

  factory BookingCharge.fromJson(Map<String, dynamic> j) => BookingCharge(
        id: j['id'] as String,
        description: j['description'] as String,
        amountPaise: (j['amountPaise'] as num).toInt(),
        status: j['status'] as String,
      );
}

class CustomerSummary {
  final String id;
  final String? name;
  final String phone;

  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
        id: j['id'] as String,
        name: j['name'] as String?,
        phone: j['phone'] as String,
      );
}

class PartnerSummary {
  final String id;
  final String? name;
  final String shopName;
  final String phone;
  final String? upiId;
  final double? lat;
  final double? lng;
  final double? rating;
  final int ratingCount;

  const PartnerSummary({
    required this.id,
    required this.name,
    required this.shopName,
    required this.phone,
    required this.upiId,
    required this.lat,
    required this.lng,
    required this.rating,
    required this.ratingCount,
  });

  factory PartnerSummary.fromJson(Map<String, dynamic> j) => PartnerSummary(
        id: j['id'] as String,
        name: j['name'] as String?,
        shopName: j['shopName'] as String,
        phone: j['phone'] as String,
        upiId: j['upiId'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        rating: (j['rating'] as num?)?.toDouble(),
        ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
      );
}

class BookingRating {
  final int stars;
  final String? comment;

  const BookingRating({required this.stars, this.comment});

  factory BookingRating.fromJson(Map<String, dynamic> j) => BookingRating(
        stars: (j['stars'] as num).toInt(),
        comment: j['comment'] as String?,
      );
}

class Booking {
  final String id;
  final String code;
  final String status; // searching | accepted | arrived | in_progress | completed | cancelled | expired
  final String vehicleType;
  final String issue;
  final String? note;
  final String? vehicleNumber;
  final double lat;
  final double lng;
  final String? address;
  final int visitFeePaise;
  final int extraPaise;
  final int totalPaise;
  final String? paymentMethod;
  final String? startOtp;
  final CustomerSummary? customer;
  final PartnerSummary? partner;
  final List<BookingCharge> charges;
  final BookingRating? rating;
  final String createdAt;

  const Booking({
    required this.id,
    required this.code,
    required this.status,
    required this.vehicleType,
    required this.issue,
    this.note,
    this.vehicleNumber,
    required this.lat,
    required this.lng,
    this.address,
    required this.visitFeePaise,
    required this.extraPaise,
    required this.totalPaise,
    this.paymentMethod,
    this.startOtp,
    this.customer,
    this.partner,
    required this.charges,
    this.rating,
    required this.createdAt,
  });

  bool get isLive =>
      status == 'searching' ||
      status == 'accepted' ||
      status == 'arrived' ||
      status == 'in_progress';

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as String,
        code: j['code'] as String,
        status: j['status'] as String,
        vehicleType: j['vehicleType'] as String,
        issue: j['issue'] as String,
        note: j['note'] as String?,
        vehicleNumber: j['vehicleNumber'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        address: j['address'] as String?,
        visitFeePaise: (j['visitFeePaise'] as num).toInt(),
        extraPaise: (j['extraPaise'] as num).toInt(),
        totalPaise: (j['totalPaise'] as num).toInt(),
        paymentMethod: j['paymentMethod'] as String?,
        startOtp: j['startOtp'] as String?,
        customer: j['customer'] != null
            ? CustomerSummary.fromJson(j['customer'] as Map<String, dynamic>)
            : null,
        partner: j['partner'] != null
            ? PartnerSummary.fromJson(j['partner'] as Map<String, dynamic>)
            : null,
        charges: ((j['charges'] as List?) ?? const [])
            .map((e) => BookingCharge.fromJson(e as Map<String, dynamic>))
            .toList(),
        rating: j['rating'] != null
            ? BookingRating.fromJson(j['rating'] as Map<String, dynamic>)
            : null,
        createdAt: j['createdAt'] as String,
      );
}

class JobOffer {
  final String bookingId;
  final String code;
  final String vehicleType;
  final String issue;
  final String? note;
  final double lat;
  final double lng;
  final String? address;
  final int visitFeePaise;
  final int distanceMeters;
  final DateTime expiresAt;

  const JobOffer({
    required this.bookingId,
    required this.code,
    required this.vehicleType,
    required this.issue,
    this.note,
    required this.lat,
    required this.lng,
    this.address,
    required this.visitFeePaise,
    required this.distanceMeters,
    required this.expiresAt,
  });

  factory JobOffer.fromJson(Map<String, dynamic> j) => JobOffer(
        bookingId: j['bookingId'] as String,
        code: j['code'] as String,
        vehicleType: j['vehicleType'] as String,
        issue: j['issue'] as String,
        note: j['note'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        address: j['address'] as String?,
        visitFeePaise: (j['visitFeePaise'] as num).toInt(),
        distanceMeters: (j['distanceMeters'] as num).toInt(),
        expiresAt: DateTime.parse(j['expiresAt'] as String),
      );
}

class PartnerProfile {
  final String userId;
  final String? name;
  final String phone;
  final String shopName;
  final List<String> vehicleTypes;
  final String? upiId;
  final String status; // pending | approved | rejected | suspended
  final bool isOnline;
  final double? lat;
  final double? lng;
  final double? rating;
  final int ratingCount;
  final List<String> documentsUploaded;

  const PartnerProfile({
    required this.userId,
    this.name,
    required this.phone,
    required this.shopName,
    required this.vehicleTypes,
    this.upiId,
    required this.status,
    required this.isOnline,
    this.lat,
    this.lng,
    this.rating,
    required this.ratingCount,
    required this.documentsUploaded,
  });

  factory PartnerProfile.fromJson(Map<String, dynamic> j) => PartnerProfile(
        userId: j['userId'] as String,
        name: j['name'] as String?,
        phone: j['phone'] as String,
        shopName: j['shopName'] as String,
        vehicleTypes: ((j['vehicleTypes'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        upiId: j['upiId'] as String?,
        status: j['status'] as String,
        isOnline: j['isOnline'] as bool? ?? false,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        rating: (j['rating'] as num?)?.toDouble(),
        ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
        documentsUploaded: ((j['documentsUploaded'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class EarningsJobItem {
  final String id;
  final String code;
  final String vehicleType;
  final String issue;
  final int totalPaise;
  final int commissionPaise;
  final int netPaise;
  final String paymentMethod;
  final String completedAt;

  const EarningsJobItem({
    required this.id,
    required this.code,
    required this.vehicleType,
    required this.issue,
    required this.totalPaise,
    required this.commissionPaise,
    required this.netPaise,
    required this.paymentMethod,
    required this.completedAt,
  });

  factory EarningsJobItem.fromJson(Map<String, dynamic> j) => EarningsJobItem(
        id: j['id'] as String,
        code: j['code'] as String,
        vehicleType: j['vehicleType'] as String,
        issue: j['issue'] as String,
        totalPaise: (j['totalPaise'] as num).toInt(),
        commissionPaise: (j['commissionPaise'] as num).toInt(),
        netPaise: (j['netPaise'] as num).toInt(),
        paymentMethod: (j['paymentMethod'] as String?) ?? 'cash',
        completedAt: j['completedAt'] as String,
      );
}

class EarningsSummary {
  final int completedJobs;
  final int grossPaise;
  final int commissionPaise;
  final int netEarningsPaise;
  final int commissionBalanceDuePaise;
  final List<EarningsJobItem> recentJobs;

  const EarningsSummary({
    required this.completedJobs,
    required this.grossPaise,
    required this.commissionPaise,
    required this.netEarningsPaise,
    required this.commissionBalanceDuePaise,
    required this.recentJobs,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> j) => EarningsSummary(
        completedJobs: (j['completedJobs'] as num).toInt(),
        grossPaise: (j['grossPaise'] as num).toInt(),
        commissionPaise: (j['commissionPaise'] as num).toInt(),
        netEarningsPaise: (j['netEarningsPaise'] as num).toInt(),
        commissionBalanceDuePaise: (j['commissionBalanceDuePaise'] as num).toInt(),
        recentJobs: ((j['recentJobs'] as List?) ?? const [])
            .map((e) => EarningsJobItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
