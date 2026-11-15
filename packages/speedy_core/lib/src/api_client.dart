import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'local_fallback.dart';
import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;

  const ApiException({
    required this.status,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class SpeedyApiClient {
  final String baseUrl;
  final String? Function() getToken;
  final http.Client _http;
  bool _remoteUnreachable = false;

  SpeedyApiClient({
    required this.baseUrl,
    required this.getToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client() {
    if (kIsWeb) {
      final host = Uri.base.host;
      final isLocalPage = host == '127.0.0.1' || host == 'localhost';
      final pointsToLocalhost =
          baseUrl.contains('127.0.0.1') || baseUrl.contains('localhost');
      if (!isLocalPage && pointsToLocalhost) {
        // Running on Netlify / static HTTPS preview without remote backend configured yet
        _remoteUnreachable = true;
      }
    }
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({Map<String, String>? extra, bool jsonBody = false}) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      h['Content-Type'] = 'application/json';
    }
    final token = getToken();
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    if (extra != null) {
      h.addAll(extra);
    }
    return h;
  }

  Map<String, dynamic> _decodeResponse(http.Response res) {
    Map<String, dynamic> body = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {}
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        status: res.statusCode,
        code: (body['error'] as String?) ?? 'HTTP_${res.statusCode}',
        message: (body['message'] as String?) ?? 'Request failed (${res.statusCode})',
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _http
        .get(_uri(path), headers: _headers())
        .timeout(const Duration(milliseconds: 1200));
    return _decodeResponse(res);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final res = await _http
        .post(
          _uri(path),
          headers: _headers(extra: extraHeaders, jsonBody: body != null),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(milliseconds: 1200));
    return _decodeResponse(res);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final res = await _http
        .patch(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(milliseconds: 1200));
    return _decodeResponse(res);
  }

  Future<T> _withEdgeFallback<T>(
    Future<T> Function() remoteCall,
    Future<T> Function() edgeFallback,
  ) async {
    if (_remoteUnreachable) {
      return await edgeFallback();
    }
    try {
      return await remoteCall();
    } on ApiException {
      rethrow;
    } catch (_) {
      _remoteUnreachable = true;
      return await edgeFallback();
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog & User Profile
  // ---------------------------------------------------------------------------

  Future<Catalog> getCatalog() => _withEdgeFallback(
        () async {
          final data = await _get('/v1/catalog');
          return Catalog.fromJson(data);
        },
        () async => Catalog.fallback,
      );

  Future<Map<String, dynamic>> getMe() => _withEdgeFallback(
        () => _get('/v1/me'),
        () => LocalEdgeFallback.getMe(getToken()),
      );

  Future<Map<String, dynamic>> updateMe(String name) => _withEdgeFallback(
        () => _patch('/v1/me', {'name': name.trim()}),
        () => LocalEdgeFallback.updateMe(getToken(), name),
      );

  Future<void> registerDeviceToken(String token, String app) => _withEdgeFallback(
        () async {
          await _post('/v1/me/device-token', body: {'token': token, 'app': app});
        },
        () async {},
      );

  // ---------------------------------------------------------------------------
  // Customer Booking Flow
  // ---------------------------------------------------------------------------

  Future<Booking> createBooking({
    required String vehicleType,
    required String issue,
    required double lat,
    required double lng,
    String? address,
    String? note,
    String? vehicleNumber,
    required String idempotencyKey,
  }) =>
      _withEdgeFallback(
        () async {
          final payload = <String, dynamic>{
            'vehicleType': vehicleType,
            'issue': issue,
            'lat': lat,
            'lng': lng,
            'idempotencyKey': idempotencyKey,
          };
          if (address != null && address.trim().isNotEmpty) {
            payload['address'] = address.trim();
          }
          if (note != null && note.trim().isNotEmpty) {
            payload['note'] = note.trim();
          }
          if (vehicleNumber != null && vehicleNumber.trim().isNotEmpty) {
            payload['vehicleNumber'] = vehicleNumber.trim();
          }
          final data = await _post(
            '/v1/bookings',
            body: payload,
            extraHeaders: {'Idempotency-Key': idempotencyKey},
          );
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.createBooking(
          getToken(),
          vehicleType: vehicleType,
          issue: issue,
          lat: lat,
          lng: lng,
          address: address,
          note: note,
          vehicleNumber: vehicleNumber,
        ),
      );

  Future<Booking?> getActiveBooking() => _withEdgeFallback(
        () async {
          final data = await _get('/v1/bookings/active');
          final b = data['booking'];
          if (b == null) return null;
          return Booking.fromJson(b as Map<String, dynamic>);
        },
        () => LocalEdgeFallback.getActiveBooking(getToken()),
      );

  Future<List<Booking>> listBookings() => _withEdgeFallback(
        () async {
          final data = await _get('/v1/bookings');
          final list = (data['bookings'] as List?) ?? const [];
          return list
              .map((e) => Booking.fromJson(e as Map<String, dynamic>))
              .toList();
        },
        () => LocalEdgeFallback.listBookings(getToken()),
      );

  Future<Booking> getBooking(String id) => _withEdgeFallback(
        () async {
          final data = await _get('/v1/bookings/$id');
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.getBooking(getToken(), id),
      );

  Future<Booking> cancelBooking(String id, {String? reason}) => _withEdgeFallback(
        () async {
          final body = <String, dynamic>{};
          if (reason != null && reason.trim().isNotEmpty) {
            body['reason'] = reason.trim();
          }
          final data = await _post('/v1/bookings/$id/cancel', body: body);
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.cancelBooking(getToken(), id),
      );

  Future<Booking> decideCharge(
    String bookingId,
    String chargeId,
    String decision,
  ) =>
      _withEdgeFallback(
        () async {
          final data = await _post(
            '/v1/bookings/$bookingId/charges/$chargeId/decision',
            body: {'decision': decision},
          );
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.decideCharge(getToken(), bookingId, chargeId, decision),
      );

  Future<Booking> rateBooking(
    String bookingId,
    int stars, {
    String? comment,
  }) =>
      _withEdgeFallback(
        () async {
          final body = <String, dynamic>{'stars': stars};
          if (comment != null && comment.trim().isNotEmpty) {
            body['comment'] = comment.trim();
          }
          final data = await _post('/v1/bookings/$bookingId/rating', body: body);
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.rateBooking(getToken(), bookingId, stars, comment),
      );

  // ---------------------------------------------------------------------------
  // Partner (Mechanic) Flow
  // ---------------------------------------------------------------------------

  Future<({PartnerProfile? partner, Booking? activeBooking})> getPartnerMe() =>
      _withEdgeFallback(
        () async {
          final data = await _get('/v1/partner/me');
          final p = data['partner'] != null
              ? PartnerProfile.fromJson(data['partner'] as Map<String, dynamic>)
              : null;
          final b = data['activeBooking'] != null
              ? Booking.fromJson(data['activeBooking'] as Map<String, dynamic>)
              : null;
          return (partner: p, activeBooking: b);
        },
        () => LocalEdgeFallback.getPartnerMe(getToken()),
      );

  Future<void> applyPartner({
    required String name,
    required String shopName,
    required List<String> vehicleTypes,
    String? upiId,
  }) =>
      _withEdgeFallback(
        () async {
          final body = <String, dynamic>{
            'name': name.trim(),
            'shopName': shopName.trim(),
            'vehicleTypes': vehicleTypes,
          };
          if (upiId != null && upiId.trim().isNotEmpty) {
            body['upiId'] = upiId.trim();
          }
          await _post('/v1/partner/apply', body: body);
        },
        () => LocalEdgeFallback.applyPartner(
          getToken(),
          name: name,
          shopName: shopName,
          vehicleTypes: vehicleTypes,
          upiId: upiId,
        ),
      );

  Future<void> uploadPartnerDocument({
    required String kind,
    required List<int> bytes,
    required String filename,
  }) =>
      _withEdgeFallback(
        () async {
          final req = http.MultipartRequest(
            'POST',
            _uri('/v1/partner/documents/$kind'),
          );
          final token = getToken();
          if (token != null && token.isNotEmpty) {
            req.headers['Authorization'] = 'Bearer $token';
          }
          req.files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
            ),
          );
          final streamed = await _http.send(req).timeout(const Duration(milliseconds: 1200));
          final res = await http.Response.fromStream(streamed);
          _decodeResponse(res);
        },
        () => LocalEdgeFallback.uploadDocument(getToken(), kind),
      );

  Future<void> setAvailability({
    required bool isOnline,
    double? lat,
    double? lng,
  }) =>
      _withEdgeFallback(
        () async {
          final body = <String, dynamic>{'isOnline': isOnline};
          if (lat != null) body['lat'] = lat;
          if (lng != null) body['lng'] = lng;
          await _post('/v1/partner/availability', body: body);
        },
        () => LocalEdgeFallback.setAvailability(
          getToken(),
          isOnline: isOnline,
          lat: lat,
          lng: lng,
        ),
      );

  Future<void> sendLocation({
    required double lat,
    required double lng,
  }) =>
      _withEdgeFallback(
        () async {
          await _post('/v1/partner/location', body: {'lat': lat, 'lng': lng});
        },
        () async {},
      );

  Future<List<JobOffer>> listOffers() => _withEdgeFallback(
        () async {
          final data = await _get('/v1/partner/offers');
          final list = (data['offers'] as List?) ?? const [];
          return list
              .map((e) => JobOffer.fromJson(e as Map<String, dynamic>))
              .toList();
        },
        () => LocalEdgeFallback.listOffers(getToken()),
      );

  Future<Booking> acceptOffer(String bookingId) => _withEdgeFallback(
        () async {
          final data = await _post('/v1/partner/bookings/$bookingId/accept');
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.acceptOffer(getToken(), bookingId),
      );

  Future<void> rejectOffer(String bookingId) => _withEdgeFallback(
        () async {
          await _post('/v1/partner/bookings/$bookingId/reject');
        },
        () async {},
      );

  Future<Booking> markArrived(String bookingId) => _withEdgeFallback(
        () async {
          final data = await _post('/v1/partner/bookings/$bookingId/arrive');
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.markArrived(getToken(), bookingId),
      );

  Future<Booking> startWork(String bookingId, String otp) => _withEdgeFallback(
        () async {
          final data = await _post(
            '/v1/partner/bookings/$bookingId/start',
            body: {'otp': otp.trim()},
          );
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.startWork(getToken(), bookingId, otp),
      );

  Future<Booking> addCharge(
    String bookingId, {
    required String description,
    required int amountPaise,
  }) =>
      _withEdgeFallback(
        () async {
          final data = await _post(
            '/v1/partner/bookings/$bookingId/charges',
            body: {
              'description': description.trim(),
              'amountPaise': amountPaise,
            },
          );
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.addCharge(
          getToken(),
          bookingId,
          description: description,
          amountPaise: amountPaise,
        ),
      );

  Future<Booking> completeBooking(
    String bookingId, {
    required String paymentMethod,
  }) =>
      _withEdgeFallback(
        () async {
          final data = await _post(
            '/v1/partner/bookings/$bookingId/complete',
            body: {'paymentMethod': paymentMethod},
          );
          return Booking.fromJson(data);
        },
        () => LocalEdgeFallback.completeBooking(
          getToken(),
          bookingId,
          paymentMethod: paymentMethod,
        ),
      );

  Future<EarningsSummary> getEarnings() => _withEdgeFallback(
        () async {
          final data = await _get('/v1/partner/earnings');
          return EarningsSummary.fromJson(data);
        },
        () => LocalEdgeFallback.getEarnings(getToken()),
      );

  Future<void> adminApprovePartner(String userId) => _withEdgeFallback(
        () async {
          await _post(
            '/v1/admin/partners/$userId/decision',
            body: {'status': 'approved'},
          );
        },
        () => LocalEdgeFallback.approvePartner(userId),
      );

  // ---------------------------------------------------------------------------
  // Socket.IO Realtime Connection
  // ---------------------------------------------------------------------------

  io.Socket? connectSocket({
    required void Function(String event, Map<String, dynamic> data) onEvent,
  }) {
    if (_remoteUnreachable) {
      return null;
    }
    final token = getToken() ?? '';
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    const events = [
      'booking:updated',
      'offer:new',
      'offer:closed',
      'partner:location',
    ];

    for (final evt in events) {
      socket.on(evt, (payload) {
        if (payload is Map) {
          onEvent(evt, Map<String, dynamic>.from(payload));
        }
      });
    }

    return socket;
  }
}
