/*
 * HEADLIGHT CONTROLLER - Single Motor Mode
 * 
 * Currently configured for ONE motor on pins 4,5
 * 
 * TO ENABLE SECOND MOTOR:
 * 1. Connect second DRV8825 and motor to pins 6,7
 * 2. Uncomment all lines marked with "// UNCOMMENT when second motor connected"
 * 3. Change "bool hasSecondMotor = false;" to "bool hasSecondMotor = true;"
 * 4. Upload the modified code
 */

 #include <WiFi.h>
 #include <WebServer.h>
 #include <EEPROM.h>
 #include <ArduinoJson.h>
 #include <BluetoothSerial.h>
 #include "DRV8825.h"
 
 // Configuration structure
 struct Config {
   int leftDirPin = 4;
   int leftStepPin = 5;
   int rightDirPin = 6;
   int rightStepPin = 7;
   int pc817Pin = 14;
   int enablePin = 2;         // NEW: Enable pin for DRV8825 (LOW = enabled, HIGH = disabled)
   int centerPosition = 160;  // Center position (half of 320 steps)
   int maxPosition = 320;     // Maximum up position
   int minPosition = 0;       // Minimum down position
   bool autoCenter = true;    // Auto-center on power loss
   int animationSpeed = 3;    // Delay between steps (ms)
   int motorTimeout = 2000;   // NEW: Time (ms) to disable motors after movement to reduce heat
 };
 
 // Global variables
 Config config;
 DRV8825 leftStepper;
 // DRV8825 rightStepper;  // UNCOMMENT when second motor is connected
 WebServer server(80);
 BluetoothSerial SerialBT;
 
 int leftCurrentPosition = 0;
 int rightCurrentPosition = 0;  // Keep for future use
 bool headlightsOn = false;
 bool lastHeadlightState = false;
 bool isAnimating = false;
 unsigned long lastMovementTime = 0;  // NEW: Track when motors last moved
 bool motorsEnabled = false;          // NEW: Track motor enable state
 
 // Feature flag - set to true when second motor is connected
 bool hasSecondMotor = false;
 
 // EEPROM addresses
 const int CONFIG_ADDR = 0;
 const int LEFT_POS_ADDR = sizeof(Config);
 const int RIGHT_POS_ADDR = sizeof(Config) + sizeof(int);
 
 // WiFi credentials (AP mode)
 const char* ssid = "HeadlightController";
 const char* password = "headlight123";
 
 // Bluetooth device name
 const char* btDeviceName = "HeadlightController";
 
 // Function declarations
 void setupWiFi();
 void setupBluetooth();
 void setupWebServer();
 void handleBluetoothCommands();
 void handleSerialCommands();
 void processBluetoothCommand(String command);
 void sendBluetoothStatusUpdate();
 void sendBluetoothConfig();
 void sendBluetoothSuccess(String message);
 void sendBluetoothError(String error);
 void sendBluetoothStatus(String status);
 void handleRoot();
 void handleGetConfig();
 void handleSetConfig();
 void handleGetStatus();
 void handleMove();
 void handleCenter();
 void handleAnimate();
 void handleTest();
 void handleMaxUp();    // NEW
 void handleMaxDown();  // NEW
 void moveToPosition(int leftTarget, int rightTarget);
 void moveSteps(int leftSteps, int rightSteps);
 void forceMoveStepper(DRV8825 &stepper, int steps);
 void rawMotorTest();
 void centerMotors();
 void startupAnimation();
 void testMotors();
 void enableMotors();   // NEW
 void disableMotors();  // NEW
 void checkMotorTimeout(); // NEW
 void loadConfig();
 void saveConfig();
 void loadPositions();
 void savePositions();
 
 void setup() {
   Serial.begin(115200);
   Serial.println("=====================================");
   Serial.println("🚗 Headlight Controller Starting...");
   Serial.println("=====================================");
   
   // Initialize EEPROM
   EEPROM.begin(512);
   loadConfig();  // This will fix corrupted config automatically
   
   // Load positions from EEPROM (with validation)
   loadPositions();  // This will fix corrupted positions automatically
   
   // NEW: Initialize enable pin
   pinMode(config.enablePin, OUTPUT);
   disableMotors(); // Start with motors disabled to prevent heating
   Serial.println("✓ Enable pin " + String(config.enablePin) + " initialized (motors disabled)");
   
   // Initialize steppers with detailed debugging
   Serial.println("Initializing steppers...");
   Serial.println("Left motor - DIR:" + String(config.leftDirPin) + " STEP:" + String(config.leftStepPin));
   // Serial.println("Right motor - DIR:" + String(config.rightDirPin) + " STEP:" + String(config.rightStepPin));
   
   leftStepper.begin(config.leftDirPin, config.leftStepPin);
   // rightStepper.begin(config.rightDirPin, config.rightStepPin);  // UNCOMMENT when second motor connected
   Serial.println("✓ LEFT stepper initialized");
   Serial.println("NOTE: Right motor commented out - uncomment when connected");
   
   // Test pin modes
   pinMode(config.leftDirPin, OUTPUT);
   pinMode(config.leftStepPin, OUTPUT);
   // pinMode(config.rightDirPin, OUTPUT);     // UNCOMMENT when second motor connected
   // pinMode(config.rightStepPin, OUTPUT);    // UNCOMMENT when second motor connected
   Serial.println("✓ LEFT motor pins set to OUTPUT mode");
   
   // Initialize PC817 pin WITHOUT pullup first
   pinMode(config.pc817Pin, INPUT);
   Serial.println("✓ PC817 pin " + String(config.pc817Pin) + " initialized WITHOUT pullup");
   Serial.println("  Pin 14 value (no pullup): " + String(digitalRead(config.pc817Pin)));
   
   // Now test with pullup
   pinMode(config.pc817Pin, INPUT_PULLUP);
   delay(10);
   Serial.println("  Pin 14 value (with pullup): " + String(digitalRead(config.pc817Pin)));
   
   // Fix headlight logic - if pin 14 is connected to 5V, it should be OFF
   // When headlights are ON, pin 14 should be LOW (connected to ground via PC817)
   bool pinValue = digitalRead(config.pc817Pin);
   headlightsOn = !pinValue;  // Invert the logic
   Serial.println("  Headlight state: " + String(headlightsOn ? "ON" : "OFF"));
   
   // Start WiFi AP
   setupWiFi();
   
   // Start Bluetooth
   setupBluetooth();
   
   // Setup web server routes
   setupWebServer();
   
   Serial.println("=====================================");
   Serial.println("🎉 SYSTEM READY!");
   Serial.println("WiFi AP: " + String(ssid));
   Serial.println("Bluetooth: " + String(btDeviceName));
   Serial.println("Web: http://192.168.4.1");
   Serial.println("Enable Pin: " + String(config.enablePin) + " (reduces motor heat)");
   Serial.println("=====================================");
   Serial.println("MOTOR TEST - Type 'rawtest' to test pins directly");
   Serial.println("Type 'help' for all commands");
 }
 
 void loop() {
   server.handleClient();
   handleBluetoothCommands();
   handleSerialCommands();  // Add manual control via Serial Monitor
   
   // NEW: Check if motors should be disabled due to timeout (reduces heat)
   checkMotorTimeout();
   
   // Check headlight state with FIXED LOGIC
   bool pinValue = digitalRead(config.pc817Pin);
   bool currentHeadlightState = !pinValue;  // INVERT - when pin is HIGH (5V), headlights are OFF
   
   if (currentHeadlightState != lastHeadlightState) {
     lastHeadlightState = currentHeadlightState;
     headlightsOn = currentHeadlightState;
     
     Serial.println("=== HEADLIGHT STATE CHANGE ===");
     Serial.println("Pin 14 raw value: " + String(pinValue));
     Serial.println("Headlight state: " + String(headlightsOn ? "ON" : "OFF"));
     
     if (headlightsOn) {
       Serial.println("🔆 HEADLIGHTS TURNED ON");
       sendBluetoothStatus("headlights_on");
       if (hasSecondMotor) {
         moveToPosition(config.maxPosition, config.maxPosition);
       } else {
         moveToPosition(config.maxPosition, rightCurrentPosition); // Only move left motor
       }
       delay(500);
       startupAnimation();
     } else {
       Serial.println("🔅 HEADLIGHTS TURNED OFF");
       sendBluetoothStatus("headlights_off");
       if (config.autoCenter) {
         centerMotors();
       } else {
         if (hasSecondMotor) {
           moveToPosition(config.minPosition, config.minPosition);
         } else {
           moveToPosition(config.minPosition, rightCurrentPosition); // Only move left motor
         }
       }
     }
   }
   
   delay(100);
 }
 
 // NEW: Enable motors (allows movement, but causes heating)
 void enableMotors() {
   if (!motorsEnabled) {
     digitalWrite(config.enablePin, LOW);  // DRV8825 enable pin is active LOW
     motorsEnabled = true;
     lastMovementTime = millis();
     Serial.println("🔥 Motors ENABLED (will heat up)");
     delay(50); // Give driver time to stabilize
   }
 }
 
 // NEW: Disable motors (prevents heating, but no holding torque)
 void disableMotors() {
   if (motorsEnabled) {
     digitalWrite(config.enablePin, HIGH);  // DRV8825 enable pin is active LOW
     motorsEnabled = false;
     Serial.println("❄️ Motors DISABLED (cooling down)");
   }
 }
 
 // NEW: Check if motors should be disabled to reduce heat
 void checkMotorTimeout() {
   if (motorsEnabled && !isAnimating) {
     if (millis() - lastMovementTime > config.motorTimeout) {
       disableMotors();
     }
   }
 }
 
 void setupWiFi() {
   WiFi.mode(WIFI_AP);
   WiFi.softAP(ssid, password);
   
   Serial.println("WiFi AP started");
   Serial.print("IP address: ");
   Serial.println(WiFi.softAPIP());
 }
 
 void setupBluetooth() {
   SerialBT.begin(btDeviceName);
   Serial.println("Bluetooth started");
   Serial.println("Device name: " + String(btDeviceName));
   
   // Send welcome message
   DynamicJsonDocument welcomeDoc(512);
   welcomeDoc["type"] = "welcome";
   welcomeDoc["message"] = "HeadlightController Connected";
   welcomeDoc["version"] = "1.0";
   
   String welcomeMsg;
   serializeJson(welcomeDoc, welcomeMsg);
   SerialBT.println(welcomeMsg);
 }
 
 void handleBluetoothCommands() {
   if (SerialBT.available()) {
     String command = SerialBT.readStringUntil('\n');
     command.trim();
     
     if (command.length() > 0) {
       processBluetoothCommand(command);
     }
   }
 }
 
 void handleSerialCommands() {
   if (Serial.available()) {
     String command = Serial.readStringUntil('\n');
     command.trim();
     command.toLowerCase();
     
     Serial.println("Serial Command: " + command);
     
     if (command == "test") {
       Serial.println("🔧 TESTING MOTORS");
       testMotors();
     }
     else if (command == "center") {
       Serial.println("🎯 CENTERING MOTORS");
       centerMotors();
     }
     else if (command == "max") {
       Serial.println("⬆️ MOVING TO MAX");
       moveToPosition(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
     }
     else if (command == "min") {
       Serial.println("⬇️ MOVING TO MIN");
       moveToPosition(config.minPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
     }
     else if (command == "up") {
       Serial.println("⬆️ MOVING UP");
       moveSteps(20, 20);
     }
     else if (command == "down") {
       Serial.println("⬇️ MOVING DOWN");
       moveSteps(-20, -20);
     }
     else if (command == "left_up") {
       Serial.println("⬆️ LEFT MOTOR UP");
       moveSteps(20, 0);
     }
     else if (command == "left_down") {
       Serial.println("⬇️ LEFT MOTOR DOWN");
       moveSteps(-20, 0);
     }
     else if (command == "right_up") {
       if (hasSecondMotor) {
         Serial.println("⬆️ RIGHT MOTOR UP");
         moveSteps(0, 20);
       } else {
         Serial.println("⚠️ RIGHT MOTOR not connected");
       }
     }
     else if (command == "right_down") {
       if (hasSecondMotor) {
         Serial.println("⬇️ RIGHT MOTOR DOWN");
         moveSteps(0, -20);
       } else {
         Serial.println("⚠️ RIGHT MOTOR not connected");
       }
     }
     else if (command == "animate") {
       Serial.println("✨ STARTING ANIMATION");
       startupAnimation();
     }
     else if (command == "enable") {  // NEW
       enableMotors();
     }
     else if (command == "disable") {  // NEW
       disableMotors();
     }
     else if (command == "status") {
       Serial.println("=== STATUS ===");
       Serial.println("Left Position: " + String(leftCurrentPosition));
       Serial.println("Right Position: " + String(rightCurrentPosition));
       Serial.println("Headlights: " + String(headlightsOn ? "ON" : "OFF"));
       Serial.println("Motors: " + String(motorsEnabled ? "ENABLED (hot)" : "DISABLED (cool)"));
       Serial.println("Center: " + String(config.centerPosition));
       Serial.println("Max: " + String(config.maxPosition));
       Serial.println("Min: " + String(config.minPosition));
     }
     else if (command == "help") {
       Serial.println("=== AVAILABLE COMMANDS ===");
       Serial.println("test - Test motors (up/down/center sequence)");
       Serial.println("center - Center motors");
       Serial.println("max - Move to maximum position");
       Serial.println("min - Move to minimum position");
       Serial.println("up - Move motors up");
       Serial.println("down - Move motors down");
       Serial.println("left_up - Move left motor up");
       Serial.println("left_down - Move left motor down");
       if (hasSecondMotor) {
         Serial.println("right_up - Move right motor up");
         Serial.println("right_down - Move right motor down");
       }
       Serial.println("animate - Start animation sequence");
       Serial.println("enable - Enable motors (causes heating)");   // NEW
       Serial.println("disable - Disable motors (reduces heat)");  // NEW
       Serial.println("status - Show current status");
       Serial.println("help - Show this help");
     }
     else if (command.length() > 0) {
       Serial.println("Unknown command. Type 'help' for available commands.");
     }
   }
 }
 
 void processBluetoothCommand(String command) {
   Serial.println("BT Command: " + command);
   
   // Check if it's a simple text command first
   command.toLowerCase();
   if (command == "test") {
     testMotors();
     SerialBT.println("Motor test completed");
     return;
   }
   else if (command == "center") {
     centerMotors();
     SerialBT.println("Motors centered");
     return;
   }
   else if (command == "max") {
     moveToPosition(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
     SerialBT.println("Moved to maximum");
     return;
   }
   else if (command == "min") {
     moveToPosition(config.minPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
     SerialBT.println("Moved to minimum");
     return;
   }
   else if (command == "up") {
     moveSteps(20, 20);
     SerialBT.println("Moved up");
     return;
   }
   else if (command == "down") {
     moveSteps(-20, -20);
     SerialBT.println("Moved down");
     return;
   }
   else if (command == "animate") {
     if (!isAnimating) {
       startupAnimation();
       SerialBT.println("Animation started");
     } else {
       SerialBT.println("Animation already running");
     }
     return;
   }
   else if (command == "status") {
     SerialBT.println("Left: " + String(leftCurrentPosition) + ", Right: " + String(rightCurrentPosition));
     SerialBT.println("Headlights: " + String(headlightsOn ? "ON" : "OFF"));
     return;
   }
   
   // If not a simple command, try to parse as JSON
   DynamicJsonDocument doc(1024);
   DeserializationError error = deserializeJson(doc, command);
   
   if (error) {
     SerialBT.println("Invalid command. Try: test, center, max, min, up, down, animate, status");
     return;
   }
   
   String action = doc["action"];
   
   if (action == "status") {
     sendBluetoothStatusUpdate();
   }
   else if (action == "move") {
     String direction = doc["direction"];
     int steps = doc.containsKey("steps") ? doc["steps"] : 20;
     
     if (direction == "up") {
       moveSteps(steps, steps);
     } else if (direction == "down") {
       moveSteps(-steps, -steps);
     } else if (direction == "left_up") {
       moveSteps(steps, 0);
     } else if (direction == "left_down") {
       moveSteps(-steps, 0);
     } else if (direction == "right_up") {
       moveSteps(0, steps);
     } else if (direction == "right_down") {
       moveSteps(0, -steps);
     }
     
     sendBluetoothSuccess("Movement completed");
   }
   else if (action == "center") {
     centerMotors();
     sendBluetoothSuccess("Motors centered");
   }
   else if (action == "animate") {
     if (!isAnimating) {
       startupAnimation();
       sendBluetoothSuccess("Animation started");
     } else {
       sendBluetoothError("Animation already running");
     }
   }
   else if (action == "test") {
     testMotors();
     sendBluetoothSuccess("Motor test completed");
   }
   else if (action == "config_get") {
     sendBluetoothConfig();
   }
   else if (action == "config_set") {
     if (doc.containsKey("centerPosition")) config.centerPosition = doc["centerPosition"];
     if (doc.containsKey("animationSpeed")) config.animationSpeed = doc["animationSpeed"];
     if (doc.containsKey("autoCenter")) config.autoCenter = doc["autoCenter"];
     if (doc.containsKey("motorTimeout")) config.motorTimeout = doc["motorTimeout"];  // NEW
     
     saveConfig();
     sendBluetoothSuccess("Configuration saved");
   }
   else if (action == "position_set") {
     if (doc.containsKey("left") && doc.containsKey("right")) {
       int leftPos = doc["left"];
       int rightPos = doc["right"];
       moveToPosition(leftPos, rightPos);
       sendBluetoothSuccess("Position set");
     } else {
       sendBluetoothError("Missing left or right position");
     }
   }
   else {
     sendBluetoothError("Unknown action: " + action);
   }
 }
 
 void sendBluetoothStatusUpdate() {
   DynamicJsonDocument doc(1024);
   doc["type"] = "status";
   doc["leftPosition"] = leftCurrentPosition;
   doc["rightPosition"] = rightCurrentPosition;
   doc["headlightsOn"] = headlightsOn;
   doc["isAnimating"] = isAnimating;
   doc["motorsEnabled"] = motorsEnabled;  // NEW
   doc["centerPosition"] = config.centerPosition;
   doc["maxPosition"] = config.maxPosition;
   doc["minPosition"] = config.minPosition;
   
   String response;
   serializeJson(doc, response);
   SerialBT.println(response);
 }
 
 void sendBluetoothConfig() {
   DynamicJsonDocument doc(1024);
   doc["type"] = "config";
   doc["leftDirPin"] = config.leftDirPin;
   doc["leftStepPin"] = config.leftStepPin;
   doc["rightDirPin"] = config.rightDirPin;
   doc["rightStepPin"] = config.rightStepPin;
   doc["pc817Pin"] = config.pc817Pin;
   doc["enablePin"] = config.enablePin;  // NEW
   doc["centerPosition"] = config.centerPosition;
   doc["maxPosition"] = config.maxPosition;
   doc["minPosition"] = config.minPosition;
   doc["autoCenter"] = config.autoCenter;
   doc["animationSpeed"] = config.animationSpeed;
   doc["motorTimeout"] = config.motorTimeout;  // NEW
   
   String response;
   serializeJson(doc, response);
   SerialBT.println(response);
 }
 
 void sendBluetoothSuccess(String message) {
   DynamicJsonDocument doc(512);
   doc["type"] = "success";
   doc["message"] = message;
   doc["timestamp"] = millis();
   
   String response;
   serializeJson(doc, response);
   SerialBT.println(response);
 }
 
 void sendBluetoothError(String error) {
   DynamicJsonDocument doc(512);
   doc["type"] = "error";
   doc["message"] = error;
   doc["timestamp"] = millis();
   
   String response;
   serializeJson(doc, response);
   SerialBT.println(response);
 }
 
 void sendBluetoothStatus(String status) {
   DynamicJsonDocument doc(512);
   doc["type"] = "notification";
   doc["status"] = status;
   doc["timestamp"] = millis();
   
   String response;
   serializeJson(doc, response);
   SerialBT.println(response);
 }
 
 void setupWebServer() {
   // Serve main page
   server.on("/", handleRoot);
   
   // Debug endpoint
   server.on("/debug", []() {
     bool pinValue = digitalRead(config.pc817Pin);
     bool headlightState = !pinValue;  // Correct logic
     
     String debug = "=== DEBUG INFO ===\n";
     debug += "Left Position: " + String(leftCurrentPosition) + "\n";
     debug += "Right Position: " + String(rightCurrentPosition) + "\n";
     debug += "Pin 14 Raw Value: " + String(pinValue) + "\n";
     debug += "Headlights: " + String(headlightState ? "ON" : "OFF") + "\n";
     debug += "Motors: " + String(motorsEnabled ? "ENABLED (hot)" : "DISABLED (cool)") + "\n";  // NEW
     debug += "Center Position: " + String(config.centerPosition) + "\n";
     debug += "Animation Speed: " + String(config.animationSpeed) + "\n";
     debug += "Motor Timeout: " + String(config.motorTimeout) + "ms\n";  // NEW
     debug += "Auto Center: " + String(config.autoCenter ? "YES" : "NO") + "\n";
     debug += "Is Animating: " + String(isAnimating ? "YES" : "NO") + "\n";
     debug += "Left Motor: DIR=" + String(config.leftDirPin) + " STEP=" + String(config.leftStepPin) + "\n";
     debug += "Right Motor: DIR=" + String(config.rightDirPin) + " STEP=" + String(config.rightStepPin) + "\n";
     debug += "PC817 Pin: " + String(config.pc817Pin) + "\n";
     debug += "Enable Pin: " + String(config.enablePin) + "\n";  // NEW
     debug += "Free Memory: " + String(ESP.getFreeHeap()) + " bytes\n";
     debug += "Uptime: " + String(millis()/1000) + " seconds\n";
     debug += "\nCOMMANDS:\n";
     debug += "rawtest - Test motor pins directly\n";
     debug += "reset - Reset position tracking\n";
     debug += "test - Test motors\n";
     debug += "enable/disable - Control motor power\n";  // NEW
     debug += "status - Show status\n";
     server.send(200, "text/plain", debug);
   });
   
   // API endpoints
   server.on("/api/config", HTTP_GET, handleGetConfig);
   server.on("/api/config", HTTP_POST, handleSetConfig);
   server.on("/api/status", HTTP_GET, handleGetStatus);
   server.on("/api/move", HTTP_POST, handleMove);
   server.on("/api/center", HTTP_POST, handleCenter);
   server.on("/api/animate", HTTP_POST, handleAnimate);
   server.on("/api/test", HTTP_POST, handleTest);
   server.on("/api/max_up", HTTP_POST, handleMaxUp);      // NEW
   server.on("/api/max_down", HTTP_POST, handleMaxDown);  // NEW
   
   server.begin();
   Serial.println("Web server started");
 }
 
 void handleRoot() {
   String html = "<!DOCTYPE html><html><head>";
   html += "<meta charset='UTF-8'>";
   html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
   html += "<title>Headlight Controller</title>";
   html += "<style>";
   html += "* { margin: 0; padding: 0; box-sizing: border-box; }";
   html += "body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; }";
   html += ".container { max-width: 500px; margin: 0 auto; background: white; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); overflow: hidden; }";
   html += ".header { background: #2c3e50; color: white; padding: 20px; text-align: center; }";
   html += ".content { padding: 20px; }";
   html += ".status { background: #ecf0f1; padding: 15px; border-radius: 10px; margin-bottom: 20px; }";
   html += ".controls { margin-bottom: 20px; }";
   html += ".btn { width: 100%; padding: 12px; margin: 5px 0; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; transition: all 0.3s; }";
   html += ".btn-primary { background: #3498db; color: white; }";
   html += ".btn-success { background: #27ae60; color: white; }";
   html += ".btn-warning { background: #f39c12; color: white; }";
   html += ".btn-danger { background: #e74c3c; color: white; }";
   html += ".btn-orange { background: #e67e22; color: white; }";
   html += ".btn-purple { background: #9b59b6; color: white; }";  // NEW
   html += ".btn:hover { transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0,0,0,0.2); }";
   html += ".input-group { margin: 10px 0; }";
   html += ".input-group label { display: block; margin-bottom: 5px; font-weight: bold; }";
   html += ".input-group input { width: 100%; padding: 10px; border: 2px solid #ddd; border-radius: 5px; font-size: 16px; }";
   html += ".row { display: flex; gap: 10px; }";
   html += ".col { flex: 1; }";
   html += "#status { color: #27ae60; font-weight: bold; }";
   html += ".offline { color: #e74c3c !important; }";
   html += "</style></head><body>";
   
   html += "<div class='container'>";
   html += "<div class='header'>";
   html += "<h1>Headlight Controller</h1>";
   html += "<p>Audi A4 B6 Stepper Control</p>";
   html += "</div>";
   html += "<div class='content'>";
   
   html += "<div class='status'>";
   html += "<div><strong>Status:</strong> <span id='status'>Loading...</span></div>";
   html += "<div><strong>WiFi:</strong> HeadlightController (192.168.4.1)</div>";
   html += "<div><strong>Bluetooth:</strong> HeadlightController</div>";
   html += "<div><strong>Left Position:</strong> <span id='leftPos'>-</span></div>";
   html += "<div><strong>Right Position:</strong> <span id='rightPos'>-</span></div>";
   html += "<div><strong>Headlights:</strong> <span id='headlights'>-</span></div>";
   html += "<div><strong>Motors:</strong> <span id='motors'>-</span></div>";  // NEW
   html += "</div>";
   
   html += "<div class='controls'>";
   html += "<h3>Quick Controls</h3>";
   html += "<button class='btn btn-success' onclick='centerMotors()'>Center Motors</button>";
   
   // NEW: Max Up and Max Down buttons
   html += "<div class='row'>";
   html += "<div class='col'>";
   html += "<button class='btn btn-purple' onclick='maxUp()'>⬆️ Max Up</button>";
   html += "</div>";
   html += "<div class='col'>";
   html += "<button class='btn btn-purple' onclick='maxDown()'>⬇️ Max Down</button>";
   html += "</div>";
   html += "</div>";
   
   html += "<div class='row'>";
   html += "<div class='col'>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"up\")'>Move Up</button>";
   html += "</div>";
   html += "<div class='col'>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"down\")'>Move Down</button>";
   html += "</div>";
   html += "</div>";
   html += "<button class='btn btn-orange' onclick='location.href=\"/debug\"'>🔍 Debug Info</button>";
   html += "<button class='btn btn-warning' onclick='startAnimation()'>Start Animation</button>";
   html += "<button class='btn btn-danger' onclick='testMotors()'>Test Motors</button>";
   html += "</div>";
   
   html += "<div class='controls'>";
   html += "<h3>Individual Control</h3>";
   html += "<div class='row'>";
   html += "<div class='col'>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"left_up\")'>Left Up</button>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"left_down\")'>Left Down</button>";
   html += "</div>";
   html += "<div class='col'>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"right_up\")'>Right Up</button>";
   html += "<button class='btn btn-primary' onclick='moveMotors(\"right_down\")'>Right Down</button>";
   html += "</div>";
   html += "</div>";
   html += "</div>";
   
   html += "<div class='controls'>";
   html += "<h3>Configuration</h3>";
   html += "<div class='input-group'>";
   html += "<label>Center Position (0-320):</label>";
   html += "<input type='number' id='centerPos' min='0' max='320' value='160'>";
   html += "</div>";
   html += "<div class='input-group'>";
   html += "<label>Animation Speed (ms):</label>";
   html += "<input type='number' id='animSpeed' min='1' max='100' value='3'>";
   html += "</div>";
   html += "<div class='input-group'>";  // NEW
   html += "<label>Motor Timeout (ms) - reduces heat:</label>";
   html += "<input type='number' id='motorTimeout' min='500' max='10000' value='2000'>";
   html += "</div>";
   html += "<button class='btn btn-success' onclick='saveConfig()'>Save Configuration</button>";
   html += "</div>";
   html += "</div></div>";
   
   html += "<script>";
   html += "function updateStatus() {";
   html += "fetch('/api/status')";
   html += ".then(r => r.json())";
   html += ".then(data => {";
   html += "document.getElementById('status').textContent = 'Online';";
   html += "document.getElementById('leftPos').textContent = data.leftPosition;";
   html += "document.getElementById('rightPos').textContent = data.rightPosition;";
   html += "document.getElementById('headlights').textContent = data.headlightsOn ? 'ON' : 'OFF';";
   html += "document.getElementById('motors').textContent = data.motorsEnabled ? 'ENABLED (hot)' : 'DISABLED (cool)';";  // NEW
   html += "})";
   html += ".catch(() => {";
   html += "document.getElementById('status').textContent = 'Offline';";
   html += "});";
   html += "}";
   
   html += "function loadConfig() {";
   html += "fetch('/api/config')";
   html += ".then(r => r.json())";
   html += ".then(data => {";
   html += "document.getElementById('centerPos').value = data.centerPosition;";
   html += "document.getElementById('animSpeed').value = data.animationSpeed;";
   html += "document.getElementById('motorTimeout').value = data.motorTimeout;";  // NEW
   html += "});";
   html += "}";
   
   html += "function centerMotors() { fetch('/api/center', {method: 'POST'}); }";
   html += "function moveMotors(direction) { fetch('/api/move', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({direction: direction}) }); }";
   html += "function startAnimation() { fetch('/api/animate', {method: 'POST'}); }";
   html += "function testMotors() { fetch('/api/test', {method: 'POST'}); }";
   html += "function maxUp() { fetch('/api/max_up', {method: 'POST'}); }";      // NEW
   html += "function maxDown() { fetch('/api/max_down', {method: 'POST'}); }";  // NEW
   
   html += "function saveConfig() {";
   html += "const config = {";
   html += "centerPosition: parseInt(document.getElementById('centerPos').value),";
   html += "animationSpeed: parseInt(document.getElementById('animSpeed').value),";
   html += "motorTimeout: parseInt(document.getElementById('motorTimeout').value)";  // NEW
   html += "};";
   html += "fetch('/api/config', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(config) })";
   html += ".then(() => { alert('Configuration saved!'); });";
   html += "}";
   
   html += "updateStatus(); loadConfig(); setInterval(updateStatus, 2000);";
   html += "</script>";
   html += "</body></html>";
   
   server.send(200, "text/html", html);
 }
 
 // NEW: Handle Max Up button
 void handleMaxUp() {
   moveToPosition(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
   server.send(200, "text/plain", "OK");
 }
 
 // NEW: Handle Max Down button  
 void handleMaxDown() {
   moveToPosition(config.minPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
   server.send(200, "text/plain", "OK");
 }
 
 void handleGetConfig() {
   DynamicJsonDocument doc(1024);
   doc["leftDirPin"] = config.leftDirPin;
   doc["leftStepPin"] = config.leftStepPin;
   doc["rightDirPin"] = config.rightDirPin;
   doc["rightStepPin"] = config.rightStepPin;
   doc["pc817Pin"] = config.pc817Pin;
   doc["enablePin"] = config.enablePin;  // NEW
   doc["centerPosition"] = config.centerPosition;
   doc["maxPosition"] = config.maxPosition;
   doc["minPosition"] = config.minPosition;
   doc["autoCenter"] = config.autoCenter;
   doc["animationSpeed"] = config.animationSpeed;
   doc["motorTimeout"] = config.motorTimeout;  // NEW
   
   String response;
   serializeJson(doc, response);
   server.send(200, "application/json", response);
 }
 
 void handleSetConfig() {
   DynamicJsonDocument doc(1024);
   deserializeJson(doc, server.arg("plain"));
   
   if (doc.containsKey("centerPosition")) config.centerPosition = doc["centerPosition"];
   if (doc.containsKey("animationSpeed")) config.animationSpeed = doc["animationSpeed"];
   if (doc.containsKey("autoCenter")) config.autoCenter = doc["autoCenter"];
   if (doc.containsKey("motorTimeout")) config.motorTimeout = doc["motorTimeout"];  // NEW
   
   saveConfig();
   server.send(200, "text/plain", "OK");
 }
 
 void handleGetStatus() {
   DynamicJsonDocument doc(1024);
   doc["leftPosition"] = leftCurrentPosition;
   doc["rightPosition"] = rightCurrentPosition;
   doc["headlightsOn"] = headlightsOn;
   doc["isAnimating"] = isAnimating;
   doc["motorsEnabled"] = motorsEnabled;  // NEW
   
   String response;
   serializeJson(doc, response);
   server.send(200, "application/json", response);
 }
 
 void handleMove() {
   DynamicJsonDocument doc(1024);
   deserializeJson(doc, server.arg("plain"));
   
   String direction = doc["direction"];
   int steps = 20; // Default step size
   
   if (direction == "up") {
     moveSteps(steps, steps);
   } else if (direction == "down") {
     moveSteps(-steps, -steps);
   } else if (direction == "left_up") {
     moveSteps(steps, 0);
   } else if (direction == "left_down") {
     moveSteps(-steps, 0);
   } else if (direction == "right_up") {
     moveSteps(0, steps);
   } else if (direction == "right_down") {
     moveSteps(0, -steps);
   }
   
   server.send(200, "text/plain", "OK");
 }
 
 void handleCenter() {
   centerMotors();
   server.send(200, "text/plain", "OK");
 }
 
 void handleAnimate() {
   startupAnimation();
   server.send(200, "text/plain", "OK");
 }
 
 void handleTest() {
   testMotors();
   server.send(200, "text/plain", "OK");
 }
 
 void moveToPosition(int leftTarget, int rightTarget) {
   leftTarget = constrain(leftTarget, config.minPosition, config.maxPosition);
   rightTarget = constrain(rightTarget, config.minPosition, config.maxPosition);
   
   int leftSteps = leftTarget - leftCurrentPosition;
   int rightSteps = rightTarget - rightCurrentPosition;
   
   moveSteps(leftSteps, rightSteps);
 }
 
 void moveSteps(int leftSteps, int rightSteps) {
   Serial.println("=== MOVE STEPS REQUEST ===");
   Serial.println("Requested - Left: " + String(leftSteps) + " steps, Right: " + String(rightSteps) + " steps");
   Serial.println("Current positions - L:" + String(leftCurrentPosition) + " R:" + String(rightCurrentPosition));
   
   // Calculate new positions and constrain them
   int newLeftPos = constrain(leftCurrentPosition + leftSteps, config.minPosition, config.maxPosition);
   int newRightPos = constrain(rightCurrentPosition + rightSteps, config.minPosition, config.maxPosition);
   
   // Recalculate actual steps needed
   int actualLeftSteps = newLeftPos - leftCurrentPosition;
   int actualRightSteps = newRightPos - rightCurrentPosition;
   
   Serial.println("Calculated - Left: " + String(actualLeftSteps) + " steps, Right: " + String(actualRightSteps) + " steps");
   Serial.println("Target positions - L:" + String(newLeftPos) + " R:" + String(newRightPos));
   
   // FORCE MOVEMENT even if steps are 0
   if (abs(leftSteps) > 0 || abs(rightSteps) > 0) {
     enableMotors();  // NEW: Enable motors before movement
     
     Serial.println("🔧 FORCING MOVEMENT with original request");
     
     // Use original requested steps, not calculated ones
     if (leftSteps != 0) {
       Serial.println("Moving LEFT motor " + String(leftSteps) + " steps");
       forceMoveStepper(leftStepper, leftSteps);
       leftCurrentPosition += leftSteps; // Update position tracking
     }
     
     if (rightSteps != 0) {
       if (hasSecondMotor) {
         Serial.println("Moving RIGHT motor " + String(rightSteps) + " steps");
         // forceMoveStepper(rightStepper, rightSteps);  // UNCOMMENT when second motor connected
         rightCurrentPosition += rightSteps; // Update position tracking
       } else {
         Serial.println("⚠️ RIGHT motor command ignored - not connected");
       }
     }
     
     // Constrain positions after movement
     leftCurrentPosition = constrain(leftCurrentPosition, config.minPosition, config.maxPosition);
     rightCurrentPosition = constrain(rightCurrentPosition, config.minPosition, config.maxPosition);
     
     Serial.println("✓ Movement complete - L:" + String(leftCurrentPosition) + " R:" + String(rightCurrentPosition));
     
     // Update movement time for timeout tracking
     lastMovementTime = millis();  // NEW
     
     // Save positions to EEPROM
     savePositions();
   } else {
     Serial.println("❌ No movement - both steps are 0");
   }
 }
 
 void centerMotors() {
   Serial.println("Centering motors...");
   moveToPosition(config.centerPosition, config.centerPosition);
 }
 
 void startupAnimation() {
   if (isAnimating) return;
   isAnimating = true;
   
   enableMotors();  // NEW: Enable motors for animation
   Serial.println("Starting animation...");
   
   if (hasSecondMotor) {
     // Full dual motor animation
     for (int cycle = 0; cycle < 3; cycle++) {
       // Left up, right down
       moveToPosition(config.maxPosition, config.minPosition);
       delay(500);
       
       // Both center
       centerMotors();
       delay(300);
       
       // Left down, right up
       moveToPosition(config.minPosition, config.maxPosition);
       delay(500);
       
       // Both center
       centerMotors();
       delay(300);
     }
   } else {
     // Single motor animation
     Serial.println("⚠️ Single motor animation (right motor not connected)");
     for (int cycle = 0; cycle < 3; cycle++) {
       // Move to max
       moveToPosition(config.maxPosition, rightCurrentPosition);
       delay(500);
       
       // Move to center
       centerMotors();
       delay(300);
       
       // Move to min
       moveToPosition(config.minPosition, rightCurrentPosition);
       delay(500);
       
       // Move to center
       centerMotors();
       delay(300);
     }
   }
   
   // Final center
   centerMotors();
   isAnimating = false;
   lastMovementTime = millis();  // NEW: Update timeout tracking
 }
 
 void testMotors() {
   enableMotors();  // NEW: Enable motors for testing
   Serial.println("Testing motors - UP, DOWN, CENTER sequence...");
   
   // Move to MAX position
   Serial.println("🔧 Moving to MAX position");
   moveToPosition(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
   delay(1000);
   
   // Move to MIN position  
   Serial.println("🔧 Moving to MIN position");
   moveToPosition(config.minPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
   delay(1000);
   
   // Move to CENTER position
   Serial.println("🔧 Moving to CENTER position");
   centerMotors();
   
   Serial.println("✓ Motor test complete - UP, DOWN, CENTER");
 }
 
 void rawMotorTest() {
   Serial.println("=== RAW MOTOR PIN TEST ===");
   Serial.println("Testing pins directly without DRV8825 library");
   
   enableMotors();  // NEW: Enable motors for raw test
   
   // Test left motor pins
   Serial.println("Testing LEFT motor - DIR:" + String(config.leftDirPin) + " STEP:" + String(config.leftStepPin));
   for (int i = 0; i < 10; i++) {
     digitalWrite(config.leftDirPin, HIGH);
     delayMicroseconds(100);
     digitalWrite(config.leftStepPin, HIGH);
     delayMicroseconds(100);
     digitalWrite(config.leftStepPin, LOW);
     delayMicroseconds(100);
   }
   
   delay(500);
   
   if (hasSecondMotor) {
     // Test right motor pins  
     Serial.println("Testing RIGHT motor - DIR:" + String(config.rightDirPin) + " STEP:" + String(config.rightStepPin));
     for (int i = 0; i < 10; i++) {
       digitalWrite(config.rightDirPin, HIGH);
       delayMicroseconds(100);
       digitalWrite(config.rightStepPin, HIGH);
       delayMicroseconds(100);
       digitalWrite(config.rightStepPin, LOW);
       delayMicroseconds(100);
     }
   } else {
     Serial.println("⚠️ RIGHT motor not connected - skipping raw test");
   }
   
   lastMovementTime = millis();  // NEW: Update timeout tracking
   
   Serial.println("✓ Raw pin test complete");
   Serial.println("If motors didn't move, check:");
   Serial.println("1. DRV8825 power connections");
   Serial.println("2. Motor wiring");
   Serial.println("3. DRV8825 enable pin (should be LOW)");
 }
 
 void forceMoveStepper(DRV8825 &stepper, int steps) {
   if (steps == 0) return;
   
   stepper.setDirection(steps > 0 ? DRV8825_CLOCK_WISE : DRV8825_COUNTERCLOCK_WISE);
   
   for (int i = 0; i < abs(steps); i++) {
     stepper.step();
     delay(config.animationSpeed);
   }
 }
 
 void loadConfig() {
   EEPROM.get(CONFIG_ADDR, config);
   
   // VALIDATE CONFIG VALUES - if invalid, use defaults
   bool configCorrupted = false;
   
   if (config.leftDirPin < 0 || config.leftDirPin > 39) {
     config.leftDirPin = 4;
     configCorrupted = true;
     Serial.println("⚠️ Invalid leftDirPin in EEPROM, using default: 4");
   }
   
   if (config.leftStepPin < 0 || config.leftStepPin > 39) {
     config.leftStepPin = 5;
     configCorrupted = true;
     Serial.println("⚠️ Invalid leftStepPin in EEPROM, using default: 5");
   }
   
   if (config.rightDirPin < 0 || config.rightDirPin > 39) {
     config.rightDirPin = 6;
     configCorrupted = true;
     Serial.println("⚠️ Invalid rightDirPin in EEPROM, using default: 6");
   }
   
   if (config.rightStepPin < 0 || config.rightStepPin > 39) {
     config.rightStepPin = 7;
     configCorrupted = true;
     Serial.println("⚠️ Invalid rightStepPin in EEPROM, using default: 7");
   }
   
   if (config.pc817Pin < 0 || config.pc817Pin > 39) {
     config.pc817Pin = 14;
     configCorrupted = true;
     Serial.println("⚠️ Invalid pc817Pin in EEPROM, using default: 14");
   }
   
   if (config.enablePin < 0 || config.enablePin > 39) {  // NEW
     config.enablePin = 2;
     configCorrupted = true;
     Serial.println("⚠️ Invalid enablePin in EEPROM, using default: 2");
   }
   
   if (config.centerPosition < 0 || config.centerPosition > 320) {
     config.centerPosition = 160;
     configCorrupted = true;
     Serial.println("⚠️ Invalid centerPosition in EEPROM, using default: 160");
   }
   
   if (config.animationSpeed < 1 || config.animationSpeed > 100) {
     config.animationSpeed = 3;
     configCorrupted = true;
     Serial.println("⚠️ Invalid animationSpeed in EEPROM, using default: 3");
   }
   
   if (config.motorTimeout < 500 || config.motorTimeout > 10000) {  // NEW
     config.motorTimeout = 2000;
     configCorrupted = true;
     Serial.println("⚠️ Invalid motorTimeout in EEPROM, using default: 2000ms");
   }
   
   // Set other defaults
   config.maxPosition = 320;
   config.minPosition = 0;
   config.autoCenter = true;
   
   if (configCorrupted) {
     Serial.println("⚠️ EEPROM was corrupted - using default values");
     Serial.println("✓ Saving corrected config to EEPROM...");
     saveConfig();
   }
 }
 
 void saveConfig() {
   EEPROM.put(CONFIG_ADDR, config);
   EEPROM.commit();
   Serial.println("Configuration saved");
 }
 
 void loadPositions() {
   EEPROM.get(LEFT_POS_ADDR, leftCurrentPosition);
   EEPROM.get(RIGHT_POS_ADDR, rightCurrentPosition);
   
   bool positionsCorrupted = false;
   
   // VALIDATE POSITIONS - if invalid, set defaults
   if (leftCurrentPosition < config.minPosition || leftCurrentPosition > config.maxPosition) {
     leftCurrentPosition = config.centerPosition; // Default to center
     positionsCorrupted = true;
     Serial.println("⚠️ Invalid left position in EEPROM, reset to center: " + String(leftCurrentPosition));
   }
   
   if (rightCurrentPosition < config.minPosition || rightCurrentPosition > config.maxPosition) {
     rightCurrentPosition = config.centerPosition; // Default to center  
     positionsCorrupted = true;
     Serial.println("⚠️ Invalid right position in EEPROM, reset to center: " + String(rightCurrentPosition));
   }
   
   Serial.println("Loaded positions - L:" + String(leftCurrentPosition) + " R:" + String(rightCurrentPosition));
   
   // Save corrected positions
   if (positionsCorrupted) {
     Serial.println("✓ Saving corrected positions to EEPROM...");
     savePositions();
   }
 }
 
 void savePositions() {
   EEPROM.put(LEFT_POS_ADDR, leftCurrentPosition);
   EEPROM.put(RIGHT_POS_ADDR, rightCurrentPosition);
   EEPROM.commit();
 }