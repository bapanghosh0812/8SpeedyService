import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class SessionController extends ChangeNotifier {
  final String storagePrefix;
  final String defaultApiBaseUrl;
  final String firebaseProjectId;
  final String firebaseWebApiKey;
  final String masterAuthPhonesRaw;
  final String masterAuthOtp;

  final String _apiBaseUrl;
  String? _token;
  String? _userId;
  String? _phone;
  String? _name;
  bool _initialized = false;
  String? _pendingSessionInfo;
  String? _pendingPhoneE164;

  SessionController({
    required this.storagePrefix,
    this.defaultApiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8080',
    ),
    this.firebaseProjectId = const String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'speedyservice-dev',
    ),
    this.firebaseWebApiKey = const String.fromEnvironment(
      'FIREBASE_WEB_API_KEY',
      defaultValue: '',
    ),
    this.masterAuthPhonesRaw = const String.fromEnvironment(
      'MASTER_AUTH_PHONES',
      defaultValue: '+919883290273,+919635297320',
    ),
    this.masterAuthOtp = const String.fromEnvironment(
      'MASTER_AUTH_OTP',
      defaultValue: '123456',
    ),
  }) : _apiBaseUrl = defaultApiBaseUrl;

  bool get initialized => _initialized;
  bool get isSignedIn => _token != null && _token!.isNotEmpty;
  bool get isLocalEmulatorMode => firebaseWebApiKey.isEmpty;
  String get apiBaseUrl => _apiBaseUrl;
  String? get token => _token;
  String? get userId => _userId;
  String? get phone => _phone;
  String? get name => _name;

  Set<String> get _allowedMasterPhones => masterAuthPhonesRaw
      .split(',')
      .map((s) => normalizeIndianPhone(s.trim()))
      .whereType<String>()
      .toSet();

  late final SpeedyApiClient api = SpeedyApiClient(
    baseUrl: _apiBaseUrl,
    getToken: () => _token,
  );

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('${storagePrefix}_token');
    final savedPhone = prefs.getString('${storagePrefix}_phone');
    final savedName = prefs.getString('${storagePrefix}_name');
    final savedUserId = prefs.getString('${storagePrefix}_user_id');

    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      _phone = savedPhone;
      _name = savedName;
      _userId = savedUserId;
      if (isLocalEmulatorMode && savedPhone != null && savedPhone.isNotEmpty) {
        _token = mintEmulatorJwt(
          phoneE164: savedPhone,
          projectId: firebaseProjectId,
        );
        await prefs.setString('${storagePrefix}_token', _token!);
      }
    }
    _initialized = true;
    notifyListeners();
  }

  static String? normalizeIndianPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    String ten = digits;
    if (digits.length == 12 && digits.startsWith('91')) {
      ten = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      ten = digits.substring(1);
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(ten)) {
      return null;
    }
    return '+91$ten';
  }

  /// Step 1 of Phone Auth: Validates the 10-digit Indian mobile number and requests OTP.
  Future<void> requestOtp(String rawPhone, {String? recaptchaToken}) async {
    final e164 = normalizeIndianPhone(rawPhone);
    if (e164 == null) {
      throw const ApiException(
        status: 400,
        code: 'INVALID_PHONE',
        message: 'Enter a valid 10-digit Indian mobile number',
      );
    }

    if (firebaseWebApiKey.isNotEmpty) {
      final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=$firebaseWebApiKey',
      );
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phoneNumber': e164,
          if (recaptchaToken != null) 'recaptchaToken': recaptchaToken,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (body['error']?['message'] as String?) ?? 'OTP request failed';
        throw ApiException(status: res.statusCode, code: 'FIREBASE_OTP_ERROR', message: msg);
      }
      _pendingPhoneE164 = e164;
      _pendingSessionInfo = body['sessionInfo'] as String?;
    } else {
      final allowed = _allowedMasterPhones;
      if (allowed.isNotEmpty && !allowed.contains(e164)) {
        throw const ApiException(
          status: 403,
          code: 'UNAUTHORIZED_PHONE',
          message: 'This mobile number is not authorized',
        );
      }
      _pendingPhoneE164 = e164;
      _pendingSessionInfo = 'session_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Step 2 of Phone Auth: Verifies the 6-digit SMS OTP and signs in.
  Future<void> verifyOtpAndSignIn(String smsCode, {String? displayName}) async {
    final cleanCode = smsCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(cleanCode)) {
      throw const ApiException(
        status: 400,
        code: 'INVALID_OTP',
        message: 'Enter the 6-digit verification code',
      );
    }
    final e164 = _pendingPhoneE164;
    if (e164 == null) {
      throw const ApiException(
        status: 400,
        code: 'NO_PENDING_PHONE',
        message: 'Please request an OTP first',
      );
    }

    String idToken;
    if (firebaseWebApiKey.isNotEmpty) {
      final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=$firebaseWebApiKey',
      );
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sessionInfo': _pendingSessionInfo,
          'code': cleanCode,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (body['error']?['message'] as String?) ?? 'Invalid OTP code';
        throw ApiException(status: res.statusCode, code: 'FIREBASE_VERIFY_ERROR', message: msg);
      }
      idToken = body['idToken'] as String;
    } else {
      if (cleanCode != masterAuthOtp.trim()) {
        throw const ApiException(
          status: 401,
          code: 'INVALID_OTP',
          message: 'Incorrect OTP code',
        );
      }
      idToken = mintEmulatorJwt(
        phoneE164: e164,
        projectId: firebaseProjectId,
      );
    }

    _token = idToken;
    _phone = e164;

    if (displayName != null && displayName.trim().isNotEmpty) {
      await api.updateMe(displayName.trim());
    }

    final me = await api.getMe();
    _userId = me['id'] as String?;
    _phone = (me['phone'] as String?) ?? e164;
    _name = me['name'] as String?;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${storagePrefix}_token', _token!);
    await prefs.setString('${storagePrefix}_phone', _phone!);
    if (_userId != null) {
      await prefs.setString('${storagePrefix}_user_id', _userId!);
    }
    if (_name != null) {
      await prefs.setString('${storagePrefix}_name', _name!);
    }

    notifyListeners();
  }

  Future<void> updateDisplayName(String newName) async {
    final res = await api.updateMe(newName);
    _name = res['name'] as String?;
    final prefs = await SharedPreferences.getInstance();
    if (_name != null) {
      await prefs.setString('${storagePrefix}_name', _name!);
    }
    notifyListeners();
  }

  Future<void> devAdminApprovePartner(String targetUserId) async {
    if (!isLocalEmulatorMode) {
      throw const ApiException(
        status: 403,
        code: 'PRODUCTION_ADMIN_ONLY',
        message: 'Use the backend admin CLI in production',
      );
    }
    final adminToken = mintEmulatorJwt(
      phoneE164: '+919883290273',
      projectId: firebaseProjectId,
      isAdmin: true,
    );
    final adminClient = SpeedyApiClient(
      baseUrl: _apiBaseUrl,
      getToken: () => adminToken,
    );
    await adminClient.adminApprovePartner(targetUserId);
  }

  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _phone = null;
    _name = null;
    _pendingPhoneE164 = null;
    _pendingSessionInfo = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${storagePrefix}_token');
    await prefs.remove('${storagePrefix}_phone');
    await prefs.remove('${storagePrefix}_name');
    await prefs.remove('${storagePrefix}_user_id');
    notifyListeners();
  }

  static String mintEmulatorJwt({
    required String phoneE164,
    required String projectId,
    bool isAdmin = false,
  }) {
    final uid = 'uid_${phoneE164.replaceAll(RegExp(r'\D'), '')}';
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final header = _b64Url({'alg': 'none', 'typ': 'JWT'});
    final payload = _b64Url({
      'iss': 'https://securetoken.google.com/$projectId',
      'aud': projectId,
      'auth_time': nowSec - 5,
      'user_id': uid,
      'sub': uid,
      'iat': nowSec - 5,
      'exp': nowSec + 86400 * 365,
      'phone_number': phoneE164,
      if (isAdmin) 'admin': true,
      'firebase': {
        'identities': {
          'phone': [phoneE164],
        },
        'sign_in_provider': 'phone',
      },
    });
    return '$header.$payload.';
  }

  static String _b64Url(Map<String, dynamic> jsonMap) {
    final raw = utf8.encode(jsonEncode(jsonMap));
    return base64Url.encode(raw).replaceAll('=', '');
  }
}
