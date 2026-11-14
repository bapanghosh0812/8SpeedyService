import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:speedy_core/speedy_core.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController(storagePrefix: 'speedy_customer');
  await session.init();
  runApp(SpeedyCustomerApp(session: session));
}

class SpeedyCustomerApp extends StatelessWidget {
  final SessionController session;

  const SpeedyCustomerApp({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return MaterialApp(
          title: '8SpeedyService',
          debugShowCheckedModeBanner: false,
          theme: SpeedyTheme.light(),
          darkTheme: SpeedyTheme.dark(),
          themeMode: ThemeMode.light,
          home: session.isSignedIn
              ? CustomerHomeScreen(session: session)
              : CustomerAuthScreen(session: session),
        );
      },
    );
  }
}

// =============================================================================
// PHONE LOGIN SCREEN (Customer)
// =============================================================================

class CustomerAuthScreen extends StatefulWidget {
  final SessionController session;

  const CustomerAuthScreen({super.key, required this.session});

  @override
  State<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends State<CustomerAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
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
      if (widget.session.isLocalEmulatorMode && _otpCtrl.text.isEmpty) {
        _otpCtrl.text = '123456';
      }
      if (mounted) {
        setState(() => _otpSent = true);
      }
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
      await widget.session.verifyOtpAndSignIn(
        _otpCtrl.text,
        displayName: _nameCtrl.text,
      );
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
                  const SizedBox(height: 18),
                  Text(
                    '8SpeedyService',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Instant on-road mechanic in 3 taps',
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
                            _otpSent ? 'Verify 6-digit OTP' : 'Sign in with mobile number',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (!_otpSent) ...[
                            TextField(
                              key: const Key('customer_phone_input'),
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Mobile Number',
                                hintText: '9876543210',
                                prefixText: '+91 ',
                                prefixIcon: Icon(Icons.phone_android_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('customer_name_input'),
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Your Name (Optional)',
                                hintText: 'Rahul Sharma',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                            ),
                          ] else ...[
                            TextField(
                              key: const Key('customer_otp_input'),
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
                            if (widget.session.isLocalEmulatorMode)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Local Auth Emulator active — use any 6-digit OTP (e.g. 123456).',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: SpeedyPalette.primary,
                                  ),
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
                            key: const Key('customer_auth_submit'),
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
                                : Text(_otpSent ? 'Verify & Continue' : 'Get OTP'),
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
// CUSTOMER HOME: RAPIDO-STYLE 3-TAP INSTANT BOOKING & LIVE TRACKING
// =============================================================================

class CustomerHomeScreen extends StatefulWidget {
  final SessionController session;

  const CustomerHomeScreen({super.key, required this.session});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  Catalog _catalog = Catalog.fallback;
  String _selectedIssue = 'puncture';
  String _selectedVehicle = 'bike';

  // Default GPS coordinates (Pune, Maharashtra — inside India service boundary)
  double _lat = 18.5204;
  double _lng = 73.8567;
  String _address = 'MG Road, Camp, Pune, Maharashtra';

  final _vehicleNoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  Booking? _activeBooking;
  Booking? _recentlyCompletedForRating;
  double? _livePartnerLat;
  double? _livePartnerLng;

  bool _bookingSubmitting = false;
  String? _bannerError;

  io.Socket? _socket;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket?.dispose();
    _vehicleNoCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _connectRealtime();
    await Future.wait([
      _loadCatalog(),
      _refreshActiveBooking(),
    ]);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshActiveBooking(silent: true);
    });
  }

  void _connectRealtime() {
    _socket?.dispose();
    _socket = widget.session.api.connectSocket(
      onEvent: (event, data) {
        if (!mounted) return;
        if (event == 'booking:updated') {
          final updated = Booking.fromJson(data);
          setState(() {
            if (updated.isLive) {
              _activeBooking = updated;
              if (updated.partner?.lat != null && updated.partner?.lng != null) {
                _livePartnerLat = updated.partner!.lat;
                _livePartnerLng = updated.partner!.lng;
              }
            } else {
              _activeBooking = null;
              if (updated.status == 'completed' && updated.rating == null) {
                _recentlyCompletedForRating = updated;
              }
            }
          });
        } else if (event == 'partner:location') {
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            setState(() {
              _livePartnerLat = lat;
              _livePartnerLng = lng;
            });
          }
        }
      },
    );
  }

  Future<void> _loadCatalog() async {
    try {
      final cat = await widget.session.api.getCatalog();
      if (mounted && cat.vehicles.isNotEmpty && cat.issues.isNotEmpty) {
        setState(() => _catalog = cat);
      }
    } catch (_) {
      // Keep fallback catalog
    }
  }

  Future<void> _refreshActiveBooking({bool silent = false}) async {
    try {
      final prevId = _activeBooking?.id;
      final b = await widget.session.api.getActiveBooking();
      if (!mounted) return;
      if (b != null) {
        setState(() {
          _activeBooking = b;
          if (b.partner?.lat != null && b.partner?.lng != null) {
            _livePartnerLat = b.partner!.lat;
            _livePartnerLng = b.partner!.lng;
          }
        });
      } else if (prevId != null) {
        // Active booking ended — check if it completed so customer can rate
        final finished = await widget.session.api.getBooking(prevId);
        if (!mounted) return;
        setState(() {
          _activeBooking = null;
          if (finished.status == 'completed' && finished.rating == null) {
            _recentlyCompletedForRating = finished;
          }
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _bannerError = e.toString());
      }
    }
  }

  VehicleOption get _currentVehicleOption => _catalog.vehicles.firstWhere(
        (v) => v.id == _selectedVehicle,
        orElse: () => _catalog.vehicles.first,
      );

  IssueOption get _currentIssueOption => _catalog.issues.firstWhere(
        (i) => i.id == _selectedIssue,
        orElse: () => _catalog.issues.first,
      );

  Future<void> _bookNow() async {
    setState(() {
      _bookingSubmitting = true;
      _bannerError = null;
    });
    try {
      final idempotencyKey =
          'cust_${widget.session.userId ?? 'u'}_${DateTime.now().millisecondsSinceEpoch}';
      final created = await widget.session.api.createBooking(
        vehicleType: _selectedVehicle,
        issue: _selectedIssue,
        lat: _lat,
        lng: _lng,
        address: _address,
        note: _noteCtrl.text,
        vehicleNumber: _vehicleNoCtrl.text,
        idempotencyKey: idempotencyKey,
      );
      if (mounted) {
        setState(() => _activeBooking = created);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _bannerError = e.message);
    } catch (e) {
      if (mounted) setState(() => _bannerError = 'Booking failed: $e');
    } finally {
      if (mounted) setState(() => _bookingSubmitting = false);
    }
  }

  Future<void> _cancelActiveBooking() async {
    final active = _activeBooking;
    if (active == null) return;
    try {
      await widget.session.api.cancelBooking(active.id, reason: 'Cancelled by customer');
      if (mounted) {
        setState(() => _activeBooking = null);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _decideExtraCharge(BookingCharge charge, String decision) async {
    final active = _activeBooking;
    if (active == null) return;
    try {
      final updated = await widget.session.api.decideCharge(
        active.id,
        charge.id,
        decision,
      );
      if (mounted) {
        setState(() => _activeBooking = updated);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _showBookingHistorySheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) {
            return FutureBuilder<List<Booking>>(
              future: widget.session.api.listBookings(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No past bookings yet.'),
                  );
                }
                return ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final b = items[idx];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${b.code} • ${b.vehicleType.toUpperCase()} (${b.issue})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Status: ${b.status.toUpperCase()} • ${b.address ?? ''}',
                        ),
                        trailing: Text(
                          formatRupeesFromPaise(b.totalPaise),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _editLocationDialog() async {
    final addrCtrl = TextEditingController(text: _address);
    final presets = <({String label, double lat, double lng})>[
      (label: 'MG Road, Camp, Pune', lat: 18.5204, lng: 73.8567),
      (label: 'Andheri East, WEH Highway, Mumbai', lat: 19.1136, lng: 72.8697),
      (label: 'Silk Board Flyover, Bengaluru', lat: 12.9177, lng: 77.6238),
      (label: 'NH-48 Rajiv Chowk, Gurugram', lat: 28.4445, lng: 77.0266),
    ];
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
                'Breakdown Location',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Landmark / Road Name',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Quick GPS Presets:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...presets.map(
                (p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.my_location_rounded, size: 18),
                  title: Text(p.label),
                  onTap: () {
                    setState(() {
                      _address = p.label;
                      _lat = p.lat;
                      _lng = p.lng;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  if (addrCtrl.text.trim().isNotEmpty) {
                    setState(() => _address = addrCtrl.text.trim());
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Update Location'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeBooking;
    return Scaffold(
      appBar: AppBar(
        title: SpeedyBrandHeader(
          subtitle: widget.session.phone ?? 'Roadside Assistance',
        ),
        actions: [
          IconButton(
            tooltip: 'Booking History',
            onPressed: _showBookingHistorySheet,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Sign Out',
            onPressed: () => widget.session.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: active != null
            ? _buildActiveBookingView(active)
            : _buildThreeTapBookingView(),
      ),
      bottomNavigationBar: active == null ? _buildBottomBookBar() : null,
    );
  }

  // ---------------------------------------------------------------------------
  // RAPIDO-STYLE 3-TAP BOOKING VIEW
  // ---------------------------------------------------------------------------

  Widget _buildThreeTapBookingView() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (_recentlyCompletedForRating != null)
          _RatingPromptCard(
            booking: _recentlyCompletedForRating!,
            onRated: (stars, comment) async {
              final target = _recentlyCompletedForRating!;
              await widget.session.api.rateBooking(target.id, stars, comment: comment);
              if (mounted) {
                setState(() => _recentlyCompletedForRating = null);
              }
            },
            onDismiss: () => setState(() => _recentlyCompletedForRating = null),
          ),
        // GPS Pickup Header Card
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: 138,
                width: double.infinity,
                child: CustomPaint(
                  painter: _RoadRadarMapPainter(
                    customerLat: _lat,
                    customerLng: _lng,
                    partnerLat: null,
                    partnerLng: null,
                    isSearching: false,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gps_fixed_rounded, size: 14, color: Color(0xFF34D399)),
                            SizedBox(width: 6),
                            Text(
                              'GPS Locked • Verified Mechanics Ready',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: _editLocationDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: SpeedyPalette.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: SpeedyPalette.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BREAKDOWN LOCATION',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Change',
                        style: TextStyle(
                          color: SpeedyPalette.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_bannerError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SpeedyPalette.dangerRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _bannerError!,
              style: const TextStyle(
                color: SpeedyPalette.dangerRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        const SizedBox(height: 20),
        // TAP 1: PICK ISSUE
        Row(
          children: [
            _StepBadge(number: '1'),
            const SizedBox(width: 8),
            Text(
              'What happened to your vehicle?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _catalog.issues.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 64,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final issue = _catalog.issues[index];
            final selected = issue.id == _selectedIssue;
            return InkWell(
              key: Key('issue_${issue.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedIssue = issue.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? SpeedyPalette.primary.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? SpeedyPalette.primary : const Color(0xFFE2E8F0),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _iconForIssue(issue.id),
                      size: 22,
                      color: selected ? SpeedyPalette.primary : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        issue.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13.5,
                          color: selected
                              ? SpeedyPalette.primaryDark
                              : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 22),
        // TAP 2: PICK VEHICLE
        Row(
          children: [
            _StepBadge(number: '2'),
            const SizedBox(width: 8),
            Text(
              'Select your vehicle',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _catalog.vehicles.map((veh) {
            final selected = veh.id == _selectedVehicle;
            return InkWell(
              key: Key('vehicle_${veh.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedVehicle = veh.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? SpeedyPalette.primary
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? SpeedyPalette.primary : const Color(0xFFE2E8F0),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconForVehicle(veh.id),
                      size: 20,
                      color: selected ? Colors.white : const Color(0xFF334155),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      veh.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.2)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formatRupeesFromPaise(veh.visitFeePaise),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: selected ? Colors.white : SpeedyPalette.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 18),
        // Optional collapsed details (Vehicle number / note)
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text(
            'Add vehicle number or note (optional)',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          children: [
            const SizedBox(height: 6),
            TextField(
              controller: _vehicleNoCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Vehicle Number (e.g. MH12AB1234)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Landmark or issue details',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBookBar() {
    final vehicle = _currentVehicleOption;
    final issue = _currentIssueOption;
    final fee = formatRupeesFromPaise(vehicle.visitFeePaise);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${vehicle.label} • ${issue.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  'Fixed Visit Fee: $fee',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: SpeedyPalette.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('book_mechanic_button'),
              onPressed: _bookingSubmitting ? null : _bookNow,
              icon: _bookingSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.flash_on_rounded),
              label: Text('Book Mechanic • $fee'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LIVE BOOKING VIEW (Searching -> Accepted -> Arrived -> In Progress)
  // ---------------------------------------------------------------------------

  Widget _buildActiveBookingView(Booking b) {
    final partnerLat = _livePartnerLat ?? b.partner?.lat;
    final partnerLng = _livePartnerLng ?? b.partner?.lng;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Live Map & Status Banner
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: CustomPaint(
                  painter: _RoadRadarMapPainter(
                    customerLat: b.lat,
                    customerLng: b.lng,
                    partnerLat: partnerLat,
                    partnerLng: partnerLng,
                    isSearching: b.status == 'searching',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor(b.status),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusHeadline(b.status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Booking ${b.code} • ${b.vehicleType.toUpperCase()} (${b.issue})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (b.status == 'searching') ...[
                      const Text(
                        'Broadcasting your breakdown location to verified mechanics nearby (3 km → 6 km → 10 km)...',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _cancelActiveBooking,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel Booking Request'),
                      ),
                    ],
                    if (b.partner != null) ...[
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: SpeedyPalette.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.engineering_rounded,
                              color: SpeedyPalette.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.partner!.shopName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${b.partner!.name ?? 'Verified Mechanic'} • ★ ${b.partner!.rating?.toStringAsFixed(1) ?? 'New'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              launchUrl(Uri.parse('tel:${b.partner!.phone}'));
                            },
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: const Text('Call'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4-DIGIT START OTP CARD (Shown when accepted or arrived)
        if ((b.status == 'accepted' || b.status == 'arrived') && b.startOtp != null) ...[
          const SizedBox(height: 14),
          Card(
            color: const Color(0xFFF0F9FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: SpeedyPalette.primary, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '4-DIGIT START CODE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: SpeedyPalette.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Share this code with the mechanic only when they arrive at your vehicle.',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    key: const Key('customer_start_otp_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: SpeedyPalette.primaryDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      b.startOtp!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // EXTRA CHARGES APPROVAL GATE
        if (b.charges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Extra Parts / Repair Charges',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The mechanic cannot complete the job until you approve or reject extra items.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  ...b.charges.map((c) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    c.description,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  formatRupeesFromPaise(c.amountPaise),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (c.status == 'pending')
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _decideExtraCharge(c, 'rejected'),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _decideExtraCharge(c, 'approved'),
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Status: ${c.status.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: c.status == 'approved'
                                      ? SpeedyPalette.successTeal
                                      : SpeedyPalette.dangerRed,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],

        // BILL SUMMARY CARD
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bill Summary',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Fixed Visit & Inspection Fee'),
                    Text(
                      formatRupeesFromPaise(b.visitFeePaise),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Approved Extra Parts / Labour'),
                    Text(
                      formatRupeesFromPaise(b.extraPaise),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Payable (Cash / UPI)',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
                if (b.status == 'accepted' || b.status == 'arrived') ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _cancelActiveBooking,
                    child: const Text(
                      'Cancel Booking',
                      style: TextStyle(color: SpeedyPalette.dangerRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'searching':
        return SpeedyPalette.accentAmber;
      case 'accepted':
        return SpeedyPalette.primary;
      case 'arrived':
        return SpeedyPalette.successTeal;
      case 'in_progress':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF475569);
    }
  }

  static String _statusHeadline(String status) {
    switch (status) {
      case 'searching':
        return 'FINDING NEAREST MECHANIC...';
      case 'accepted':
        return 'MECHANIC ON THE WAY';
      case 'arrived':
        return 'MECHANIC HAS ARRIVED';
      case 'in_progress':
        return 'REPAIR IN PROGRESS';
      default:
        return status.toUpperCase();
    }
  }

  static IconData _iconForIssue(String id) {
    switch (id) {
      case 'puncture':
        return Icons.tire_repair_rounded;
      case 'battery':
        return Icons.battery_charging_full_rounded;
      case 'wont_start':
        return Icons.power_settings_new_rounded;
      case 'brake_clutch_chain':
        return Icons.settings_suggest_rounded;
      default:
        return Icons.handyman_rounded;
    }
  }

  static IconData _iconForVehicle(String id) {
    switch (id) {
      case 'bike':
        return Icons.two_wheeler_rounded;
      case 'scooter':
        return Icons.electric_moped_rounded;
      case 'auto':
        return Icons.electric_rickshaw_rounded;
      case 'car':
        return Icons.directions_car_filled_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.commute_rounded;
    }
  }
}

class _StepBadge extends StatelessWidget {
  final String number;
  const _StepBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SpeedyPalette.primary,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        number,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _RatingPromptCard extends StatefulWidget {
  final Booking booking;
  final Future<void> Function(int stars, String? comment) onRated;
  final VoidCallback onDismiss;

  const _RatingPromptCard({
    required this.booking,
    required this.onRated,
    required this.onDismiss,
  });

  @override
  State<_RatingPromptCard> createState() => _RatingPromptCardState();
}

class _RatingPromptCardState extends State<_RatingPromptCard> {
  int _stars = 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: const Color(0xFFF0FDF4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: SpeedyPalette.successTeal, width: 1.4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Job ${widget.booking.code} Completed!',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              Text(
                'Rate ${widget.booking.partner?.shopName ?? 'your mechanic'} (${formatRupeesFromPaise(widget.booking.totalPaise)} paid)',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starVal = index + 1;
                  return IconButton(
                    onPressed: () => setState(() => _stars = starVal),
                    icon: Icon(
                      starVal <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                      color: SpeedyPalette.accentAmber,
                      size: 32,
                    ),
                  );
                }),
              ),
              TextField(
                controller: _commentCtrl,
                decoration: const InputDecoration(
                  hintText: 'Quick feedback (optional)',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        setState(() => _submitting = true);
                        await widget.onRated(_stars, _commentCtrl.text);
                      },
                child: const Text('Submit Rating'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom vector road & live GPS radar map painter so the map canvas looks crisp
/// even before a billing-enabled Google Maps tile key is configured.
class _RoadRadarMapPainter extends CustomPainter {
  final double customerLat;
  final double customerLng;
  final double? partnerLat;
  final double? partnerLng;
  final bool isSearching;

  const _RoadRadarMapPainter({
    required this.customerLat,
    required this.customerLng,
    required this.partnerLat,
    required this.partnerLng,
    required this.isSearching,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFE8EEF5);
    canvas.drawRect(Offset.zero & size, bg);

    // Subtle grid & road network lines
    final gridPaint = Paint()
      ..color = const Color(0xFFD5E0EC)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height * 0.65),
      Offset(size.width, size.height * 0.32),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.28, 0),
      Offset(size.width * 0.68, size.height),
      roadPaint,
    );

    final custCenter = Offset(size.width * 0.48, size.height * 0.54);

    // Radar concentric rings
    final ringPaint = Paint()
      ..color = (isSearching ? SpeedyPalette.accentAmber : SpeedyPalette.primary)
          .withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(custCenter, 48, ringPaint);
    canvas.drawCircle(custCenter, 26, ringPaint);

    // If partner location is available, draw route line and mechanic pin
    if (partnerLat != null && partnerLng != null) {
      final dx = ((partnerLng! - customerLng) * 4500).clamp(-120.0, 120.0);
      final dy = ((customerLat - partnerLat!) * 4500).clamp(-60.0, 60.0);
      final mechPos = Offset(
        (custCenter.dx + dx).clamp(32.0, size.width - 32.0),
        (custCenter.dy + dy).clamp(32.0, size.height - 32.0),
      );

      final routePaint = Paint()
        ..color = SpeedyPalette.primary
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(custCenter, mechPos, routePaint);

      final mechBg = Paint()..color = SpeedyPalette.primaryDark;
      canvas.drawCircle(mechPos, 11, mechBg);
      final mechDot = Paint()..color = Colors.white;
      canvas.drawCircle(mechPos, 4.5, mechDot);
    }

    // Customer GPS pin
    final pinHalo = Paint()..color = Colors.white;
    canvas.drawCircle(custCenter, 11, pinHalo);
    final pinCore = Paint()..color = SpeedyPalette.primary;
    canvas.drawCircle(custCenter, 7.5, pinCore);
  }

  @override
  bool shouldRepaint(covariant _RoadRadarMapPainter oldDelegate) =>
      oldDelegate.customerLat != customerLat ||
      oldDelegate.customerLng != customerLng ||
      oldDelegate.partnerLat != partnerLat ||
      oldDelegate.partnerLng != partnerLng ||
      oldDelegate.isSearching != isSearching;
}
