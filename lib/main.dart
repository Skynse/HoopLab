import 'package:flutter/material.dart';

import 'package:hooplab/pages/method_selector.dart';

void main() {
  runApp(App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Blueprint theme - blue and white
        primaryColor: const Color(0xFF1565C0), // Deep blue
        scaffoldBackgroundColor: const Color(
          0xFFE3F2FD,
        ), // Light blue background
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF1565C0), // Deep blue
          secondary: const Color(0xFF0D47A1), // Darker blue
          surface: const Color(0xFFFFFFFF), // White
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: const Color(0xFF0D47A1), // Blue text
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: Color(0x331565C0)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            elevation: 2,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF1565C0),
          foregroundColor: Colors.white,
        ),
      ),
      home: const MethodSelector(),
    );
  }
}
