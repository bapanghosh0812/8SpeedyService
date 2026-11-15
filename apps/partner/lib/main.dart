import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:speedy_core/speedy_core.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController(storagePrefix: 'speedy_partner');
  await session.init();
  runApp(SpeedyPartnerApp(session: session));
}

class SpeedyPartnerApp extends StatelessWidget {
  final SessionController session;

  const SpeedyPartnerApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return MaterialApp(
          title: '8SpeedyService Partner',
          debugShowCheckedModeBanner: false,
          theme: SpeedyTheme.light(),
          darkTheme: SpeedyTheme.dark(),
          themeMode: ThemeMode.light,
          home: session.isSignedIn
              ? PartnerConsoleScreen(session: session)
              : PartnerAuthScreen(session: session),
        );
      },
    );
  }
}

// =============================================================================
// PARTNER PHONE LOGIN SCREEN
// =============================================================================

class PartnerAuthScreen extends StatefulWidget {
  final SessionController session;

  const PartnerAuthScreen({super.key, required this.session});

  @override
  State<PartnerAuthScreen> createState() => _PartnerAuthScreenState();
}

class _PartnerAuthScreenState extends State<PartnerAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.requestOtp(_phoneCtrl.text);
      if (mounted) setState(() => _otpSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.verifyOtpAndSignIn(_otpCtrl.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: SpeedyLogoMark(size: 72, borderRadius: 20),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '8SpeedyService',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SpeedyPalette.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PARTNER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mechanic Duty, Live Job Dispatch & Earnings Console',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _otpSent ? 'Verify 6-digit OTP' : 'Partner Phone Login',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (!_otpSent)
                            TextField(
                              key: const Key('partner_phone_input'),
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Mechanic Mobile Number',
                                hintText: '9765432109',
                                prefixText: '+91 ',
                                prefixIcon: Icon(Icons.phone_android_rounded),
                              ),
                            )
                          else ...[
                            TextField(
                              key: const Key('partner_otp_input'),
                              controller: _otpCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 6,
                              ),
                              decoration: const InputDecoration(
                                labelText: '6-Digit OTP',
                                counterText: '',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SpeedyPalette.dangerRed.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: SpeedyPalette.dangerRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            key: const Key('partner_auth_submit'),
                            onPressed: _busy ? null : (_otpSent ? _verifyOtp : _sendOtp),
                            child: _busy
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(_otpSent ? 'Verify & Open Console' : 'Get OTP'),
                          ),
                          if (_otpSent) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _otpSent = false;
                                        _error = null;
                                      }),
                              child: const Text('Change mobile number'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PARTNER MAIN CONSOLE (Onboarding / Pending KYC / Live Duty / Earnings)
// =============================================================================

class PartnerConsoleScreen extends StatefulWidget {
  final SessionController session;

  const PartnerConsoleScreen({super.key, required this.session});

  @override
  State<PartnerConsoleScreen> createState() => _PartnerConsoleScreenState();
}

class _PartnerConsoleScreenState extends State<PartnerConsoleScreen> {
  int _tabIndex = 0;
  bool _loading = true;
  String? _error;

  PartnerProfile? _partner;
  Booking? _activeBooking;
  List<JobOffer> _offers = const [];
  EarningsSummary? _earnings;

  // Default mechanic GPS (Pune — near customer default so instant dispatch works out of the box)
  final double _lat = 18.5212;
  final double _lng = 73.8574;

  final _otpStartCtrl = TextEditingController();

  io.Socket? _socket;
  Timer? _pollTimer;

  // Minimal valid 1x1 PNG for instant KYC verification upload testing
  static final List<int> _sampleValidPngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket?.dispose();
    _otpStartCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _connectRealtime();
    await _refreshAll();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshAll(silent: true);
    });
  }

  void _connectRealtime() {
    _socket?.dispose();
    _socket = widget.session.api.connectSocket(
      onEvent: (event, data) {
        if (!mounted) return;
        if (event == 'offer:new' || event == 'offer:closed') {
          _refreshOffers();
        } else if (event == 'booking:updated') {
          final b = Booking.fromJson(data);
          setState(() {
            _activeBooking = b.isLive ? b : null;
          });
          _refreshAll(silent: true);
        }
      },
    );
  }

  Future<void> _refreshAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final me = await widget.session.api.getPartnerMe();
      List<JobOffer> offers = const [];
      EarningsSummary? earnings;

      if (me.partner != null && me.partner!.status == 'approved') {
        final results = await Future.wait([
          widget.session.api.listOffers(),
          widget.session.api.getEarnings(),
        ]);
        offers = results[0] as List<JobOffer>;
        earnings = results[1] as EarningsSummary;
      }

      if (mounted) {
        setState(() {
          _partner = me.partner;
          _activeBooking = me.activeBooking;
          _offers = offers;
          _earnings = earnings;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (!silent) _error = e.toString();
        });
      }
    }
  }

  Future<void> _refreshOffers() async {
    try {
      final offers = await widget.session.api.listOffers();
      if (mounted) setState(() => _offers = offers);
    } catch (_) {}
  }

  Future<void> _toggleOnline(bool online) async {
    try {
      await widget.session.api.setAvailability(
        isOnline: online,
        lat: _lat,
        lng: _lng,
      );
      await _refreshAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _acceptOffer(JobOffer offer) async {
    try {
      final b = await widget.session.api.acceptOffer(offer.bookingId);
      if (mounted) {
        setState(() {
          _activeBooking = b;
          _offers = const [];
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      await _refreshOffers();
    }
  }

  Future<void> _rejectOffer(JobOffer offer) async {
    try {
      await widget.session.api.rejectOffer(offer.bookingId);
      await _refreshOffers();
    } catch (_) {}
  }

  Future<void> _markArrived() async {
    final active = _activeBooking;
    if (active == null) return;
    try {
      final b = await widget.session.api.markArrived(active.id);
      if (mounted) setState(() => _activeBooking = b);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _startRepairWithOtp() async {
    final active = _activeBooking;
    if (active == null) return;
    try {
      final b = await widget.session.api.startWork(active.id, _otpStartCtrl.text);
      _otpStartCtrl.clear();
      if (mounted) setState(() => _activeBooking = b);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _showAddExtraChargeDialog() async {
    final active = _activeBooking;
    if (active == null) return;
    final descCtrl = TextEditingController();
    final rupeesCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Extra Part / Repair Charge',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Customer will receive an instant approval request on their app.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Part / Labour Description (e.g. Heavy Duty Tube)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rupeesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount in ₹ (e.g. 250)',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final rupees = int.tryParse(rupeesCtrl.text.trim()) ?? 0;
                  if (descCtrl.text.trim().length < 2 || rupees <= 0) return;
                  Navigator.pop(ctx);
                  try {
                    final updated = await widget.session.api.addCharge(
                      active.id,
                      description: descCtrl.text.trim(),
                      amountPaise: rupees * 100,
                    );
                    if (mounted) setState(() => _activeBooking = updated);
                  } on ApiException catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  }
                },
                child: const Text('Send to Customer for Approval'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _completeJob(String paymentMethod) async {
    final active = _activeBooking;
    if (active == null) return;
    try {
      await widget.session.api.completeBooking(
        active.id,
        paymentMethod: paymentMethod,
      );
      if (mounted) {
        setState(() => _activeBooking = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job completed (${paymentMethod.toUpperCase()})! Earnings updated.'),
          ),
        );
      }
      await _refreshAll(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _partner;
    final isApproved = p != null && p.status == 'approved';

    return Scaffold(
      appBar: AppBar(
        title: SpeedyBrandHeader(
          badgeText: 'PARTNER',
          subtitle: p?.shopName ?? widget.session.phone ?? 'Mechanic Console',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refreshAll(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign Out',
            onPressed: () => widget.session.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && p == null
            ? const Center(child: CircularProgressIndicator())
            : p == null
                ? _PartnerApplicationForm(
                    onSubmitted: () => _refreshAll(),
                    session: widget.session,
                  )
                : !isApproved
                    ? _buildPendingVerificationView(p)
                    : _tabIndex == 0
                        ? _buildDutyTab(p)
                        : _buildEarningsTab(),
      ),
      bottomNavigationBar: isApproved
          ? NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.radar_rounded),
                  label: 'Duty & Jobs',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  label: 'Earnings & Ledger',
                ),
              ],
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // KYC & PENDING VERIFICATION SCREEN
  // ---------------------------------------------------------------------------

  Widget _buildPendingVerificationView(PartnerProfile p) {
    final requiredDocs = const [
      (id: 'id_proof', label: 'Government ID Proof (Aadhaar / DL)'),
      (id: 'selfie', label: 'Mechanic Live Selfie'),
      (id: 'shop_photo', label: 'Garage / Tool Kit Photo'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: SpeedyPalette.accentAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'STATUS: ${p.status.toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  p.shopName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vehicles: ${p.vehicleTypes.join(', ').toUpperCase()}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const Divider(height: 24),
                const Text(
                  'KYC Verification Documents',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                ...requiredDocs.map((doc) {
                  final uploaded = p.documentsUploaded.contains(doc.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      uploaded
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      color: uploaded
                          ? SpeedyPalette.successTeal
                          : SpeedyPalette.primary,
                    ),
                    title: Text(
                      doc.label,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    trailing: uploaded
                        ? const Text(
                            'Uploaded',
                            style: TextStyle(
                              color: SpeedyPalette.successTeal,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          )
                        : OutlinedButton(
                            onPressed: () async {
                              await widget.session.api.uploadPartnerDocument(
                                kind: doc.id,
                                bytes: _sampleValidPngBytes,
                                filename: '${doc.id}.png',
                              );
                              await _refreshAll(silent: true);
                            },
                            child: const Text('Upload'),
                          ),
                  );
                }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Admin CLI Approval Command:\nnpm run admin -- approve ${p.phone}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.session.isLocalEmulatorMode) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('dev_instant_approve_button'),
                    onPressed: () async {
                      await widget.session.devAdminApprovePartner(p.userId);
                      await _refreshAll();
                    },
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Instant Admin Approve (Local Dev)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: DUTY SWITCH, INCOMING JOB OFFERS & ACTIVE JOB EXECUTION
  // ---------------------------------------------------------------------------

  Widget _buildDutyTab(PartnerProfile p) {
    final active = _activeBooking;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: SpeedyPalette.dangerRed),
            ),
          ),

        // ONLINE / OFFLINE DUTY HEADER CARD
        Card(
          color: p.isOnline ? const Color(0xFFF0FDF4) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: p.isOnline ? SpeedyPalette.successTeal : const Color(0xFFE2E8F0),
              width: p.isOnline ? 1.6 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  p.isOnline ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                  size: 32,
                  color: p.isOnline ? SpeedyPalette.successTeal : const Color(0xFF64748B),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.isOnline ? 'YOU ARE ONLINE' : 'YOU ARE OFFLINE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: p.isOnline
                              ? SpeedyPalette.successTeal
                              : const Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.isOnline
                            ? 'Receiving nearby breakdown alerts (3–10 km)'
                            : 'Go online to receive roadside repair jobs',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('partner_online_switch'),
                  value: p.isOnline,
                  onChanged: _toggleOnline,
                ),
              ],
            ),
          ),
        ),

        // INCOMING FULL-PRIORITY JOB OFFERS
        if (active == null && _offers.isNotEmpty) ...[
          const SizedBox(height: 16),
          ..._offers.map((offer) {
            final remainingSec = offer.expiresAt
                .difference(DateTime.now())
                .inSeconds
                .clamp(0, 60);
            final distKm = (offer.distanceMeters / 1000).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: const Color(0xFFFFFBEB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: SpeedyPalette.accentAmber, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: SpeedyPalette.accentAmber,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'NEW JOB OFFER • ${remainingSec}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          Text(
                            '$distKm km away',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${offer.vehicleType.toUpperCase()} • ${offer.issue.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Text(
                            formatRupeesFromPaise(offer.visitFeePaise),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: SpeedyPalette.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        offer.address ?? 'GPS: ${offer.lat}, ${offer.lng}',
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
                      ),
                      if (offer.note != null && offer.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Note: ${offer.note}',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _rejectOffer(offer),
                              child: const Text('Pass'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              key: Key('accept_offer_${offer.bookingId}'),
                              onPressed: () => _acceptOffer(offer),
                              icon: const Icon(Icons.check_circle_outline_rounded),
                              label: const Text('ACCEPT JOB'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],

        // IDLE STATE WHEN ONLINE WITH NO OFFERS
        if (active == null && _offers.isEmpty) ...[
          const SizedBox(height: 36),
          Center(
            child: Column(
              children: [
                Icon(
                  p.isOnline ? Icons.radar_rounded : Icons.pause_circle_outline_rounded,
                  size: 56,
                  color: const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                Text(
                  p.isOnline
                      ? 'Waiting for nearby roadside requests...'
                      : 'Switch to ONLINE above to start receiving jobs.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ACTIVE JOB CONSOLE
        if (active != null) ...[
          const SizedBox(height: 16),
          _buildActiveJobCard(active),
        ],
      ],
    );
  }

  Widget _buildActiveJobCard(Booking b) {
    final hasPendingCharge = b.charges.any((c) => c.status == 'pending');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACTIVE JOB • ${b.code}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: SpeedyPalette.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: SpeedyPalette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    b.status.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: SpeedyPalette.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${b.vehicleType.toUpperCase()} — ${b.issue.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              b.address ?? 'GPS: ${b.lat}, ${b.lng}',
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
            ),
            if (b.customer != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.customer!.name ?? 'Customer',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          b.customer!.phone,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      launchUrl(Uri.parse('tel:${b.customer!.phone}'));
                    },
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Call'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final url = Uri.parse(
                        'https://www.google.com/maps/dir/?api=1&destination=${b.lat},${b.lng}',
                      );
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('Navigate'),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),

            // STEP 1: ACCEPTED -> MARK ARRIVED
            if (b.status == 'accepted') ...[
              FilledButton.icon(
                key: const Key('partner_mark_arrived_button'),
                onPressed: _markArrived,
                icon: const Icon(Icons.place_rounded),
                label: const Text('Reached Customer Location (Mark Arrived)'),
              ),
            ],

            // STEP 2: ARRIVED -> ENTER CUSTOMER'S 4-DIGIT START OTP
            if (b.status == 'arrived') ...[
              const Text(
                'Ask the customer for their 4-Digit Start Code:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('partner_start_otp_input'),
                controller: _otpStartCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  labelText: '4-Digit Start Code',
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('partner_verify_start_otp_button'),
                onPressed: _startRepairWithOtp,
                icon: const Icon(Icons.play_circle_fill_rounded),
                label: const Text('Verify Code & Start Repair'),
              ),
            ],

            // STEP 3: IN_PROGRESS -> EXTRA CHARGES + COMPLETE JOB
            if (b.status == 'in_progress') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bill & Extra Parts',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  TextButton.icon(
                    onPressed: _showAddExtraChargeDialog,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                    label: const Text('Add Part / Charge'),
                  ),
                ],
              ),
              if (b.charges.isNotEmpty)
                ...b.charges.map(
                  (c) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.description),
                    subtitle: Text('Status: ${c.status.toUpperCase()}'),
                    trailing: Text(
                      formatRupeesFromPaise(c.amountPaise),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total to Collect from Customer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      formatRupeesFromPaise(b.totalPaise),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: SpeedyPalette.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasPendingCharge) ...[
                const SizedBox(height: 10),
                const Text(
                  'Waiting for customer to approve or reject pending extra charges before completing.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('complete_cash_button'),
                      onPressed: hasPendingCharge ? null : () => _completeJob('cash'),
                      child: const Text('Complete (Cash)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('complete_upi_button'),
                      onPressed: hasPendingCharge ? null : () => _completeJob('upi'),
                      child: const Text('Complete (UPI)'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: EARNINGS & APPEND-ONLY LEDGER SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildEarningsTab() {
    final e = _earnings;
    if (e == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.65,
          children: [
            _MetricCard(
              label: 'NET EARNINGS',
              value: formatRupeesFromPaise(e.netEarningsPaise),
              valueColor: SpeedyPalette.successTeal,
            ),
            _MetricCard(
              label: 'COMPLETED JOBS',
              value: '${e.completedJobs}',
              valueColor: SpeedyPalette.primary,
            ),
            _MetricCard(
              label: 'GROSS COLLECTED',
              value: formatRupeesFromPaise(e.grossPaise),
              valueColor: const Color(0xFF0F172A),
            ),
            _MetricCard(
              label: 'COMMISSION DUE (15%)',
              value: formatRupeesFromPaise(e.commissionBalanceDuePaise),
              valueColor: SpeedyPalette.accentAmber,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Recent Completed Jobs',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        if (e.recentJobs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No completed jobs yet.'),
            ),
          )
        else
          ...e.recentJobs.map(
            (j) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(
                    '${j.code} • ${j.vehicleType.toUpperCase()} (${j.issue})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Paid via ${j.paymentMethod.toUpperCase()} • Commission: ${formatRupeesFromPaise(j.commissionPaise)}',
                  ),
                  trailing: Text(
                    formatRupeesFromPaise(j.netPaise),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: SpeedyPalette.successTeal,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PARTNER APPLICATION FORM (When mechanic first signs in)
// =============================================================================

class _PartnerApplicationForm extends StatefulWidget {
  final SessionController session;
  final VoidCallback onSubmitted;

  const _PartnerApplicationForm({
    required this.session,
    required this.onSubmitted,
  });

  @override
  State<_PartnerApplicationForm> createState() => _PartnerApplicationFormState();
}

class _PartnerApplicationFormState extends State<_PartnerApplicationForm> {
  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final Set<String> _selectedVehicles = {'bike', 'scooter', 'car'};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().length < 2 ||
        _shopCtrl.text.trim().length < 2 ||
        _selectedVehicles.isEmpty) {
      setState(() => _error = 'Enter your name, workshop name, and at least 1 vehicle type.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.session.api.applyPartner(
        name: _nameCtrl.text,
        shopName: _shopCtrl.text,
        vehicleTypes: _selectedVehicles.toList(),
        upiId: _upiCtrl.text.trim().isEmpty ? null : _upiCtrl.text.trim(),
      );
      widget.onSubmitted();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Register Your Mechanic Workshop',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Complete your profile to receive instant roadside repair jobs near you.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('apply_name_input'),
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mechanic Full Name',
                    hintText: 'Ramesh Patil',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('apply_shop_input'),
                  controller: _shopCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Garage / Workshop Name',
                    hintText: 'Shree Ganesh Auto Works',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('apply_upi_input'),
                  controller: _upiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID for Customer Payments (Optional)',
                    hintText: 'ganeshauto@okaxis',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vehicles You Repair:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: Catalog.fallback.vehicles.map((v) {
                    final checked = _selectedVehicles.contains(v.id);
                    return FilterChip(
                      label: Text(v.label),
                      selected: checked,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedVehicles.add(v.id);
                          } else {
                            _selectedVehicles.remove(v.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: SpeedyPalette.dangerRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('partner_apply_submit'),
                  onPressed: _submitting ? null : _submit,
                  child: const Text('Submit Partner Application'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
