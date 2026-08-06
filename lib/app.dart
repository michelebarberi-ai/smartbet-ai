import 'package:flutter/material.dart';
import 'package:smartbet_ai_new/screens/home_screen.dart';
import 'package:smartbet_ai_new/theme/app_theme.dart';

class SmartBetApp extends StatelessWidget {
  const SmartBetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartBet AI',
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
