import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const PitMedApp());
}

class PitMedApp extends StatelessWidget {
  const PitMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PitMed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          primary: const Color(0xFF3F51B5),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
