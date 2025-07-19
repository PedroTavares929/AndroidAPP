// lib/ConnectionPage.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ControlPage.dart';
import 'theme_constants.dart'; // Import the new file

class ConnectionPage extends StatefulWidget {
  final bool isDarkMode;
  final AppThemeMode themeMode; // Use the shared enum
  final Function(AppThemeMode) onThemeChanged;

  ConnectionPage({
    required this.isDarkMode,
    required this.themeMode,
    required this.onThemeChanged
  });

  @override
  _ConnectionPageState createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> with TickerProviderStateMixin {
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool isConnected = false;
  String statusMessage = "Ready to connect";
  List<BluetoothDevice> availableDevices = [];
  BluetoothDevice? selectedDevice;
  int connectionAttempt = 0;

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
      duration: Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _scanForDevices();
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

  Future<void> _scanForDevices() async {
    try {
      setState(() {
        statusMessage = "Scanning for devices...";
      });

      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      setState(() {
        availableDevices = devices;

        // Try to find HeadlightController devices
        BluetoothDevice? targetDevice;
        for (BluetoothDevice device in devices) {
          if (device.name != null &&
              (device.name!.contains("Headlight") ||
               device.name == "HeadlightController")) {
            targetDevice = device;
            break;
          }
        }

        if (targetDevice != null) {
          selectedDevice = targetDevice;
          statusMessage = "Found: ${targetDevice.name}\nReady to connect!";
        } else {
          statusMessage = "Found ${devices.length} paired devices.\nSelect HeadlightController device.";
        }
      });

    } catch (e) {
      setState(() {
        statusMessage = "Scan failed: $e";
      });
    }
  }

  Future<void> connectToDevice([BluetoothDevice? device]) async {
    BluetoothDevice? targetDevice = device ?? selectedDevice;

    if (targetDevice == null) {
      setState(() {
        statusMessage = "No device selected!";
      });
      return;
    }

    connectionAttempt++;

    setState(() {
      isConnecting = true;
      statusMessage = "Connecting to ${targetDevice!.name}...\nAttempt $connectionAttempt";
    });

    _rotationController.repeat();

    try {
      // Close any existing connection first
      try {
        await connection?.close();
      } catch (e) {
        // Ignore errors when closing
      }

      // Add a small delay to ensure previous connection is closed
      await Future.delayed(Duration(milliseconds: 500));

      BluetoothConnection conn = await BluetoothConnection.toAddress(targetDevice.address);

      setState(() {
        connection = conn;
        isConnected = true;
        isConnecting = false;
        statusMessage = "Connected successfully!\nTesting communication...";
        connectionAttempt = 0; // Reset on success
      });

      _rotationController.stop();
      _rotationController.reset();

      // Test communication with retry
      await _testConnectionWithRetry(conn);

    } catch (e) {
      setState(() {
        statusMessage = "Connection failed (attempt $connectionAttempt):\n${e.toString()}";
        isConnecting = false;
      });
      _rotationController.stop();
      _rotationController.reset();

      // Auto retry up to 3 times for common errors
      if (connectionAttempt < 3 && (e.toString().contains('socket') || e.toString().contains('timeout'))) {
        await Future.delayed(Duration(milliseconds: 1000));
        connectToDevice(targetDevice);
      }
    }
  }

  Future<void> _testConnectionWithRetry(BluetoothConnection conn) async {
    int testAttempts = 0;
    bool testSuccessful = false;

    while (testAttempts < 3 && !testSuccessful) {
      try {
        testAttempts++;

        // Send status request
        String testCommand = '{"action": "status"}\n';
        conn.output.add(Uint8List.fromList(utf8.encode(testCommand)));
        await conn.output.allSent;

        // Wait for response
        await Future.delayed(Duration(milliseconds: 1000));

        setState(() {
          statusMessage = "Connection test successful!\nNavigating to controls...";
        });

        testSuccessful = true;

      } catch (e) {
        if (testAttempts >= 3) {
          setState(() {
            statusMessage = "Connection established but test failed.\nProceeding anyway...";
          });
          testSuccessful = true; // Proceed anyway
        } else {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
    }

    // Navigate to Control Page
    await Future.delayed(Duration(milliseconds: 500));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => ControlPage(
            connection: conn,
            isDarkMode: widget.isDarkMode,
            themeMode: widget.themeMode, // Use the shared enum
            onThemeChanged: widget.onThemeChanged, // Use the shared enum
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
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: widget.isDarkMode ? Color(0xFF1A1A2E) : Colors.white,
          title: Text(
            'Theme Settings',
            style: TextStyle(
              color: widget.isDarkMode ? Colors.orange : Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThemeOption(
                title: 'System Default',
                subtitle: 'Follow phone settings',
                icon: Icons.phone_android,
                isSelected: widget.themeMode == AppThemeMode.system,
                onTap: () {
                  widget.onThemeChanged(AppThemeMode.system);
                  Navigator.pop(context);
                },
              ),
              SizedBox(height: 12),
              _buildThemeOption(
                title: 'Light Mode',
                subtitle: 'Always light theme',
                icon: Icons.light_mode,
                isSelected: widget.themeMode == AppThemeMode.light,
                onTap: () {
                  widget.onThemeChanged(AppThemeMode.light);
                  Navigator.pop(context);
                },
              ),
              SizedBox(height: 12),
              _buildThemeOption(
                title: 'Dark Mode',
                subtitle: 'Always dark theme',
                icon: Icons.dark_mode,
                isSelected: widget.themeMode == AppThemeMode.dark,
                onTap: () {
                  widget.onThemeChanged(AppThemeMode.dark);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(
                  color: widget.isDarkMode ? Colors.orange : Colors.blue,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
            ? (widget.isDarkMode ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.2))
            : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
              ? (widget.isDarkMode ? Colors.orange : Colors.blue)
              : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                ? (widget.isDarkMode ? Colors.orange : Colors.blue)
                : Colors.grey,
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: widget.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                size: 20,
              ),
          ],
        ),
      ),
    );
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
                _buildHeader(isTablet),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildConnectionCard(isTablet),
                        SizedBox(height: 20),
                        _buildDevicesList(isTablet),
                      ],
                    ),
                  ),
                ),
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
          Row(
            children: [
              // Refresh button
              GestureDetector(
                onTap: _scanForDevices,
                child: Container(
                  padding: EdgeInsets.all(isTablet ? 16 : 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: Colors.green,
                    size: isTablet ? 28 : 20,
                  ),
                ),
              ),
              SizedBox(width: 12),
              // Theme toggle
              GestureDetector(
                onTap: _showThemeDialog,
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
                    widget.themeMode == AppThemeMode.system
                      ? Icons.phone_android
                      : (widget.isDarkMode ? Icons.dark_mode : Icons.light_mode),
                    color: widget.isDarkMode ? Colors.orange : Colors.blue,
                    size: isTablet ? 28 : 20,
                  ),
                ),
              ),
            ],
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
              _buildAnimatedIcon(isTablet),
              SizedBox(height: isTablet ? 40 : 30),

              Text(
                'HEADLIGHT CONTROL',
                style: TextStyle(
                  fontSize: isTablet ? 24 : 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode ? Colors.orange : Colors.blue,
                  letterSpacing: 2,
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
                        fontSize: isTablet ? 14 : 12,
                        color: widget.isDarkMode ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              SizedBox(height: isTablet ? 30 : 20),

              if (selectedDevice != null) ...[
                // Selected Device Info
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isTablet ? 20 : 16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.bluetooth_connected, color: Colors.green, size: isTablet ? 24 : 20),
                      SizedBox(height: 8),
                      Text(
                        selectedDevice!.name ?? 'Unknown Device',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        selectedDevice!.address,
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 10,
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isTablet ? 20 : 16),
              ],

              // Connect Button
              _buildConnectButton(isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesList(bool isTablet) {
    if (availableDevices.isEmpty) {
      return Container();
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: isTablet ? 500 : double.infinity,
      ),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF1A1A2E).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isDarkMode
            ? Colors.orange.withOpacity(0.3)
            : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            child: Text(
              'AVAILABLE DEVICES (${availableDevices.length})',
              style: TextStyle(
                fontSize: isTablet ? 18 : 16,
                fontWeight: FontWeight.bold,
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                letterSpacing: 1,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: availableDevices.length,
            itemBuilder: (context, index) {
              BluetoothDevice device = availableDevices[index];
              bool isSelected = selectedDevice?.address == device.address;
              bool isHeadlightDevice = device.name != null && device.name!.contains("Headlight");

              return Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                    ? Colors.green.withOpacity(0.2)
                    : (isHeadlightDevice
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                      ? Colors.green
                      : (isHeadlightDevice ? Colors.orange : Colors.grey.withOpacity(0.3)),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isHeadlightDevice
                      ? Icons.directions_car_rounded
                      : Icons.bluetooth_rounded,
                    color: isSelected
                      ? Colors.green
                      : (isHeadlightDevice ? Colors.orange : Colors.grey),
                    size: isTablet ? 24 : 20,
                  ),
                  title: Text(
                    device.name ?? 'Unknown Device',
                    style: TextStyle(
                      fontSize: isTablet ? 16 : 14,
                      fontWeight: isHeadlightDevice ? FontWeight.bold : FontWeight.normal,
                      color: widget.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    device.address,
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10,
                      color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                      fontFamily: 'monospace',
                    ),
                  ),
                  trailing: isSelected
                    ? Icon(Icons.check_circle, color: Colors.green)
                    : null,
                  onTap: () {
                    setState(() {
                      selectedDevice = device;
                      connectionAttempt = 0; // Reset attempts when selecting new device
                      statusMessage = "Selected: ${device.name}\nReady to connect!";
                    });
                  },
                ),
              );
            },
          ),
          SizedBox(height: 16),
        ],
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
                            : Icons.car_rental_rounded,
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
        onPressed: (isConnecting || selectedDevice == null) ? null : connectToDevice,
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
                    Icons.cable_rounded,
                    size: isTablet ? 28 : 24,
                  ),
                  SizedBox(width: 12),
                  Text(
                    selectedDevice != null ? 'CONNECT TO DEVICE' : 'SELECT A DEVICE',
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
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
      child: Column(
        children: [
          Text(
            connectionAttempt > 0 ? 'Connection attempts: $connectionAttempt/3' : 'Tap device to select, then connect',
            style: TextStyle(
              fontSize: 12,
              color: widget.isDarkMode ? Colors.white54 : Colors.black54,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 12,
                color: widget.isDarkMode ? Colors.orange.withOpacity(0.7) : Colors.blue.withOpacity(0.7),
              ),
              SizedBox(width: 4),
              Text(
                'Auto-retry on connection failures',
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isDarkMode ? Colors.orange.withOpacity(0.7) : Colors.blue.withOpacity(0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
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