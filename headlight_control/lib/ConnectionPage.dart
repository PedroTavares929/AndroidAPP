import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ControlPage.dart';

class ConnectionPage extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  ConnectionPage({required this.isDarkMode, required this.onThemeChanged});

  @override
  _ConnectionPageState createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> with TickerProviderStateMixin {
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool isConnected = false;
  String statusMessage = "Ready to connect";
  
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _rotationController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  Future<void> connectToDevice() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Scanning for devices...";
    });

    _rotationController.repeat();

    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      
      BluetoothDevice? targetDevice;
      for (BluetoothDevice device in devices) {
        if (device.name != null && device.name == "HeadlightController") {
          targetDevice = device;
          break;
        }
      }

      if (targetDevice == null) {
        setState(() {
          statusMessage = "HeadlightController not found. Please pair the device first.";
          isConnecting = false;
        });
        _rotationController.stop();
        return;
      }

      setState(() {
        statusMessage = "Connecting to ${targetDevice?.name ?? 'HeadlightController'}...";
      });

      BluetoothConnection conn = await BluetoothConnection.toAddress(targetDevice.address);
      
      setState(() {
        connection = conn;
        isConnected = true;
        isConnecting = false;
        statusMessage = "Connected successfully!";
      });

      _rotationController.stop();
      _rotationController.reset();

      // Navigate to Control Page
      await Future.delayed(Duration(milliseconds: 500));
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => ControlPage(
            connection: conn,
            isDarkMode: widget.isDarkMode,
            onThemeChanged: widget.onThemeChanged,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: animation.drive(
                Tween(begin: Offset(1.0, 0.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOut)),
              ),
              child: child,
            );
          },
          transitionDuration: Duration(milliseconds: 300),
        ),
      );

    } catch (e) {
      setState(() {
        statusMessage = "Connection failed: ${e.toString().split(':').last.trim()}";
        isConnecting = false;
      });
      _rotationController.stop();
      _rotationController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isDarkMode 
                ? [
                    Color(0xFF0F0F23),
                    Color(0xFF1A1A2E), 
                    Color(0xFF16213E),
                    Color(0xFF0F3460)
                  ]
                : [
                    Color(0xFFE3F2FD),
                    Color(0xFFBBDEFB), 
                    Color(0xFF90CAF9),
                    Color(0xFF64B5F6)
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 60 : 24,
              vertical: 20,
            ),
            child: Column(
              children: [
                // Header
                _buildHeader(isTablet),
                
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: _buildConnectionCard(isTablet),
                    ),
                  ),
                ),
                
                // Footer
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isTablet ? 16 : 12),
            decoration: BoxDecoration(
              color: widget.isDarkMode 
                ? Colors.orange.withOpacity(0.2) 
                : Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.directions_car_rounded,
              color: widget.isDarkMode ? Colors.orange : Colors.blue,
              size: isTablet ? 32 : 24,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUDI A4 B6',
                  style: TextStyle(
                    fontSize: isTablet ? 28 : 24,
                    fontWeight: FontWeight.bold,
                    color: widget.isDarkMode ? Colors.white : Colors.black87,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'Headlight Controller',
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => widget.onThemeChanged(!widget.isDarkMode),
            child: Container(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              decoration: BoxDecoration(
                color: widget.isDarkMode 
                  ? Colors.orange.withOpacity(0.2) 
                  : Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.isDarkMode ? Colors.orange : Colors.blue,
                  width: 2,
                ),
              ),
              child: Icon(
                widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                size: isTablet ? 28 : 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(bool isTablet) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: isTablet ? 500 : double.infinity,
      ),
      margin: EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: widget.isDarkMode 
          ? Color(0xFF1A1A2E).withOpacity(0.9) 
          : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: widget.isDarkMode 
              ? Colors.black.withOpacity(0.3) 
              : Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: Offset(0, 15),
            spreadRadius: 5,
          ),
        ],
        border: Border.all(
          color: widget.isDarkMode 
            ? Colors.orange.withOpacity(0.3) 
            : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: EdgeInsets.all(isTablet ? 50 : 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Bluetooth Icon
              _buildAnimatedIcon(isTablet),
              
              SizedBox(height: isTablet ? 40 : 30),
              
              // Title
              Text(
                'ESP32 CONTROLLER',
                style: TextStyle(
                  fontSize: isTablet ? 26 : 22,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode ? Colors.orange : Colors.blue,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: isTablet ? 30 : 20),
              
              // Status Container
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 30 : 20,
                  vertical: isTablet ? 20 : 15,
                ),
                decoration: BoxDecoration(
                  color: widget.isDarkMode 
                    ? Color(0xFF0F0F23).withOpacity(0.7) 
                    : Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isDarkMode 
                      ? Colors.orange.withOpacity(0.2) 
                      : Colors.blue.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getStatusIcon(),
                      color: _getStatusColor(),
                      size: isTablet ? 24 : 20,
                    ),
                    SizedBox(height: 8),
                    Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: isTablet ? 16 : 14,
                        color: widget.isDarkMode ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: isTablet ? 40 : 30),
              
              // Connect Button
              _buildConnectButton(isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon(bool isTablet) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isConnecting ? _pulseAnimation.value : 1.0,
          child: AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: isConnecting ? _rotationController.value * 6.28 : 0,
                child: Container(
                  width: isTablet ? 120 : 100,
                  height: isTablet ? 120 : 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: widget.isDarkMode
                          ? [
                              Colors.orange.shade400,
                              Colors.deepOrange.shade600,
                              Colors.orange.shade800,
                            ]
                          : [
                              Colors.blue.shade400,
                              Colors.cyan.shade600,
                              Colors.blue.shade800,
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isDarkMode ? Colors.orange : Colors.blue)
                            .withOpacity(0.4),
                        blurRadius: 25,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    isConnected 
                        ? Icons.bluetooth_connected_rounded
                        : isConnecting 
                            ? Icons.bluetooth_searching_rounded
                            : Icons.bluetooth_rounded,
                    size: isTablet ? 60 : 50,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildConnectButton(bool isTablet) {
    return Container(
      width: double.infinity,
      height: isTablet ? 70 : 60,
      child: ElevatedButton(
        onPressed: isConnecting ? null : connectToDevice,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.isDarkMode ? Colors.orange : Colors.blue,
          foregroundColor: Colors.white,
          elevation: 15,
          shadowColor: (widget.isDarkMode ? Colors.orange : Colors.blue).withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          disabledBackgroundColor: Colors.grey.shade400,
        ),
        child: isConnecting
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: isTablet ? 24 : 20,
                    height: isTablet ? 24 : 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'CONNECTING...',
                    style: TextStyle(
                      fontSize: isTablet ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_connected_rounded,
                    size: isTablet ? 28 : 24,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'CONNECT TO ESP32',
                    style: TextStyle(
                      fontSize: isTablet ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'Make sure your device is paired with "HeadlightController"',
        style: TextStyle(
          fontSize: 12,
          color: widget.isDarkMode ? Colors.white54 : Colors.black54,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  IconData _getStatusIcon() {
    if (isConnected) return Icons.check_circle_rounded;
    if (isConnecting) return Icons.hourglass_empty_rounded;
    return Icons.info_outline_rounded;
  }

  Color _getStatusColor() {
    if (isConnected) return Colors.green;
    if (isConnecting) return Colors.orange;
    return widget.isDarkMode ? Colors.white70 : Colors.black54;
  }
}