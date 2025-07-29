/*
 * HEADLIGHT CONTROLLER - NON-BLOCKING VERSION
 * 
 * ✅ FIXED: Now sends status updates DURING animations and movements
 * ✅ Bluetooth commands work while motors are moving
 * ✅ Real-time status updates every 500ms during operations
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
   int enablePin = 2;
   int centerPosition = 160;
   int maxPosition = 320;
   int minPosition = 0;
   bool autoCenter = true;
   int animationSpeed = 3;
   int motorTimeout = 2000;
 };
 
 // Animation states
 enum AnimationState {
   ANIM_IDLE,
   ANIM_MOVE_TO_MAX,
   ANIM_WAIT_AT_MAX,
   ANIM_MOVE_TO_CENTER1,
   ANIM_WAIT_AT_CENTER1,
   ANIM_MOVE_TO_MIN,
   ANIM_WAIT_AT_MIN,
   ANIM_MOVE_TO_CENTER2,
   ANIM_WAIT_AT_CENTER2,
   ANIM_COMPLETE
 };
 
 // Motor movement states
 enum MotorState {
   MOTOR_IDLE,
   MOTOR_MOVING,
   MOTOR_STEP_DELAY
 };
 
 // Global variables
 Config config;
 DRV8825 leftStepper;
 // DRV8825 rightStepper;  // UNCOMMENT when second motor is connected
 WebServer server(80);
 BluetoothSerial SerialBT;
 
 int leftCurrentPosition = 0;
 int rightCurrentPosition = 0;
 bool headlightsOn = false;
 bool lastHeadlightState = false;
 bool isAnimating = false;
 unsigned long lastMovementTime = 0;
 bool motorsEnabled = false;
 
 // Feature flag
 bool hasSecondMotor = false;
 
 // NON-BLOCKING ANIMATION VARIABLES
 AnimationState animState = ANIM_IDLE;
 unsigned long animTimer = 0;
 int animCycle = 0;
 const int maxAnimCycles = 3;
 
 // NON-BLOCKING MOTOR MOVEMENT VARIABLES
 MotorState leftMotorState = MOTOR_IDLE;
 MotorState rightMotorState = MOTOR_IDLE;
 int leftStepsRemaining = 0;
 int rightStepsRemaining = 0;
 int leftTargetPosition = 0;
 int rightTargetPosition = 0;
 unsigned long leftStepTimer = 0;
 unsigned long rightStepTimer = 0;
 bool leftDirection = true;  // true = up, false = down
 bool rightDirection = true;
 
 // STATUS UPDATE TIMER (non-blocking)
 unsigned long lastStatusUpdate = 0;
 const unsigned long statusUpdateInterval = 500; // Send status every 500ms
 
 // EEPROM addresses
 const int CONFIG_ADDR = 0;
 const int LEFT_POS_ADDR = sizeof(Config);
 const int RIGHT_POS_ADDR = sizeof(Config) + sizeof(int);
 
 // WiFi credentials
 const char* ssid = "HeadlightController";
 const char* password = "headlight123";
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
 
 // NON-BLOCKING FUNCTIONS
 void updateAnimation();
 void updateMotorMovement();
 void startNonBlockingAnimation();
 void moveToPositionNonBlocking(int leftTarget, int rightTarget);
 void moveStepsNonBlocking(int leftSteps, int rightSteps);
 void stepLeftMotor();
 void stepRightMotor();
 void enableMotors();
 void disableMotors();
 void checkMotorTimeout();
 
 // WEB HANDLERS
 void handleRoot();
 void handleGetConfig();
 void handleSetConfig();
 void handleGetStatus();
 void handleMove();
 void handleCenter();
 void handleAnimate();
 void handleTest();
 void handleMaxUp();
 void handleMaxDown();
 
 // UTILITY FUNCTIONS
 void loadConfig();
 void saveConfig();
 void loadPositions();
 void savePositions();
 
 void setup() {
   Serial.begin(115200);
   Serial.println("=====================================");
   Serial.println("🚗 NON-BLOCKING Headlight Controller");
   Serial.println("✅ Real-time status during animations");
   Serial.println("=====================================");
   
   // Initialize EEPROM
   EEPROM.begin(512);
   loadConfig();
   loadPositions();
   
   // Initialize enable pin
   pinMode(config.enablePin, OUTPUT);
   disableMotors();
   Serial.println("✓ Enable pin " + String(config.enablePin) + " initialized");
   
   // Initialize steppers
   leftStepper.begin(config.leftDirPin, config.leftStepPin);
   pinMode(config.leftDirPin, OUTPUT);
   pinMode(config.leftStepPin, OUTPUT);
   Serial.println("✓ LEFT stepper initialized");
   
   // Initialize PC817 pin
   pinMode(config.pc817Pin, INPUT_PULLUP);
   bool pinValue = digitalRead(config.pc817Pin);
   headlightsOn = !pinValue;
   Serial.println("✓ PC817 pin initialized, headlights: " + String(headlightsOn ? "ON" : "OFF"));
   
   // Start services
   setupWiFi();
   setupBluetooth();
   setupWebServer();
   
   Serial.println("=====================================");
   Serial.println("🎉 NON-BLOCKING SYSTEM READY!");
   Serial.println("📡 Status updates every 500ms");
   Serial.println("🎮 Commands work during animations");
   Serial.println("=====================================");
 }
 
 void loop() {
   unsigned long currentTime = millis();
   
   // Handle communication (NEVER BLOCKED)
   server.handleClient();
   handleBluetoothCommands();
   handleSerialCommands();
   
   // Update non-blocking animations
   updateAnimation();
   
   // Update non-blocking motor movements
   updateMotorMovement();
   
   // Check motor timeout
   checkMotorTimeout();
   
   // Send status updates periodically (even during animations!)
   if (currentTime - lastStatusUpdate >= statusUpdateInterval) {
     sendBluetoothStatusUpdate();
     lastStatusUpdate = currentTime;
   }
   
   // Check headlight state
   bool pinValue = digitalRead(config.pc817Pin);
   bool currentHeadlightState = !pinValue;
   
   if (currentHeadlightState != lastHeadlightState) {
     lastHeadlightState = currentHeadlightState;
     headlightsOn = currentHeadlightState;
     
     Serial.println("=== HEADLIGHT STATE CHANGE ===");
     Serial.println("Headlight state: " + String(headlightsOn ? "ON" : "OFF"));
     
     if (headlightsOn) {
       Serial.println("🔆 HEADLIGHTS TURNED ON");
       sendBluetoothStatus("headlights_on");
       moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
       // Start animation after a short delay
       animTimer = currentTime + 1000; // 1 second delay
       animState = ANIM_MOVE_TO_MAX;
       isAnimating = true;
     } else {
       Serial.println("🔅 HEADLIGHTS TURNED OFF");
       sendBluetoothStatus("headlights_off");
       if (config.autoCenter) {
         moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
       } else {
         moveToPositionNonBlocking(config.minPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
       }
     }
   }
   
   // Small delay to prevent excessive CPU usage
   delay(1);
 }
 
 // NON-BLOCKING ANIMATION UPDATE
 void updateAnimation() {
   if (!isAnimating || animState == ANIM_IDLE) return;
   
   unsigned long currentTime = millis();
   
   switch (animState) {
     case ANIM_MOVE_TO_MAX:
       if (currentTime >= animTimer) {
         moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.minPosition : rightCurrentPosition);
         animState = ANIM_WAIT_AT_MAX;
         animTimer = currentTime + 500; // Wait 500ms
       }
       break;
       
     case ANIM_WAIT_AT_MAX:
       if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE) {
         moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
         animState = ANIM_MOVE_TO_CENTER1;
         animTimer = currentTime + 300; // Wait 300ms
       }
       break;
       
     case ANIM_MOVE_TO_CENTER1:
       if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE) {
         moveToPositionNonBlocking(config.minPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
         animState = ANIM_WAIT_AT_MIN;
         animTimer = currentTime + 500; // Wait 500ms
       }
       break;
       
     case ANIM_WAIT_AT_MIN:
       if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE) {
         moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
         animState = ANIM_MOVE_TO_CENTER2;
         animTimer = currentTime + 300; // Wait 300ms
       }
       break;
       
     case ANIM_MOVE_TO_CENTER2:
       if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE) {
         animCycle++;
         if (animCycle >= maxAnimCycles) {
           // Animation complete
           moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
           animState = ANIM_COMPLETE;
           animTimer = currentTime + 500;
         } else {
           // Next cycle
           animState = ANIM_MOVE_TO_MAX;
           animTimer = currentTime + 200;
         }
       }
       break;
       
     case ANIM_COMPLETE:
       if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE) {
         isAnimating = false;
         animState = ANIM_IDLE;
         animCycle = 0;
         lastMovementTime = currentTime;
         Serial.println("✅ Animation completed (non-blocking)");
       }
       break;
   }
 }
 
 // NON-BLOCKING MOTOR MOVEMENT UPDATE
 void updateMotorMovement() {
   unsigned long currentTime = millis();
   
   // Update left motor
   if (leftMotorState == MOTOR_MOVING && leftStepsRemaining > 0) {
     if (currentTime >= leftStepTimer) {
       stepLeftMotor();
       leftStepTimer = currentTime + config.animationSpeed;
       leftStepsRemaining--;
       
       if (leftStepsRemaining <= 0) {
         leftMotorState = MOTOR_IDLE;
         Serial.println("✓ Left motor reached position: " + String(leftCurrentPosition));
       }
     }
   }
   
   // Update right motor (if connected)
   if (hasSecondMotor && rightMotorState == MOTOR_MOVING && rightStepsRemaining > 0) {
     if (currentTime >= rightStepTimer) {
       stepRightMotor();
       rightStepTimer = currentTime + config.animationSpeed;
       rightStepsRemaining--;
       
       if (rightStepsRemaining <= 0) {
         rightMotorState = MOTOR_IDLE;
         Serial.println("✓ Right motor reached position: " + String(rightCurrentPosition));
       }
     }
   }
   
   // Save positions periodically
   static unsigned long lastSave = 0;
   if (currentTime - lastSave > 1000) { // Save every second
     savePositions();
     lastSave = currentTime;
   }
 }
 
 // NON-BLOCKING MOVE TO POSITION
 void moveToPositionNonBlocking(int leftTarget, int rightTarget) {
   leftTarget = constrain(leftTarget, config.minPosition, config.maxPosition);
   rightTarget = constrain(rightTarget, config.minPosition, config.maxPosition);
   
   int leftSteps = leftTarget - leftCurrentPosition;
   int rightSteps = rightTarget - rightCurrentPosition;
   
   moveStepsNonBlocking(leftSteps, rightSteps);
 }
 
 // NON-BLOCKING MOVE STEPS
 void moveStepsNonBlocking(int leftSteps, int rightSteps) {
   if (leftSteps == 0 && rightSteps == 0) return;
   
   enableMotors();
   
   Serial.println("🔧 NON-BLOCKING Movement - L:" + String(leftSteps) + " R:" + String(rightSteps));
   
   // Setup left motor movement
   if (leftSteps != 0) {
     leftStepsRemaining = abs(leftSteps);
     leftDirection = leftSteps > 0;
     leftStepper.setDirection(leftDirection ? DRV8825_CLOCK_WISE : DRV8825_COUNTERCLOCK_WISE);
     leftMotorState = MOTOR_MOVING;
     leftStepTimer = millis();
   }
   
   // Setup right motor movement (if connected)
   if (hasSecondMotor && rightSteps != 0) {
     rightStepsRemaining = abs(rightSteps);
     rightDirection = rightSteps > 0;
     // rightStepper.setDirection(rightDirection ? DRV8825_CLOCK_WISE : DRV8825_COUNTERCLOCK_WISE);
     rightMotorState = MOTOR_MOVING;
     rightStepTimer = millis();
   }
   
   lastMovementTime = millis();
 }
 
 // STEP INDIVIDUAL MOTORS
 void stepLeftMotor() {
   leftStepper.step();
   leftCurrentPosition += leftDirection ? 1 : -1;
   leftCurrentPosition = constrain(leftCurrentPosition, config.minPosition, config.maxPosition);
 }
 
 void stepRightMotor() {
   if (hasSecondMotor) {
     // rightStepper.step();  // UNCOMMENT when second motor connected
     rightCurrentPosition += rightDirection ? 1 : -1;
     rightCurrentPosition = constrain(rightCurrentPosition, config.minPosition, config.maxPosition);
   }
 }
 
 // START NON-BLOCKING ANIMATION
 void startNonBlockingAnimation() {
   if (isAnimating) {
     Serial.println("⚠️ Animation already running");
     return;
   }
   
   Serial.println("✨ Starting NON-BLOCKING animation");
   isAnimating = true;
   animState = ANIM_MOVE_TO_MAX;
   animCycle = 0;
   animTimer = millis() + 100; // Small delay before starting
 }
 
 // MOTOR CONTROL FUNCTIONS
 void enableMotors() {
   if (!motorsEnabled) {
     digitalWrite(config.enablePin, LOW);
     motorsEnabled = true;
     lastMovementTime = millis();
     Serial.println("🔥 Motors ENABLED");
     delay(50);
   }
 }
 
 void disableMotors() {
   if (motorsEnabled) {
     digitalWrite(config.enablePin, HIGH);
     motorsEnabled = false;
     Serial.println("❄️ Motors DISABLED");
   }
 }
 
 void checkMotorTimeout() {
   if (motorsEnabled && !isAnimating && leftMotorState == MOTOR_IDLE && rightMotorState == MOTOR_IDLE) {
     if (millis() - lastMovementTime > config.motorTimeout) {
       disableMotors();
     }
   }
 }
 
 // BLUETOOTH COMMAND PROCESSING
 void handleBluetoothCommands() {
   if (SerialBT.available()) {
     String command = SerialBT.readStringUntil('\n');
     command.trim();
     
     if (command.length() > 0) {
       processBluetoothCommand(command);
     }
   }
 }
 
 void processBluetoothCommand(String command) {
   Serial.println("BT Command: " + command);
   
   // Simple commands
   command.toLowerCase();
   if (command == "test") {
     Serial.println("🔧 NON-BLOCKING TEST");
     moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
     return;
   }
   else if (command == "center") {
     moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
     return;
   }
   else if (command == "animate") {
     startNonBlockingAnimation();
     return;
   }
   else if (command == "status") {
     sendBluetoothStatusUpdate();
     return;
   }
   
   // JSON commands
   DynamicJsonDocument doc(1024);
   DeserializationError error = deserializeJson(doc, command);
   
   if (error) {
     sendBluetoothError("Invalid JSON command");
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
       moveStepsNonBlocking(steps, steps);
     } else if (direction == "down") {
       moveStepsNonBlocking(-steps, -steps);
     } else if (direction == "left_up") {
       moveStepsNonBlocking(steps, 0);
     } else if (direction == "left_down") {
       moveStepsNonBlocking(-steps, 0);
     } else if (direction == "right_up") {
       moveStepsNonBlocking(0, steps);
     } else if (direction == "right_down") {
       moveStepsNonBlocking(0, -steps);
     }
     
     sendBluetoothSuccess("Movement started (non-blocking)");
   }
   else if (action == "center") {
     moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
     sendBluetoothSuccess("Centering motors (non-blocking)");
   }
   else if (action == "animate") {
     startNonBlockingAnimation();
     sendBluetoothSuccess("Animation started (non-blocking)");
   }
   else if (action == "test") {
     moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
     sendBluetoothSuccess("Test started (non-blocking)");
   }
   else if (action == "position_set") {
     if (doc.containsKey("left") && doc.containsKey("right")) {
       int leftPos = doc["left"];
       int rightPos = doc["right"];
       moveToPositionNonBlocking(leftPos, rightPos);
       sendBluetoothSuccess("Position set (non-blocking)");
     } else {
       sendBluetoothError("Missing left or right position");
     }
   }
   else {
     sendBluetoothError("Unknown action: " + action);
   }
 }
 
 // BLUETOOTH STATUS UPDATES
 void sendBluetoothStatusUpdate() {
   DynamicJsonDocument doc(1024);
   doc["type"] = "status";
   doc["leftPosition"] = leftCurrentPosition;
   doc["rightPosition"] = rightCurrentPosition;
   doc["headlightsOn"] = headlightsOn;
   doc["isAnimating"] = isAnimating;
   doc["motorsEnabled"] = motorsEnabled;
   doc["leftMotorMoving"] = (leftMotorState == MOTOR_MOVING);
   doc["rightMotorMoving"] = (rightMotorState == MOTOR_MOVING);
   doc["animationState"] = animState;
   doc["centerPosition"] = config.centerPosition;
   doc["maxPosition"] = config.maxPosition;
   doc["minPosition"] = config.minPosition;
   
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
 
 // SERIAL COMMANDS
 void handleSerialCommands() {
   if (Serial.available()) {
     String command = Serial.readStringUntil('\n');
     command.trim();
     command.toLowerCase();
     
     if (command == "test") {
       moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
     }
     else if (command == "center") {
       moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
     }
     else if (command == "animate") {
       startNonBlockingAnimation();
     }
     else if (command == "status") {
       Serial.println("=== NON-BLOCKING STATUS ===");
       Serial.println("Left Position: " + String(leftCurrentPosition) + " (Moving: " + String(leftMotorState == MOTOR_MOVING ? "YES" : "NO") + ")");
       Serial.println("Right Position: " + String(rightCurrentPosition) + " (Moving: " + String(rightMotorState == MOTOR_MOVING ? "YES" : "NO") + ")");
       Serial.println("Animation: " + String(isAnimating ? "RUNNING" : "STOPPED") + " (State: " + String(animState) + ")");
       Serial.println("Motors: " + String(motorsEnabled ? "ENABLED" : "DISABLED"));
     }
     else if (command == "help") {
       Serial.println("=== NON-BLOCKING COMMANDS ===");
       Serial.println("test - Start motor test (non-blocking)");
       Serial.println("center - Center motors (non-blocking)");
       Serial.println("animate - Start animation (non-blocking)");
       Serial.println("status - Show real-time status");
       Serial.println("✅ All commands work during animations!");
     }
   }
 }
 
 // WEB SERVER SETUP
 void setupWiFi() {
   WiFi.mode(WIFI_AP);
   WiFi.softAP(ssid, password);
   Serial.println("WiFi AP started: " + String(ssid));
 }
 
 void setupBluetooth() {
   SerialBT.begin(btDeviceName);
   Serial.println("Bluetooth started: " + String(btDeviceName));
 }
 
 void setupWebServer() {
   server.on("/", handleRoot);
   server.on("/api/status", HTTP_GET, handleGetStatus);
   server.on("/api/move", HTTP_POST, handleMove);
   server.on("/api/center", HTTP_POST, handleCenter);
   server.on("/api/animate", HTTP_POST, handleAnimate);
   server.on("/api/test", HTTP_POST, handleTest);
   
   server.begin();
   Serial.println("Web server started");
 }
 
 // WEB HANDLERS (simplified)
 void handleRoot() {
   String html = "<!DOCTYPE html><html><head><title>Non-Blocking Controller</title></head>";
   html += "<body><h1>Non-Blocking Headlight Controller</h1>";
   html += "<p>✅ Real-time status updates during animations</p>";
   html += "<button onclick=\"fetch('/api/animate', {method: 'POST'})\">Start Animation</button>";
   html += "<button onclick=\"fetch('/api/center', {method: 'POST'})\">Center</button>";
   html += "<button onclick=\"fetch('/api/test', {method: 'POST'})\">Test</button>";
   html += "</body></html>";
   
   server.send(200, "text/html", html);
 }
 
 void handleGetStatus() {
   DynamicJsonDocument doc(1024);
   doc["leftPosition"] = leftCurrentPosition;
   doc["rightPosition"] = rightCurrentPosition;
   doc["headlightsOn"] = headlightsOn;
   doc["isAnimating"] = isAnimating;
   doc["motorsEnabled"] = motorsEnabled;
   doc["leftMotorMoving"] = (leftMotorState == MOTOR_MOVING);
   doc["rightMotorMoving"] = (rightMotorState == MOTOR_MOVING);
   
   String response;
   serializeJson(doc, response);
   server.send(200, "application/json", response);
 }
 
 void handleMove() {
   DynamicJsonDocument doc(1024);
   deserializeJson(doc, server.arg("plain"));
   
   String direction = doc["direction"];
   int steps = 20;
   
   if (direction == "up") {
     moveStepsNonBlocking(steps, steps);
   } else if (direction == "down") {
     moveStepsNonBlocking(-steps, -steps);
   }
   
   server.send(200, "text/plain", "OK");
 }
 
 void handleCenter() {
   moveToPositionNonBlocking(config.centerPosition, config.centerPosition);
   server.send(200, "text/plain", "OK");
 }
 
 void handleAnimate() {
   startNonBlockingAnimation();
   server.send(200, "text/plain", "OK");
 }
 
 void handleTest() {
   moveToPositionNonBlocking(config.maxPosition, hasSecondMotor ? config.maxPosition : rightCurrentPosition);
   server.send(200, "text/plain", "OK");
 }
 
 // CONFIG FUNCTIONS
 void loadConfig() {
   EEPROM.get(CONFIG_ADDR, config);
   
   // Validate and set defaults if needed
   if (config.leftDirPin < 0 || config.leftDirPin > 39) config.leftDirPin = 4;
   if (config.leftStepPin < 0 || config.leftStepPin > 39) config.leftStepPin = 5;
   if (config.enablePin < 0 || config.enablePin > 39) config.enablePin = 2;
   if (config.centerPosition < 0 || config.centerPosition > 320) config.centerPosition = 160;
   if (config.animationSpeed < 1 || config.animationSpeed > 100) config.animationSpeed = 3;
   if (config.motorTimeout < 500 || config.motorTimeout > 10000) config.motorTimeout = 2000;
   
   config.maxPosition = 320;
   config.minPosition = 0;
   config.autoCenter = true;
 }
 
 void saveConfig() {
   EEPROM.put(CONFIG_ADDR, config);
   EEPROM.commit();
 }
 
 void loadPositions() {
   EEPROM.get(LEFT_POS_ADDR, leftCurrentPosition);
   EEPROM.get(RIGHT_POS_ADDR, rightCurrentPosition);
   
   if (leftCurrentPosition < 0 || leftCurrentPosition > 320) leftCurrentPosition = config.centerPosition;
   if (rightCurrentPosition < 0 || rightCurrentPosition > 320) rightCurrentPosition = config.centerPosition;
 }
 
 void savePositions() {
   EEPROM.put(LEFT_POS_ADDR, leftCurrentPosition);
   EEPROM.put(RIGHT_POS_ADDR, rightCurrentPosition);
   EEPROM.commit();
 }