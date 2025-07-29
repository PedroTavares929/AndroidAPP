// lib/ControlPage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'ConnectionPage.dart';
import 'theme_constants.dart'; // Import the new file

class ControlPage extends StatefulWidget {
  final BluetoothConnection connection;
  final bool isDarkMode;
  final AppThemeMode themeMode; // Use the shared enum
  final Function(AppThemeMode) onThemeChanged;

  ControlPage({
    required this.connection,
    required this.isDarkMode,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  _ControlPageState createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with TickerProviderStateMixin {
  // Motor status
  int leftPosition = 0;
  int rightPosition = 0;
  bool headlightsOn = false;
  bool motorsEnabled = false;
  bool isAnimating = false;
  bool isConnected = true;
  String lastError = "";
  bool leftMoving = false;
  bool rightMoving = false;

  // Configuration
  int leftDefaultPosition = 200;
  int rightDefaultPosition = 200;
  int animationSpeed = 3;
  int motorTimeout = 3000;
  int maxPosition = 320;
  int minPosition = 0;
  int stepSize = 20;

  // CAN status
  bool canInitialized = false;
  int frameCount = 0;

  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  Timer? _statusTimer;
  bool _isDisposed = false;
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();

    _breathingController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _breathingAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));

    // Listen for incoming data
    _dataSubscription = widget.connection.input!.listen(
      _onDataReceived,
      onError: (error) {
        if (!_isDisposed && mounted) {
          setState(() {
            isConnected = false;
            lastError = "Connection lost: $error";
          });
          _stopStatusTimer();
        }
      },
      onDone: () {
        _stopStatusTimer();
        if (!_isDisposed && mounted) {
          _navigateToConnection();
        }
      },
    );

    // Request initial status and config
    _sendCommand({"action": "status"});
    _sendCommand({"action": "config_get"});

    // Start status updates
    _startStatusTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopStatusTimer();
    _dataSubscription?.cancel();
    _breathingController.dispose();
    super.dispose();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!_isDisposed && mounted && _canSendData()) {
        _sendCommand({"action": "status"});
      } else {
        timer.cancel();
      }
    });
  }

  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  bool _canSendData() {
    try {
      return widget.connection.isConnected && isConnected && !_isDisposed;
    } catch (e) {
      return false;
    }
  }

  void _onDataReceived(Uint8List data) {
    if (_isDisposed || !mounted) return;

    try {
      String message = String.fromCharCodes(data).trim();
      if (message.isEmpty) return;

      List<String> jsonLines = message.split('\n').where((line) => line.trim().isNotEmpty).toList();

      for (String jsonLine in jsonLines) {
        try {
          Map<String, dynamic> json = jsonDecode(jsonLine);

          if (json['type'] == 'status') {
            setState(() {
              leftPosition = json['leftPosition'] ?? 0;
              rightPosition = json['rightPosition'] ?? 0;
              headlightsOn = json['headlightsOn'] ?? false;
              motorsEnabled = json['motorsEnabled'] ?? false;
              isAnimating = json['isAnimating'] ?? false;
              leftMoving = json['leftMoving'] ?? false;
              rightMoving = json['rightMoving'] ?? false;
              canInitialized = json['canInitialized'] ?? false;
              frameCount = json['frameCount'] ?? 0;

              isConnected = true;
              lastError = "";
            });
          }
          else if (json['type'] == 'config') {
            setState(() {
              leftDefaultPosition = json['left_default'] ?? 200;
              rightDefaultPosition = json['right_default'] ?? 200;
              animationSpeed = json['animation_speed'] ?? 3;
              motorTimeout = json['motor_timeout'] ?? 3000;
              maxPosition = json['max_position'] ?? 320;
              minPosition = json['min_position'] ?? 0;
            });
          }
          else if (json['type'] == 'success') {
            // Success message received - no notification shown
            print("Success: ${json['message'] ?? 'Success'}");
          }
          else if (json['type'] == 'error') {
            setState(() {
              lastError = json['message'] ?? 'Unknown error';
            });
          }
        } catch (e) {
          // Ignore JSON parsing errors for individual lines
        }
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          lastError = "Data error: $e";
        });
      }
    }
  }

  Future<void> _sendCommand(Map<String, dynamic> command) async {
    if (_isDisposed || !mounted || !_canSendData()) return;

    try {
      String jsonString = jsonEncode(command);
      widget.connection.output.add(Uint8List.fromList(utf8.encode(jsonString + '\n')));
      await widget.connection.output.allSent;

      if (!isConnected && !_isDisposed && mounted) {
        setState(() {
          isConnected = true;
          lastError = "";
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() {
          isConnected = false;
          lastError = "Send failed";
        });
        _stopStatusTimer();
      }
    }
  }

  Future<void> _disconnect() async {
    _isDisposed = true;
    _stopStatusTimer();

    try {
      await widget.connection.close();
    } catch (e) {
      // Ignore disconnect errors
    }

    if (mounted) {
      _navigateToConnection();
    }
  }

  void _navigateToConnection() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ConnectionPage(
          isDarkMode: widget.isDarkMode,
          themeMode: widget.themeMode, // Use the shared enum
          onThemeChanged: widget.onThemeChanged, // Use the shared enum
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: Offset(-1.0, 0.0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeInOut)),
            ),
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  void _showConfigDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        int tempLeftDefault = leftDefaultPosition;
        int tempRightDefault = rightDefaultPosition;
        int tempAnimSpeed = animationSpeed;
        int tempMotorTimeout = motorTimeout;
        int tempStepSize = stepSize;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: widget.isDarkMode ? Color(0xFF1A1A2E) : Colors.white,
              title: Text(
                'Motor Configuration',
                style: TextStyle(
                  color: widget.isDarkMode ? Colors.orange : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Left Default Position
                    Text(
                      'Left Default Position: $tempLeftDefault',
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Where left motor goes after animation & center button',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Slider(
                      value: tempLeftDefault.toDouble(),
                      min: 0,
                      max: 320,
                      divisions: 32,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setDialogState(() {
                          tempLeftDefault = value.round();
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Right Default Position
                    Text(
                      'Right Default Position: $tempRightDefault',
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Where right motor goes after animation & center button',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Slider(
                      value: tempRightDefault.toDouble(),
                      min: 0,
                      max: 320,
                      divisions: 32,
                      activeColor: Colors.green,
                      onChanged: (value) {
                        setDialogState(() {
                          tempRightDefault = value.round();
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Step Size: $tempStepSize steps',
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'How many steps UP/DOWN buttons move (1-50 steps)',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Slider(
                      value: tempStepSize.toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      activeColor: Colors.cyan,
                      onChanged: (value) {
                        setDialogState(() {
                          tempStepSize = value.round();
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Animation Speed
                    Text(
                      'Animation Speed: $tempAnimSpeed ms',
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: tempAnimSpeed.toDouble(),
                      min: 1,
                      max: 20,
                      divisions: 19,
                      activeColor: Colors.orange,
                      onChanged: (value) {
                        setDialogState(() {
                          tempAnimSpeed = value.round();
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Motor Timeout
                    Text(
                      'Motor Timeout: ${(tempMotorTimeout / 1000).toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: widget.isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: tempMotorTimeout.toDouble(),
                      min: 1000,
                      max: 10000,
                      divisions: 18,
                      activeColor: Colors.purple,
                      onChanged: (value) {
                        setDialogState(() {
                          tempMotorTimeout = value.round();
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _sendCommand({
                      "action": "config_set",
                      "left_default": tempLeftDefault,
                      "right_default": tempRightDefault,
                      "animation_speed": tempAnimSpeed,
                      "motor_timeout": tempMotorTimeout,
                    });

                    setState(() {
                      leftDefaultPosition = tempLeftDefault;
                      rightDefaultPosition = tempRightDefault;
                      animationSpeed = tempAnimSpeed;
                      motorTimeout = tempMotorTimeout;
                      stepSize = tempStepSize;
                    });

                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDarkMode ? Colors.orange : Colors.blue,
                  ),
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
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
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final isLandscape = screenWidth > screenHeight;

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
          child: Column(
            children: [
              _buildHeader(isTablet),
              Flexible(
                child: isLandscape && isTablet
                    ? _buildTabletLandscapeLayout()
                    : _buildVerticalLayout(isTablet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 30 : 20,
        vertical: isTablet ? 20 : 15,
      ),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF1A1A2E).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Disconnect Button
          GestureDetector(
            onTap: _disconnect,
            child: Container(
              padding: EdgeInsets.all(isTablet ? 14 : 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Icon(
                Icons.close_rounded,
                color: Colors.red,
                size: isTablet ? 24 : 20,
              ),
            ),
          ),

          SizedBox(width: 12),

          // Config Button
          GestureDetector(
            onTap: isConnected ? _showConfigDialog : null,
            child: Container(
              padding: EdgeInsets.all(isTablet ? 14 : 10),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.purple, width: 2),
              ),
              child: Icon(
                Icons.settings_rounded,
                color: Colors.purple,
                size: isTablet ? 24 : 20,
              ),
            ),
          ),

          SizedBox(width: 12),

          // Status Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _breathingAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: isConnected ? _breathingAnimation.value : 1.0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isConnected ? Colors.green : Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isConnected ? Colors.green : Colors.red)
                                      .withOpacity(0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isConnected ? 'CONNECTED' : 'DISCONNECTED',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
                          fontWeight: FontWeight.bold,
                          color: widget.isDarkMode ? Colors.white : Colors.black87,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (lastError.isNotEmpty)
                  Text(
                    lastError,
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10,
                      color: Colors.red,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Row(
                    children: [
                      Text(
                        'CAN: ${canInitialized ? "OK" : "FAIL"}',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 10,
                          color: canInitialized
                            ? Colors.green
                            : (widget.isDarkMode ? Colors.white54 : Colors.black54),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Frames: $frameCount',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 10,
                          color: widget.isDarkMode ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Theme Toggle
          GestureDetector(
            onTap: _showThemeDialog,
            child: Container(
              padding: EdgeInsets.all(isTablet ? 14 : 10),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
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
                size: isTablet ? 24 : 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalLayout(bool isTablet) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(isTablet ? 20 : 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (isTablet ? 40 : 32),
            ),
            child: Column(
              children: [
                _buildStatusCard(isTablet),
                SizedBox(height: isTablet ? 16 : 12),
                _buildControlsCard(isTablet),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabletLandscapeLayout() {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildStatusCard(true),
          ),
          SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: _buildControlsCard(true),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 24 : 20),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF1A1A2E).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: widget.isDarkMode
            ? Colors.orange.withOpacity(0.3)
            : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.dashboard_rounded,
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                size: isTablet ? 28 : 24,
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'MOTOR STATUS',
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDarkMode ? Colors.orange : Colors.blue,
                    letterSpacing: 2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          SizedBox(height: isTablet ? 24 : 20),

          // Motor Position Displays
          Row(
            children: [
              Expanded(
                child: _buildMotorDisplay(
                  'LEFT MOTOR',
                  leftPosition,
                  leftDefaultPosition,
                  leftMoving,
                  Colors.blue,
                  isTablet,
                ),
              ),
              SizedBox(width: isTablet ? 20 : 16),
              Expanded(
                child: _buildMotorDisplay(
                  'RIGHT MOTOR',
                  rightPosition,
                  rightDefaultPosition,
                  rightMoving,
                  Colors.green,
                  isTablet,
                ),
              ),
            ],
          ),

          SizedBox(height: isTablet ? 24 : 20),

          // System Status
          _buildSystemStatus(isTablet),
        ],
      ),
    );
  }

  Widget _buildMotorDisplay(String title, int position, int defaultPos, bool moving, Color color, bool isTablet) {
    double percentage = position / maxPosition.toDouble();

    return Container(
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF0F0F23).withOpacity(0.7)
          : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: moving ? color : color.withOpacity(0.3),
          width: moving ? 3 : 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1,
            ),
          ),

          SizedBox(height: isTablet ? 16 : 12),

          // Circular Progress
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: isTablet ? 100 : 80,
                height: isTablet ? 100 : 80,
                child: CircularProgressIndicator(
                  value: percentage,
                  strokeWidth: isTablet ? 8 : 6,
                  backgroundColor: color.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$position',
                    style: TextStyle(
                      fontSize: isTablet ? 20 : 16,
                      fontWeight: FontWeight.bold,
                      color: widget.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '/ $maxPosition',
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10,
                      color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
              if (moving)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),

          SizedBox(height: isTablet ? 12 : 8),

          Text(
            'Center: $defaultPos',
            style: TextStyle(
              fontSize: isTablet ? 12 : 10,
              color: widget.isDarkMode ? Colors.white60 : Colors.black54,
            ),
          ),

          SizedBox(height: isTablet ? 8 : 6),

          Text(
            '${(percentage * 100).toInt()}%',
            style: TextStyle(
              fontSize: isTablet ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStatus(bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF0F0F23).withOpacity(0.7)
          : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isDarkMode
            ? Colors.orange.withOpacity(0.3)
            : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SYSTEM STATUS',
            style: TextStyle(
              fontSize: isTablet ? 18 : 16,
              fontWeight: FontWeight.bold,
              color: widget.isDarkMode ? Colors.orange : Colors.blue,
              letterSpacing: 1,
            ),
          ),

          SizedBox(height: isTablet ? 12 : 8),

          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 8,
            children: [
              _buildStatusIndicator(
                'Headlights',
                headlightsOn,
                Icons.lightbulb_rounded,
                isTablet,
              ),
              _buildStatusIndicator(
                'Motors',
                motorsEnabled,
                Icons.settings_rounded,
                isTablet,
              ),
              _buildStatusIndicator(
                'Animation',
                isAnimating,
                Icons.auto_awesome_rounded,
                isTablet,
              ),
              _buildStatusIndicator(
                'CAN Bus',
                canInitialized,
                Icons.cable_rounded,
                isTablet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool status, IconData icon, bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(isTablet ? 10 : 8),
          decoration: BoxDecoration(
            color: status
              ? Colors.green.withOpacity(0.2)
              : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: status ? Colors.green : Colors.grey,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            color: status ? Colors.green : Colors.grey,
            size: isTablet ? 20 : 16,
          ),
        ),
        SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: isTablet ? 10 : 8,
            fontWeight: FontWeight.bold,
            color: status
              ? Colors.green
              : (widget.isDarkMode ? Colors.white60 : Colors.black54),
          ),
        ),
        Text(
          status ? 'ON' : 'OFF',
          style: TextStyle(
            fontSize: isTablet ? 8 : 6,
            color: status
              ? Colors.green
              : (widget.isDarkMode ? Colors.white38 : Colors.black38),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsCard(bool isTablet) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 24 : 20),
      decoration: BoxDecoration(
        color: widget.isDarkMode
          ? Color(0xFF1A1A2E).withOpacity(0.9)
          : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: widget.isDarkMode
            ? Colors.orange.withOpacity(0.3)
            : Colors.blue.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.gamepad_rounded,
                color: widget.isDarkMode ? Colors.orange : Colors.blue,
                size: isTablet ? 28 : 24,
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'MOTOR CONTROLS',
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDarkMode ? Colors.orange : Colors.blue,
                    letterSpacing: 2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          SizedBox(height: isTablet ? 20 : 16),

          // Quick Actions
          _buildQuickActions(isTablet),

          SizedBox(height: isTablet ? 16 : 12),

          // Independent Controls
          _buildIndependentControls(isTablet),

          SizedBox(height: isTablet ? 16 : 12),

          // Position Controls
          _buildPositionControls(isTablet),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                title: 'ANIMATE',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => _sendCommand({"action": "animate"}),
                color: Colors.orange,
                isTablet: isTablet,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildControlButton(
                title: 'CENTER',
                icon: Icons.center_focus_strong_rounded,
                onPressed: () => _sendCommand({"action": "center"}),
                color: Colors.green,
                isTablet: isTablet,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        _buildControlButton(
          title: 'CONFIG',
          icon: Icons.settings_rounded,
          onPressed: _showConfigDialog,
          color: Colors.purple,
          isTablet: isTablet,
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildIndependentControls(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'INDEPENDENT CONTROLS',
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    'LEFT MOTOR',
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildControlButton(
                          title: 'UP',
                          icon: Icons.keyboard_arrow_up,
                          onPressed: () => _sendCommand({"action": "move_left", "steps": stepSize}),
                          color: Colors.blue,
                          isTablet: isTablet,
                          compact: true,
                        ),
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: _buildControlButton(
                          title: 'DOWN',
                          icon: Icons.keyboard_arrow_down,
                          onPressed: () => _sendCommand({"action": "move_left", "steps": -stepSize}),
                          color: Colors.blue,
                          isTablet: isTablet,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'RIGHT MOTOR',
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildControlButton(
                          title: 'UP',
                          icon: Icons.keyboard_arrow_up,
                          onPressed: () => _sendCommand({"action": "move_right", "steps": stepSize}),
                          color: Colors.green,
                          isTablet: isTablet,
                          compact: true,
                        ),
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: _buildControlButton(
                          title: 'DOWN',
                          icon: Icons.keyboard_arrow_down,
                          onPressed: () => _sendCommand({"action": "move_right", "steps": -stepSize}),
                          color: Colors.green,
                          isTablet: isTablet,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPositionControls(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'POSITION CONTROLS',
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8),
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                title: 'MAX UP',
                icon: Icons.keyboard_double_arrow_up_rounded,
                onPressed: () => _sendCommand({"action": "max_up"}),
                color: Colors.red,
                isTablet: isTablet,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _buildControlButton(
                title: 'MAX DOWN',
                icon: Icons.keyboard_double_arrow_down_rounded,
                onPressed: () => _sendCommand({"action": "max_down"}),
                color: Colors.red,
                isTablet: isTablet,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        _buildControlButton(
          title: 'MOVE BOTH UP',
          icon: Icons.arrow_upward_rounded,
          onPressed: () => _sendCommand({"action": "move_both", "steps": stepSize}),
          color: Colors.indigo,
          isTablet: isTablet,
          isFullWidth: true,
        ),
        SizedBox(height: 8),
        _buildControlButton(
          title: 'MOVE BOTH DOWN',
          icon: Icons.arrow_downward_rounded,
          onPressed: () => _sendCommand({"action": "move_both", "steps": -stepSize}),
          color: Colors.indigo,
          isTablet: isTablet,
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    required bool isTablet,
    bool isFullWidth = false,
    bool compact = false,
  }) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      height: compact ? (isTablet ? 35 : 30) : (isTablet ? 50 : 45),
      child: ElevatedButton(
        onPressed: (isConnected && !_isDisposed) ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          disabledBackgroundColor: Colors.grey.shade400,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        ),
        child: Row(
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: compact ? (isTablet ? 16 : 14) : (isTablet ? 20 : 16)),
            if (!compact) SizedBox(width: 6),
            if (!compact)
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isTablet ? 14 : 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}