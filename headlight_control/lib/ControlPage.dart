import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'ConnectionPage.dart';

class ControlPage extends StatefulWidget {
  final BluetoothConnection connection;
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  ControlPage({
    required this.connection,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  _ControlPageState createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with TickerProviderStateMixin {
  int leftPosition = 0;
  int rightPosition = 0;
  bool headlightsOn = false;
  bool motorsEnabled = false;
  bool isAnimating = false;
  bool isConnected = true;
  String lastError = "";
  
  late AnimationController _breathingController;
  late AnimationController _progressController;
  late Animation<double> _breathingAnimation;
  
  // Auto status update timer
  Timer? _statusTimer;
  int _statusRequestCount = 0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    
    _breathingController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _progressController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    _breathingAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));
    
    // Listen for incoming data with better error handling
    widget.connection.input!.listen(
      _onDataReceived,
      onError: (error) {
        print("Connection error: $error");
        if (!_isDisposed && mounted) {
          setState(() {
            isConnected = false;
            lastError = "Connection lost: $error";
          });
          _stopStatusTimer(); // Stop timer immediately
        }
      },
      onDone: () {
        print("Connection closed by remote");
        _stopStatusTimer(); // Stop timer immediately
        if (!_isDisposed && mounted) {
          _navigateToConnection();
        }
      },
    );

    // Request initial status
    _sendCommand({"action": "status"});
    
    // Start automatic status updates every 1 second
    _startStatusTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopStatusTimer(); // Stop timer before disposing
    _breathingController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  // Check if connection is actually available before sending
  bool _canSendData() {
    try {
      return widget.connection.isConnected && isConnected && !_isDisposed;
    } catch (e) {
      print("Connection check failed: $e");
      return false;
    }
  }

  // Start automatic status request timer
  void _startStatusTimer() {
    _statusTimer?.cancel(); // Cancel any existing timer
    _statusTimer = Timer.periodic(Duration(milliseconds : 100), (timer) {
      if (!_isDisposed && mounted && _canSendData()) {
        _statusRequestCount++;
        print("Auto status request #$_statusRequestCount");
        _sendCommand({"action": "status"});
      } else {
        print("Timer stopped - disposed: $_isDisposed, mounted: $mounted, canSend: ${_canSendData()}");
        timer.cancel();
      }
    });
    print("✅ Auto status timer started (every 1 second)");
  }

  // Stop automatic status request timer
  void _stopStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = null;
    print("🛑 Auto status timer stopped");
  }

  void _onDataReceived(Uint8List data) {
    if (_isDisposed || !mounted) return;
    
    try {
      String message = String.fromCharCodes(data).trim();
      if (message.isEmpty) return;

      print("Received: $message"); // Debug print
      
      // Handle multiple JSON objects in one message
      List<String> jsonLines = message.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      for (String jsonLine in jsonLines) {
        try {
          Map<String, dynamic> json = jsonDecode(jsonLine);
          
          if (json['type'] == 'status') {
            setState(() {
              // Fix: Ensure we're getting the right values with null safety
              leftPosition = (json['leftPosition'] is int) ? json['leftPosition'] : 0;
              rightPosition = (json['rightPosition'] is int) ? json['rightPosition'] : 0;
              headlightsOn = (json['headlightsOn'] is bool) ? json['headlightsOn'] : false;
              motorsEnabled = (json['motorsEnabled'] is bool) ? json['motorsEnabled'] : false;
              isAnimating = (json['isAnimating'] is bool) ? json['isAnimating'] : false;
              isConnected = true;
              lastError = "";
            });
            
            // Animate progress bars when positions change
            if (!_progressController.isAnimating) {
              _progressController.forward().then((_) {
                if (!_isDisposed) _progressController.reset();
              });
            }
            
            print("Updated positions - Left: $leftPosition, Right: $rightPosition"); // Debug print
          }
        } catch (e) {
          print("Error parsing JSON line '$jsonLine': $e");
        }
      }
    } catch (e) {
      print("Error processing data: $e");
      if (!_isDisposed && mounted) {
        setState(() {
          lastError = "Data parsing error: $e";
        });
      }
    }
  }

  Future<void> _sendCommand(Map<String, dynamic> command) async {
    if (_isDisposed || !mounted) return;
    
    if (!_canSendData()) {
      print("Cannot send data - connection not available");
      setState(() {
        isConnected = false;
        lastError = "Connection not available";
      });
      _stopStatusTimer();
      return;
    }

    try {
      String jsonString = jsonEncode(command);
      print("Sending: $jsonString"); // Debug print
      
      widget.connection.output.add(Uint8List.fromList(utf8.encode(jsonString + '\n')));
      await widget.connection.output.allSent;
      
      // Connection successful - restart timer if it was stopped
      if (!isConnected && !_isDisposed && mounted) {
        setState(() {
          isConnected = true;
          lastError = "";
        });
        if (_statusTimer == null || !_statusTimer!.isActive) {
          _startStatusTimer(); // Restart timer if connection was restored
        }
      }
    } catch (e) {
      print("Send error: $e");
      if (!_isDisposed && mounted) {
        setState(() {
          isConnected = false;
          lastError = "Send failed: ${e.toString().split(':').last.trim()}";
        });
        _stopStatusTimer(); // Stop timer if send fails
      }
    }
  }

  Future<void> _disconnect() async {
    _isDisposed = true; // Prevent further operations
    _stopStatusTimer(); // Stop timer before disconnecting
    
    try {
      await widget.connection.close();
    } catch (e) {
      print("Disconnect error: $e");
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
          onThemeChanged: widget.onThemeChanged,
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
              // Header
              _buildHeader(isTablet),
              
              // Content - FIX OVERFLOW with Flexible
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
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkMode 
              ? Colors.orange.withOpacity(0.3) 
              : Colors.blue.withOpacity(0.3),
            width: 2,
          ),
        ),
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
          
          SizedBox(width: 16),
          
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
                          fontSize: isTablet ? 18 : 16,
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
                  Text(
                    'Auto: ${_statusTimer?.isActive == true ? "ON" : "OFF"} | Count: $_statusRequestCount',
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 12,
                      color: widget.isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          
          // Theme Toggle
          GestureDetector(
            onTap: () => widget.onThemeChanged(!widget.isDarkMode),
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
                widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
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
          padding: EdgeInsets.all(isTablet ? 20 : 16), // Reduced padding for tablets
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (isTablet ? 40 : 32),
            ),
            child: Column(
              children: [
                _buildStatusCard(isTablet),
                SizedBox(height: isTablet ? 16 : 12), // Reduced spacing
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
      padding: EdgeInsets.all(20), // Reduced padding
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildStatusCard(true),
          ),
          SizedBox(width: 16), // Reduced spacing
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
      padding: EdgeInsets.all(isTablet ? 24 : 20), // Reduced padding
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
        mainAxisSize: MainAxisSize.min, // Fix overflow
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
          
          SizedBox(height: isTablet ? 24 : 20), // Reduced spacing
          
          // Motor Position Displays
          Row(
            children: [
              Expanded(
                child: _buildMotorDisplay(
                  'LEFT MOTOR',
                  leftPosition,
                  Colors.blue,
                  isTablet,
                ),
              ),
              SizedBox(width: isTablet ? 20 : 16), // Reduced spacing
              Expanded(
                child: _buildMotorDisplay(
                  'RIGHT MOTOR',
                  rightPosition,
                  Colors.green,
                  isTablet,
                ),
              ),
            ],
          ),
          
          SizedBox(height: isTablet ? 24 : 20), // Reduced spacing
          
          // System Status
          _buildSystemStatus(isTablet),
        ],
      ),
    );
  }

  Widget _buildMotorDisplay(String title, int position, Color color, bool isTablet) {
    double percentage = position / 320.0;
    
    return Container(
      padding: EdgeInsets.all(isTablet ? 16 : 12), // Reduced padding
      decoration: BoxDecoration(
        color: widget.isDarkMode 
          ? Color(0xFF0F0F23).withOpacity(0.7) 
          : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
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
          
          SizedBox(height: isTablet ? 16 : 12), // Reduced spacing
          
          // Circular Progress
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: isTablet ? 100 : 80, // Reduced size
                height: isTablet ? 100 : 80, // Reduced size
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return CircularProgressIndicator(
                      value: percentage,
                      strokeWidth: isTablet ? 8 : 6,
                      backgroundColor: color.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    );
                  },
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$position',
                    style: TextStyle(
                      fontSize: isTablet ? 20 : 16, // Reduced size
                      fontWeight: FontWeight.bold,
                      color: widget.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    '/ 320',
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 10, // Reduced size
                      color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          SizedBox(height: isTablet ? 12 : 8), // Reduced spacing
          
          // Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: isTablet ? 6 : 4, // Reduced height
            ),
          ),
          
          SizedBox(height: isTablet ? 8 : 6), // Reduced spacing
          
          Text(
            '${(percentage * 100).toInt()}%',
            style: TextStyle(
              fontSize: isTablet ? 14 : 12, // Reduced size
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
      padding: EdgeInsets.all(isTablet ? 16 : 12), // Reduced padding
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
          
          SizedBox(height: isTablet ? 12 : 8), // Reduced spacing
          
          Wrap( // Use Wrap instead of Row for better responsive behavior
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
                'Auto-Update',
                _statusTimer?.isActive ?? false,
                Icons.update_rounded,
                isTablet,
              ),
              _buildStatusIndicator(
                'Animation',
                isAnimating,
                Icons.auto_awesome_rounded,
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
          padding: EdgeInsets.all(isTablet ? 10 : 8), // Reduced padding
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
            size: isTablet ? 20 : 16, // Reduced size
          ),
        ),
        SizedBox(height: 6), // Reduced spacing
        Text(
          label,
          style: TextStyle(
            fontSize: isTablet ? 10 : 8, // Reduced size
            fontWeight: FontWeight.bold,
            color: status 
              ? Colors.green 
              : (widget.isDarkMode ? Colors.white60 : Colors.black54),
          ),
        ),
        Text(
          status ? 'ON' : 'OFF',
          style: TextStyle(
            fontSize: isTablet ? 8 : 6, // Reduced size
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
      padding: EdgeInsets.all(isTablet ? 24 : 20), // Reduced padding
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
        mainAxisSize: MainAxisSize.min, // Fix overflow
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
          
          SizedBox(height: isTablet ? 20 : 16), // Reduced spacing
          
          // Quick Actions
          _buildQuickActions(isTablet),
          
          SizedBox(height: isTablet ? 16 : 12), // Reduced spacing
          
          // Position Controls
          _buildPositionControls(isTablet),
          
          SizedBox(height: isTablet ? 16 : 12), // Reduced spacing
          
          // Special Functions
          _buildSpecialFunctions(isTablet),
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
            fontSize: isTablet ? 16 : 14, // Reduced size
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8), // Reduced spacing
        _buildControlButton(
          title: 'CENTER MOTORS',
          icon: Icons.center_focus_strong_rounded,
          onPressed: () => _sendCommand({"action": "center"}),
          color: Colors.green,
          isTablet: isTablet,
          isFullWidth: true,
        ),
        SizedBox(height: 8), // Reduced spacing
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                title: 'MAX UP',
                icon: Icons.keyboard_double_arrow_up_rounded,
                onPressed: () => _sendCommand({
                  "action": "position_set", 
                  "left": 320, 
                  "right": 320
                }),
                color: Colors.purple,
                isTablet: isTablet,
              ),
            ),
            SizedBox(width: 8), // Reduced spacing
            Expanded(
              child: _buildControlButton(
                title: 'MAX DOWN',
                icon: Icons.keyboard_double_arrow_down_rounded,
                onPressed: () => _sendCommand({
                  "action": "position_set", 
                  "left": 0, 
                  "right": 0
                }),
                color: Colors.purple,
                isTablet: isTablet,
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
          'MOVEMENT CONTROLS',
          style: TextStyle(
            fontSize: isTablet ? 16 : 14, // Reduced size
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8), // Reduced spacing
        Row(
          children: [
            Expanded(
              child: _buildControlButton(
                title: 'MOVE UP',
                icon: Icons.arrow_upward_rounded,
                onPressed: () => _sendCommand({
                  "action": "move", 
                  "direction": "up"
                }),
                color: Colors.blue,
                isTablet: isTablet,
              ),
            ),
            SizedBox(width: 8), // Reduced spacing
            Expanded(
              child: _buildControlButton(
                title: 'MOVE DOWN',
                icon: Icons.arrow_downward_rounded,
                onPressed: () => _sendCommand({
                  "action": "move", 
                  "direction": "down"
                }),
                color: Colors.blue,
                isTablet: isTablet,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecialFunctions(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SPECIAL FUNCTIONS',
          style: TextStyle(
            fontSize: isTablet ? 16 : 14, // Reduced size
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.white70 : Colors.black87,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: isTablet ? 12 : 8), // Reduced spacing
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
            SizedBox(width: 8), // Reduced spacing
            Expanded(
              child: _buildControlButton(
                title: 'TEST',
                icon: Icons.build_rounded,
                onPressed: () => _sendCommand({"action": "test"}),
                color: Colors.red,
                isTablet: isTablet,
              ),
            ),
          ],
        ),
        SizedBox(height: 8), // Reduced spacing
        _buildControlButton(
          title: 'MANUAL STATUS ($_statusRequestCount)',
          icon: Icons.refresh_rounded,
          onPressed: () {
            print("Manual status request triggered");
            _sendCommand({"action": "status"});
          },
          color: Colors.teal,
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
  }) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      height: isTablet ? 50 : 45, // Reduced height
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
        ),
        child: Row(
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isTablet ? 20 : 16), // Reduced size
            SizedBox(width: 6), // Reduced spacing
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: isTablet ? 14 : 12, // Reduced size
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