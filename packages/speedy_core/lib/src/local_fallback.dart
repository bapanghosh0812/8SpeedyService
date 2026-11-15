import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'models.dart';

class LocalEdgeFallback {
  static const String _stateKey = 'speedy_v3_shared_edge_state';
  static final Random _rng = Random.secure();

  static Map<String, dynamic> _defaultSeededState() {
    final nowIso = DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
    return {
      'users': <String, dynamic>{
        'uid_919883290273': {
          'id': 'uid_919883290273',
          'phone': '+919883290273',
          'name': 'Bapan Ghosh',
          'isAdmin': true,
        },
        'uid_919635297320': {
          'id': 'uid_919635297320',
          'phone': '+919635297320',
          'name': '8Speedy Partner',
          'isAdmin': true,
        },
        'uid_cust_dispatch': {
          'id': 'uid_cust_dispatch',
          'phone': '+919820144510',
          'name': 'Vikram Singh',
          'isAdmin': false,
        },
      },
      'partners': <String, dynamic>{
        'uid_919883290273': {
          'userId': 'uid_919883290273',
          'name': 'Bapan Ghosh',
          'phone': '+919883290273',
          'shopName': '8SpeedyService Master Garage',
          'vehicleTypes': ['bike', 'scooter', 'auto', 'car', 'truck'],
          'upiId': '8speedyservice@okaxis',
          'status': 'approved',
          'isOnline': true,
          'lat': 18.5212,
          'lng': 73.8574,
          'rating': 4.9,
          'ratingCount': 24,
          'documentsUploaded': ['id_proof', 'selfie', 'shop_photo'],
        },
        'uid_919635297320': {
          'userId': 'uid_919635297320',
          'name': '8Speedy Partner',
          'phone': '+919635297320',
          'shopName': '8Speedy Express Auto Works',
          'vehicleTypes': ['bike', 'scooter', 'auto', 'car', 'truck'],
          'upiId': 'speedypartner@okaxis',
          'status': 'approved',
          'isOnline': true,
          'lat': 18.5212,
          'lng': 73.8574,
          'rating': 4.9,
          'ratingCount': 18,
          'documentsUploaded': ['id_proof', 'selfie', 'shop_photo'],
        },
      },
      'bookings': <Map<String, dynamic>>[
        {
          'id': '00000000-0000-4000-8000-000000000101',
          'code': 'SPD-4829',
          'customerId': 'uid_cust_dispatch',
          'partnerId': null,
          'status': 'searching',
          'vehicleType': 'car',
          'issue': 'battery',
          'note': 'Car battery dead near main highway exit, jumpstart needed',
          'vehicleNumber': 'WB 02 AN 4829',
          'lat': 18.5204,
          'lng': 73.8567,
          'address': 'Sector V Main Flyover Service Lane',
          'visitFeePaise': 24900,
          'startOtp': '1234',
          'otpAttempts': 0,
          'charges': <Map<String, dynamic>>[],
          'paymentMethod': null,
          'rating': null,
          'createdAt': DateTime.now().toIso8601String(),
          'completedAt': null,
        },
        {
          'id': '00000000-0000-4000-8000-000000000102',
          'code': 'SPD-3190',
          'customerId': 'uid_919883290273',
          'partnerId': 'uid_919635297320',
          'status': 'completed',
          'vehicleType': 'car',
          'issue': 'puncture',
          'note': 'Rear right tubeless tyre puncture repaired on spot',
          'vehicleNumber': 'WB 06 K 8812',
          'lat': 18.5204,
          'lng': 73.8567,
          'address': 'Park Street Crossing',
          'visitFeePaise': 24900,
          'startOtp': '5512',
          'otpAttempts': 0,
          'charges': <Map<String, dynamic>>[
            {
              'id': 'chg_seed_1',
              'description': 'Heavy-duty mushroom plug & valve seal',
              'amountPaise': 15000,
              'status': 'approved',
            },
          ],
          'paymentMethod': 'upi_direct',
          'rating': {'stars': 5, 'comment': 'Super fast arrival in 12 mins!'},
          'createdAt': nowIso,
          'completedAt': nowIso,
        },
        {
          'id': '00000000-0000-4000-8000-000000000103',
          'code': 'SPD-2744',
          'customerId': 'uid_919635297320',
          'partnerId': 'uid_919883290273',
          'status': 'completed',
          'vehicleType': 'bike',
          'issue': 'engine',
          'note': 'Spark plug & fuel line cleaned on highway',
          'vehicleNumber': 'WB 04 M 2744',
          'lat': 18.5204,
          'lng': 73.8567,
          'address': 'EM Bypass Connector',
          'visitFeePaise': 14900,
          'startOtp': '7741',
          'otpAttempts': 0,
          'charges': <Map<String, dynamic>>[
            {
              'id': 'chg_seed_2',
              'description': 'NGK Iridium Spark Plug replacement',
              'amountPaise': 22000,
              'status': 'approved',
            },
          ],
          'paymentMethod': 'upi_direct',
          'rating': {'stars': 5, 'comment': 'Fixed immediately on the spot.'},
          'createdAt': nowIso,
          'completedAt': nowIso,
        },
      ],
    };
  }

  static Future<Map<String, dynamic>> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}
    final raw = prefs.getString(_stateKey);
    final seed = _defaultSeededState();
    if (raw == null || raw.isEmpty) {
      return seed;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final users = Map<String, dynamic>.from(seed['users'] as Map)
        ..addAll(Map<String, dynamic>.from((decoded['users'] as Map?) ?? {}));
      final partners = Map<String, dynamic>.from(seed['partners'] as Map)
        ..addAll(Map<String, dynamic>.from((decoded['partners'] as Map?) ?? {}));
      return {
        'users': users,
        'partners': partners,
        'bookings': ((decoded['bookings'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      };
    } catch (_) {
      return seed;
    }
  }

  static Future<void> _saveState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state));
  }

  static Map<String, dynamic> _userFromToken(String? token, Map<String, dynamic> state) {
    String phone = '+919883290273';
    String uid = 'uid_919883290273';
    if (token != null && token.contains('.')) {
      try {
        final parts = token.split('.');
        if (parts.length >= 2) {
          final normalized = base64Url.normalize(parts[1]);
          final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
          phone = (payload['phone_number'] as String?) ?? phone;
          uid = (payload['user_id'] as String?) ?? (payload['sub'] as String?) ?? uid;
        }
      } catch (_) {}
    }
    final users = state['users'] as Map<String, dynamic>;
    final existing = users[uid];
    if (existing is Map) {
      return Map<String, dynamic>.from(existing);
    }
    final created = <String, dynamic>{
      'id': uid,
      'phone': phone,
      'name': null,
      'isAdmin': false,
    };
    users[uid] = created;
    return created;
  }

  static int _visitFeeFor(String vehicleType) {
    for (final v in Catalog.fallback.vehicles) {
      if (v.id == vehicleType) return v.visitFeePaise;
    }
    return 14900;
  }

  static Map<String, dynamic> _formatBookingForViewer(
    Map<String, dynamic> b,
    String viewerId,
    Map<String, dynamic> state,
  ) {
    final users = state['users'] as Map<String, dynamic>;
    final partners = state['partners'] as Map<String, dynamic>;
    final custId = b['customerId'] as String;
    final partId = b['partnerId'] as String?;

    final cust = users[custId] != null
        ? Map<String, dynamic>.from(users[custId] as Map)
        : {'id': custId, 'name': 'Customer', 'phone': '+919883290273'};

    Map<String, dynamic>? partnerSummary;
    if (partId != null && partners[partId] != null) {
      final p = Map<String, dynamic>.from(partners[partId] as Map);
      final pu = users[partId] != null
          ? Map<String, dynamic>.from(users[partId] as Map)
          : <String, dynamic>{};
      partnerSummary = {
        'id': partId,
        'name': pu['name'] ?? p['name'],
        'shopName': p['shopName'],
        'phone': pu['phone'] ?? p['phone'] ?? '+919635297320',
        'upiId': p['upiId'],
        'lat': p['lat'] ?? 18.5212,
        'lng': p['lng'] ?? 73.8574,
        'rating': p['rating'] ?? 4.9,
        'ratingCount': p['ratingCount'] ?? 18,
      };
    }

    final charges = ((b['charges'] as List?) ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    int approvedExtra = 0;
    for (final c in charges) {
      if (c['status'] == 'approved') {
        approvedExtra += (c['amountPaise'] as num).toInt();
      }
    }
    final visitFee = (b['visitFeePaise'] as num).toInt();

    return {
      'id': b['id'],
      'code': b['code'],
      'status': b['status'],
      'vehicleType': b['vehicleType'],
      'issue': b['issue'],
      'note': b['note'],
      'vehicleNumber': b['vehicleNumber'],
      'lat': b['lat'],
      'lng': b['lng'],
      'address': b['address'],
      'visitFeePaise': visitFee,
      'extraPaise': approvedExtra,
      'totalPaise': visitFee + approvedExtra,
      'paymentMethod': b['paymentMethod'],
      'startOtp': b['startOtp'],
      'customer': {
        'id': cust['id'],
        'name': cust['name'],
        'phone': cust['phone'],
      },
      'partner': partnerSummary,
      'charges': charges,
      'rating': b['rating'],
      'createdAt': b['createdAt'],
    };
  }

  static Future<Map<String, dynamic>> getMe(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    await _saveState(state);
    final partners = state['partners'] as Map<String, dynamic>;
    return {
      'id': user['id'],
      'phone': user['phone'],
      'name': user['name'],
      'isAdmin': user['isAdmin'] ?? false,
      'partner': partners[user['id']],
    };
  }

  static Future<Map<String, dynamic>> updateMe(String? token, String name) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    user['name'] = name.trim();
    (state['users'] as Map<String, dynamic>)[user['id'] as String] = user;
    await _saveState(state);
    return {
      'id': user['id'],
      'phone': user['phone'],
      'name': user['name'],
    };
  }

  static Future<Booking> createBooking(
    String? token, {
    required String vehicleType,
    required String issue,
    required double lat,
    required double lng,
    String? address,
    String? note,
    String? vehicleNumber,
  }) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;

    for (final existing in bookings) {
      final st = existing['status'] as String;
      if (existing['customerId'] == user['id'] &&
          (st == 'searching' || st == 'accepted' || st == 'arrived' || st == 'in_progress')) {
        return Booking.fromJson(_formatBookingForViewer(existing, user['id'] as String, state));
      }
    }

    final id = '00000000-0000-4000-8000-${DateTime.now().millisecondsSinceEpoch.toString().padLeft(12, '0').substring(0, 12)}';
    final code = 'SPD-${(1000 + _rng.nextInt(9000))}';
    final otp = (1000 + _rng.nextInt(9000)).toString();
    final visitFee = _visitFeeFor(vehicleType);

    final record = <String, dynamic>{
      'id': id,
      'code': code,
      'customerId': user['id'],
      'partnerId': null,
      'status': 'searching',
      'vehicleType': vehicleType,
      'issue': issue,
      'note': note,
      'vehicleNumber': vehicleNumber,
      'lat': lat,
      'lng': lng,
      'address': address,
      'visitFeePaise': visitFee,
      'startOtp': otp,
      'otpAttempts': 0,
      'charges': <Map<String, dynamic>>[],
      'paymentMethod': null,
      'rating': null,
      'createdAt': DateTime.now().toIso8601String(),
      'completedAt': null,
    };

    bookings.insert(0, record);
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(record, user['id'] as String, state));
  }

  static Future<Booking?> getActiveBooking(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    for (final b in bookings) {
      final st = b['status'] as String;
      if (b['customerId'] == user['id'] &&
          (st == 'searching' || st == 'accepted' || st == 'arrived' || st == 'in_progress')) {
        return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
      }
    }
    return null;
  }

  static Future<List<Booking>> listBookings(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    return bookings
        .where((b) => b['customerId'] == user['id'])
        .map((b) => Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state)))
        .toList();
  }

  static Future<Booking> getBooking(String? token, String id) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere(
      (x) => x['id'] == id,
      orElse: () => throw const ApiException(status: 404, code: 'NOT_FOUND', message: 'Booking not found'),
    );
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> cancelBooking(String? token, String id) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == id);
    b['status'] = 'cancelled';
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> decideCharge(
    String? token,
    String bookingId,
    String chargeId,
    String decision,
  ) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    final charges = ((b['charges'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    for (final c in charges) {
      if (c['id'] == chargeId) {
        c['status'] = decision;
      }
    }
    b['charges'] = charges;
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> rateBooking(
    String? token,
    String bookingId,
    int stars,
    String? comment,
  ) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    b['rating'] = {'stars': stars, 'comment': comment};
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<({PartnerProfile? partner, Booking? activeBooking})> getPartnerMe(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final partners = state['partners'] as Map<String, dynamic>;
    final rawP = partners[user['id']];
    if (rawP == null) {
      return (partner: null, activeBooking: null);
    }
    final p = PartnerProfile.fromJson(Map<String, dynamic>.from(rawP as Map));
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    Booking? active;
    for (final b in bookings) {
      final st = b['status'] as String;
      if (b['partnerId'] == user['id'] &&
          (st == 'accepted' || st == 'arrived' || st == 'in_progress')) {
        active = Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
        break;
      }
    }
    return (partner: p, activeBooking: active);
  }

  static Future<void> applyPartner(
    String? token, {
    required String name,
    required String shopName,
    required List<String> vehicleTypes,
    String? upiId,
  }) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    user['name'] = name.trim();
    (state['users'] as Map<String, dynamic>)[user['id'] as String] = user;
    final partners = state['partners'] as Map<String, dynamic>;
    partners[user['id'] as String] = {
      'userId': user['id'],
      'name': name.trim(),
      'phone': user['phone'],
      'shopName': shopName.trim(),
      'vehicleTypes': vehicleTypes,
      'upiId': upiId,
      'status': 'approved',
      'isOnline': true,
      'lat': 18.5212,
      'lng': 73.8574,
      'rating': 4.9,
      'ratingCount': 1,
      'documentsUploaded': <String>['id_proof', 'selfie', 'shop_photo'],
    };
    await _saveState(state);
  }

  static Future<void> uploadDocument(String? token, String kind) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final partners = state['partners'] as Map<String, dynamic>;
    final p = Map<String, dynamic>.from(partners[user['id']] as Map);
    final docs = ((p['documentsUploaded'] as List?) ?? []).map((e) => e.toString()).toSet();
    docs.add(kind);
    p['documentsUploaded'] = docs.toList();
    partners[user['id'] as String] = p;
    await _saveState(state);
  }

  static Future<void> approvePartner(String targetUserId) async {
    final state = await _loadState();
    final partners = state['partners'] as Map<String, dynamic>;
    if (partners[targetUserId] != null) {
      final p = Map<String, dynamic>.from(partners[targetUserId] as Map);
      p['status'] = 'approved';
      partners[targetUserId] = p;
      await _saveState(state);
    }
  }

  static Future<void> setAvailability(
    String? token, {
    required bool isOnline,
    double? lat,
    double? lng,
  }) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final partners = state['partners'] as Map<String, dynamic>;
    final p = Map<String, dynamic>.from(partners[user['id']] as Map);
    p['isOnline'] = isOnline;
    if (lat != null) p['lat'] = lat;
    if (lng != null) p['lng'] = lng;
    partners[user['id'] as String] = p;
    await _saveState(state);
  }

  static Future<List<JobOffer>> listOffers(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final partners = state['partners'] as Map<String, dynamic>;
    final rawP = partners[user['id']];
    if (rawP == null) return const [];
    final p = Map<String, dynamic>.from(rawP as Map);
    if (p['status'] != 'approved' || p['isOnline'] != true) {
      return const [];
    }
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final offers = <JobOffer>[];
    for (final b in bookings) {
      if (b['status'] == 'searching') {
        offers.add(
          JobOffer(
            bookingId: b['id'] as String,
            code: b['code'] as String,
            vehicleType: b['vehicleType'] as String,
            issue: b['issue'] as String,
            note: b['note'] as String?,
            lat: (b['lat'] as num).toDouble(),
            lng: (b['lng'] as num).toDouble(),
            address: b['address'] as String?,
            visitFeePaise: (b['visitFeePaise'] as num).toInt(),
            distanceMeters: 420,
            expiresAt: DateTime.now().add(const Duration(seconds: 20)),
          ),
        );
      }
    }
    return offers;
  }

  static Future<Booking> acceptOffer(String? token, String bookingId) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    if (b['status'] != 'searching') {
      throw const ApiException(
        status: 409,
        code: 'ALREADY_TAKEN',
        message: 'This job was already accepted by another mechanic',
      );
    }
    b['status'] = 'accepted';
    b['partnerId'] = user['id'];
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> markArrived(String? token, String bookingId) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    b['status'] = 'arrived';
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> startWork(String? token, String bookingId, String otp) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    final attempts = (b['otpAttempts'] as num?)?.toInt() ?? 0;
    if (attempts >= 5) {
      throw const ApiException(
        status: 429,
        code: 'OTP_LOCKED',
        message: 'Maximum OTP attempts exceeded',
      );
    }
    if (b['startOtp'] != otp.trim()) {
      b['otpAttempts'] = attempts + 1;
      await _saveState(state);
      throw const ApiException(
        status: 400,
        code: 'INVALID_OTP',
        message: 'Incorrect 4-digit Start Code. Ask the customer to check their screen.',
      );
    }
    b['status'] = 'in_progress';
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> addCharge(
    String? token,
    String bookingId, {
    required String description,
    required int amountPaise,
  }) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    final charges = ((b['charges'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    charges.add({
      'id': 'chg_${DateTime.now().millisecondsSinceEpoch}',
      'description': description,
      'amountPaise': amountPaise,
      'status': 'pending',
    });
    b['charges'] = charges;
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<Booking> completeBooking(
    String? token,
    String bookingId, {
    required String paymentMethod,
  }) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    final charges = ((b['charges'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (charges.any((c) => c['status'] == 'pending')) {
      throw const ApiException(
        status: 409,
        code: 'PENDING_CHARGES',
        message: 'Customer must approve or reject pending charges before completion',
      );
    }
    b['status'] = 'completed';
    b['paymentMethod'] = paymentMethod;
    b['completedAt'] = DateTime.now().toIso8601String();
    await _saveState(state);
    return Booking.fromJson(_formatBookingForViewer(b, user['id'] as String, state));
  }

  static Future<EarningsSummary> getEarnings(String? token) async {
    final state = await _loadState();
    final user = _userFromToken(token, state);
    final bookings = state['bookings'] as List<Map<String, dynamic>>;
    final completed = bookings
        .where((b) => b['partnerId'] == user['id'] && b['status'] == 'completed')
        .toList();

    int gross = 0;
    int comm = 0;
    final items = <EarningsJobItem>[];

    for (final b in completed) {
      final formatted = _formatBookingForViewer(b, user['id'] as String, state);
      final total = (formatted['totalPaise'] as num).toInt();
      final cPaise = ((total * 15) / 100).round();
      gross += total;
      comm += cPaise;
      items.add(
        EarningsJobItem(
          id: b['id'] as String,
          code: b['code'] as String,
          vehicleType: b['vehicleType'] as String,
          issue: b['issue'] as String,
          totalPaise: total,
          commissionPaise: cPaise,
          netPaise: total - cPaise,
          paymentMethod: (b['paymentMethod'] as String?) ?? 'cash',
          completedAt: (b['completedAt'] as String?) ?? DateTime.now().toIso8601String(),
        ),
      );
    }

    return EarningsSummary(
      completedJobs: completed.length,
      grossPaise: gross,
      commissionPaise: comm,
      netEarningsPaise: gross - comm,
      commissionBalanceDuePaise: comm,
      recentJobs: items,
    );
  }
}
