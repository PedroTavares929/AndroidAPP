// lib/main.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/scheduler.dart'; // Import for SchedulerBinding

// Import your page files here
import 'ConnectionPage.dart';
import 'ControlPage.dart';
import 'theme_constants.dart'; // Import the new file

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations for better tablet support
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(HeadlightControllerApp());
}

class HeadlightControllerApp extends StatefulWidget {
  @override
  _HeadlightControllerAppState createState() => _HeadlightControllerAppState();
}

class _HeadlightControllerAppState extends State<HeadlightControllerApp> {
  AppThemeMode _currentThemeMode = AppThemeMode.dark; // Default to dark mode for better appearance

  // Keep track of the actual effective brightness for the child pages
  bool _isSystemDarkMode = false; // Initial value, will be updated in initState

  @override
  void initState() {
    super.initState();
    // Get initial system brightness
    _isSystemDarkMode = SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

    // Listen for platform brightness changes
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      setState(() {
        _isSystemDarkMode = SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
      });
    };
  }


  @override
  Widget build(BuildContext context) {
    // Determine the effective isDarkMode for child widgets based on _currentThemeMode
    bool effectiveIsDarkMode;
    if (_currentThemeMode == AppThemeMode.system) {
      effectiveIsDarkMode = _isSystemDarkMode;
    } else {
      effectiveIsDarkMode = _currentThemeMode == AppThemeMode.dark;
    }

    return MaterialApp(
      title: 'Audi Headlight Controller',
      debugShowCheckedModeBanner: false,

      // Light Theme
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Color(0xFFE3F2FD),
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: Colors.blue.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),

      // Dark Theme
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Color(0xFF0F0F23),
        fontFamily: 'Roboto',
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: Colors.orange.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),

      // This uses Flutter's built-in ThemeMode for system theme handling
      themeMode: _getMaterialThemeMode(_currentThemeMode),

      home: ConnectionPage(
        isDarkMode: effectiveIsDarkMode, // Pass the effective dark mode status
        themeMode: _currentThemeMode, // Pass the selected theme mode
        onThemeChanged: (newThemeMode) {
          setState(() {
            _currentThemeMode = newThemeMode;
          });
        },
      ),
    );
  }

  // Helper to convert our custom AppThemeMode to Flutter's ThemeMode
  ThemeMode _getMaterialThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}