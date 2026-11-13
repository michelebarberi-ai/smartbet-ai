import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smartbet_ai_new/screens/home_screen.dart';
import 'package:smartbet_ai_new/screens/goalvdline_auto_coupon_today_screen.dart';
import 'package:smartbet_ai_new/screens/goalvdline_requested_coupon_ready_screen.dart';
import 'package:smartbet_ai_new/theme/app_theme.dart';

/// B45 P14: notification taps open an authenticated, read-only coupon screen.
class SmartBetApp extends StatefulWidget {
  const SmartBetApp({super.key});

  @override
  State<SmartBetApp> createState() => _SmartBetAppState();
}

class _SmartBetAppState extends State<SmartBetApp> {
  static const _channel = MethodChannel('goalvdline/push_registration');
  static final _dayKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  final _navigator = GlobalKey<NavigatorState>();
  bool _couponOpen = false;
  bool _onDemandCouponOpen = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onNativeCall);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readInitialTap());
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'autoCouponOpened' && call.arguments is String) {
      _openCoupon(call.arguments as String);
    } else if (call.method == 'onDemandCouponOpened') {
      _openRequestedCoupon();
    }
  }

  Future<void> _readInitialTap() async {
    try {
      final day = await _channel.invokeMethod<String>(
        'consumePendingAutoCouponDay',
      );
      if (mounted && day != null) _openCoupon(day);
      final requested = await _channel.invokeMethod<bool>(
        'consumePendingOnDemandCouponTap',
      );
      if (mounted && requested == true) _openRequestedCoupon();
    } on MissingPluginException {
      // Android, desktop and widget tests have no native APNs handler.
    } on PlatformException {
      // Push failures must never interrupt app startup.
    }
  }

  void _openCoupon(String day) {
    if (!mounted || !_dayKey.hasMatch(day) || _couponOpen) return;
    final nav = _navigator.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCoupon(day));
      return;
    }
    _couponOpen = true;
    nav
        .push<void>(
          MaterialPageRoute(
            builder: (_) => const GoalVdLineAutoCouponTodayScreen(),
          ),
        )
        .whenComplete(() => _couponOpen = false);
  }

  void _openRequestedCoupon() {
    if (!mounted || _onDemandCouponOpen) return;
    final nav = _navigator.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedCoupon());
      return;
    }
    _onDemandCouponOpen = true;
    nav.push<void>(
      MaterialPageRoute(
        builder: (_) => const GoalVdLineRequestedCouponReadyScreen(),
      ),
    ).whenComplete(() => _onDemandCouponOpen = false);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: 'GoalVdLine AI',
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
