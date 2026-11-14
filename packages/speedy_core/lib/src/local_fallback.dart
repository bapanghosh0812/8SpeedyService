import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'models.dart';

/// Shared persistent fallback engine used when the static web bundle is previewed
/// on Netlify before a remote Cloud Run API URL is configured.
/// Because `/customer/` and `/partner/` share the same Netlify origin, calling
/// `prefs.reload()` synchronizes bookings, offers, 4-digit Start OTP, extra charges,
/// and 15% commission ledger entries across both browser tabs in real time.
class LocalEdgeFallback {
  static const String _stateKey = 'speedy_v3_shared_edge_state';
  static final Random _rng = Random.secure();

  static Future<Map<String, dynamic>> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) {
      return {
        'users': <String, dynamic>{},
        'partners': <String, dynamic>{},
        'bookings': <Map<String, dynamic>>[],
      };
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'users': Map<String, dynamic>.from((decoded['users'] as Map?) ?? {}),
        'partners': Map<String, dynamic>.from((decoded['partners'] as Map?) ?? {}),
        'bookings': ((decoded['bookings'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      };
    } catch (_) {
      return {
        'users': <String, dynamic>{},
        'partners': <String, dynamic>{},
        'bookings': <Map<String, dynamic>>[],
      };
    }
  }

  static Future<void> _saveState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state));
  }

  static Map<String, dynamic> _userFromToken(String? token, Map<String, dynamic> state) {
    String phone = '+919876543210';
    String uid = 'user_default';
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
        : {'id': custId, 'name': 'Customer', 'phone': '+919876543210'};

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
        'phone': pu['phone'] ?? p['phone'] ?? '+919765432109',
        'upiId': p['upiId'],
        'lat': p['lat'] ?? 18.5212,
        'lng': p['lng'] ?? 73.8574,
        'rating': p['rating'] ?? 4.9,
        'ratingCount': p['ratingCount'] ?? 1,
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
      // Only expose startOtp to the booking customer
      'startOtp': viewerId == custId ? b['startOtp'] : null,
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
      'isAdmin': false,
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
      'status': 'pending',
      'isOnline': false,
      'lat': 18.5212,
      'lng': 73.8574,
      'rating': 4.9,
      'ratingCount': 1,
      'documentsUploaded': <String>[],
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
