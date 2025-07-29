/*
 * HEADLIGHT CONTROLLER - FIXED CAN + SAFE EEPROM
 * 
 * ✅ CAN headlight detection (ID 531, byte[0] = 0x04 = ON)
 * ✅ Safe EEPROM with error handling
 * ✅ Works with or without stepper drivers
 * ✅ Persistent configuration storage
 */

#include <ESP32-TWAI-CAN.hpp>
#include <EEPROM.h>
#include <ArduinoJson.h>
#include <BluetoothSerial.h>

// CAN Configuration
#define CAN_TX 21
#define CAN_RX 22

// Set to true when you have stepper drivers connected
#define STEPPERS_CONNECTED true

// Configuration structure
struct Config {
  uint32_t magic = 0x12345678; // Magic number to validate EEPROM
  int leftDirPin = 4;
  int leftStepPin = 5;
  int rightDirPin = 17;
  int rightStepPin = 16;
  int enablePin = 2;
  int maxPosition = 320;
  int minPosition = 0;
  int animationSpeed = 3;
  int motorTimeout = 3000;
  
  // Default positions when headlights are ON
  int leftDefaultPosition = 200;
  int rightDefaultPosition = 200;
  
  // CAN Configuration - FIXED VALUES
  uint32_t headlightCanId = 0x531;
  int headlightByteIndex = 0;        // Check byte[0]
  uint8_t headlightOnValue = 0x04;   // 0x04 = lights ON
  uint8_t headlightOffValue = 0x03;  // 0x03 = lights OFF
};

// Position storage structure
struct PositionData {
  uint32_t magic = 0x87654321; // Magic number to validate positions
  int leftPosition = 160;
  int rightPosition = 160;
};

// Animation states
enum AnimationState {
  ANIM_IDLE,
  ANIM_MOVE_TO_MAX_UP,
  ANIM_WAIT_AT_MAX_UP,
  ANIM_MOVE_TO_MAX_DOWN,
  ANIM_WAIT_AT_MAX_DOWN,
  ANIM_MOVE_TO_DEFAULT,
  ANIM_COMPLETE
};

// Motor movement states
enum MotorState {
  MOTOR_IDLE,
  MOTOR_MOVING
};

// Global variables
Config config;
PositionData positions;
BluetoothSerial SerialBT;

// Motor variables
int leftCurrentPosition = 160;
int rightCurrentPosition = 160;
bool headlightsOn = false;
bool lastHeadlightState = false;
bool isAnimating = false;
unsigned long lastMovementTime = 0;
bool motorsEnabled = false;

// Animation variables
AnimationState animState = ANIM_IDLE;
unsigned long animTimer = 0;

// Motor movement variables
MotorState leftMotorState = MOTOR_IDLE;
MotorState rightMotorState = MOTOR_IDLE;
int leftStepsRemaining = 0;
int rightStepsRemaining = 0;
unsigned long leftStepTimer = 0;
unsigned long rightStepTimer = 0;
bool leftDirection = true;
bool rightDirection = true;

// CAN variables
CanFrame rxFrame;
bool canInitialized = false;
unsigned long lastCanCheck = 0;
unsigned long frameCount = 0;

// Status update timer
unsigned long lastStatusUpdate = 0;
const unsigned long statusUpdateInterval = 500;

// EEPROM addresses
const int CONFIG_ADDR = 0;
const int POSITION_ADDR = sizeof(Config);

const char* btDeviceName = "HeadlightController";

// Function declarations
void setupBluetooth();
void setupCAN();
void setupSteppers();
void handleBluetoothCommands();
void processBluetoothCommand(String command);
void sendBluetoothStatusUpdate();
void sendBluetoothSuccess(String message);
void sendBluetoothError(String error);

void updateCanMonitoring();
void processCanFrame(CanFrame &frame);
bool checkHeadlightState(CanFrame &frame);

void updateAnimation();
void updateMotorMovement();
void startAnimation();
void moveToPositionNonBlocking(int leftTarget, int rightTarget);
void moveStepsNonBlocking(int leftSteps, int rightSteps);
void stepLeftMotor();
void stepRightMotor();
void enableMotors();
void disableMotors();
void checkMotorTimeout();

// Safe EEPROM functions
bool loadConfig();
bool saveConfig();
bool loadPositions();
bool savePositions();
void initializeEEPROM();

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("🚗 Headlight Controller Starting...");
  Serial.printf("🔧 Steppers: %s\n", STEPPERS_CONNECTED ? "ENABLED" : "VIRTUAL");
  
  // Initialize EEPROM safely
  initializeEEPROM();
  
  setupSteppers();
  setupBluetooth();
  setupCAN();
  
  Serial.println("✅ System Ready");
  Serial.printf("Positions - L:%d R:%d\n", leftCurrentPosition, rightCurrentPosition);
  Serial.printf("Defaults - L:%d R:%d\n", config.leftDefaultPosition, config.rightDefaultPosition);
  Serial.printf("🔍 CAN Detection - ID:0x%03X Byte[%d] ON:0x%02X OFF:0x%02X\n", 
    config.headlightCanId, config.headlightByteIndex, 
    config.headlightOnValue, config.headlightOffValue);
  Serial.println("📱 Ready for Bluetooth connection");
}

void loop() {
  handleBluetoothCommands();
  updateCanMonitoring();
  updateAnimation();
  updateMotorMovement();
  checkMotorTimeout();
  
  // Send status updates
  if (millis() - lastStatusUpdate >= statusUpdateInterval) {
    if (SerialBT.hasClient()) {
      sendBluetoothStatusUpdate();
    }
    lastStatusUpdate = millis();
  }
  
  // Save positions periodically (both motors)
  static unsigned long lastSave = 0;
  if (millis() - lastSave > 2000) { // Every 2 seconds
    savePositions();
    lastSave = millis();
  }
  
  delay(1);
}

// ==============================================
// SAFE EEPROM FUNCTIONS
// ==============================================

void initializeEEPROM() {
  Serial.println("💾 Initializing EEPROM...");
  
  if (!EEPROM.begin(512)) {
    Serial.println("❌ EEPROM begin failed - using defaults");
    return;
  }
  
  // Load configuration
  if (!loadConfig()) {
    Serial.println("⚠️ Config invalid - saving defaults");
    saveConfig();
  }
  
  // Load positions
  if (!loadPositions()) {
    Serial.println("⚠️ Positions invalid - saving defaults");
    savePositions();
  }
  
  Serial.println("✅ EEPROM initialized");
}

bool loadConfig() {
  Config tempConfig;
  
  try {
    EEPROM.get(CONFIG_ADDR, tempConfig);
    
    // Check magic number
    if (tempConfig.magic != 0x12345678) {
      Serial.println("💾 Config magic invalid - using defaults");
      return false;
    }
    
    // Validate ranges
    if (tempConfig.leftDefaultPosition < 0 || tempConfig.leftDefaultPosition > 320 ||
        tempConfig.rightDefaultPosition < 0 || tempConfig.rightDefaultPosition > 320 ||
        tempConfig.animationSpeed < 1 || tempConfig.animationSpeed > 50 ||
        tempConfig.motorTimeout < 500 || tempConfig.motorTimeout > 20000) {
      Serial.println("💾 Config values invalid - using defaults");
      return false;
    }
    
    // Copy valid config
    config = tempConfig;
    Serial.printf("💾 Config loaded - L:%d R:%d Speed:%d Timeout:%d\n", 
      config.leftDefaultPosition, config.rightDefaultPosition,
      config.animationSpeed, config.motorTimeout);
    return true;
    
  } catch (...) {
    Serial.println("💾 Config load exception - using defaults");
    return false;
  }
}

bool saveConfig() {
  try {
    config.magic = 0x12345678; // Ensure magic is set
    EEPROM.put(CONFIG_ADDR, config);
    
    if (EEPROM.commit()) {
      Serial.println("💾 Config saved");
      return true;
    } else {
      Serial.println("💾 Config save failed");
      return false;
    }
  } catch (...) {
    Serial.println("💾 Config save exception");
    return false;
  }
}

bool loadPositions() {
  PositionData tempPositions;
  
  try {
    EEPROM.get(POSITION_ADDR, tempPositions);
    
    // Check magic number
    if (tempPositions.magic != 0x87654321) {
      Serial.println("💾 Position magic invalid - using center");
      return false;
    }
    
    // Validate ranges
    if (tempPositions.leftPosition < 0 || tempPositions.leftPosition > 320 ||
        tempPositions.rightPosition < 0 || tempPositions.rightPosition > 320) {
      Serial.println("💾 Position values invalid - using center");
      return false;
    }
    
    // Copy valid positions
    positions = tempPositions;
    leftCurrentPosition = positions.leftPosition;
    rightCurrentPosition = positions.rightPosition;
    Serial.printf("💾 Positions loaded - L:%d R:%d\n", leftCurrentPosition, rightCurrentPosition);
    return true;
    
  } catch (...) {
    Serial.println("💾 Position load exception - using center");
    return false;
  }
}

bool savePositions() {
  try {
    positions.magic = 0x87654321; // Ensure magic is set
    positions.leftPosition = leftCurrentPosition;
    positions.rightPosition = rightCurrentPosition;
    
    EEPROM.put(POSITION_ADDR, positions);
    
    if (EEPROM.commit()) {
      return true; // Silent save for periodic saves
    } else {
      return false;
    }
  } catch (...) {
    return false;
  }
}

// ==============================================
// STEPPER FUNCTIONS
// ==============================================

void setupSteppers() {
  if (STEPPERS_CONNECTED) {
    Serial.println("🔧 Initializing real steppers...");
    pinMode(config.enablePin, OUTPUT);
    pinMode(config.leftDirPin, OUTPUT);
    pinMode(config.leftStepPin, OUTPUT);
    pinMode(config.rightDirPin, OUTPUT);
    pinMode(config.rightStepPin, OUTPUT);
    disableMotors();
    Serial.println("✅ Real steppers initialized");
  } else {
    Serial.println("🔧 Using virtual steppers");
  }
}

// ==============================================
// CAN FUNCTIONS
// ==============================================

void setupCAN() {
  Serial.println("🔌 Starting CAN...");
  
  twai_filter_config_t filterConfig = {
    .acceptance_code = config.headlightCanId << 21,
    .acceptance_mask = 0x1FFFFFFF,
    .single_filter = true
  };
  
  ESP32Can.setPins(CAN_TX, CAN_RX);
  ESP32Can.setRxQueueSize(20);
  ESP32Can.setTxQueueSize(5);
  
  if (ESP32Can.begin(ESP32Can.convertSpeed(100), CAN_TX, CAN_RX, 10, 20, &filterConfig)) {
    Serial.printf("✅ CAN initialized (ID: 0x%03X)\n", config.headlightCanId);
    canInitialized = true;
  } else {
    Serial.println("❌ CAN initialization failed");
    canInitialized = false;
  }
}

void updateCanMonitoring() {
  if (!canInitialized) return;
  
  while (ESP32Can.readFrame(rxFrame, 5)) {
    frameCount++;
    processCanFrame(rxFrame);
    
    // Show received frames for debugging
    Serial.printf("🔌 RX: ID=0x%03X Data=", rxFrame.identifier);
    for (int i = 0; i < rxFrame.data_length_code; i++) {
      Serial.printf("%02X ", rxFrame.data[i]);
    }
    Serial.println();
  }
  
  // Check for timeout (no CAN frames = lights probably off)
  if (millis() - lastCanCheck > 5000 && headlightsOn) {
    Serial.println("🔅 CAN timeout - assuming lights OFF");
    headlightsOn = false;
    lastHeadlightState = false;
  }
}

void processCanFrame(CanFrame &frame) {
  if (frame.identifier == config.headlightCanId) {
    lastCanCheck = millis();
    bool newHeadlightState = checkHeadlightState(frame);
    
    Serial.printf("🔍 Frame 0x%03X: Byte[%d]=0x%02X, Looking for ON:0x%02X OFF:0x%02X, State: %s\n", 
      frame.identifier, config.headlightByteIndex, 
      frame.data[config.headlightByteIndex], 
      config.headlightOnValue, config.headlightOffValue,
      newHeadlightState ? "ON" : "OFF");
    
    if (newHeadlightState != lastHeadlightState) {
      lastHeadlightState = newHeadlightState;
      headlightsOn = newHeadlightState;
      
      if (headlightsOn) {
        Serial.println("🔆 HEADLIGHTS ON - Starting animation");
        startAnimation();
      } else {
        Serial.println("🔅 HEADLIGHTS OFF - Motors stay in position");
      }
    }
  }
}

bool checkHeadlightState(CanFrame &frame) {
  if (frame.data_length_code <= config.headlightByteIndex) return false;
  
  uint8_t byteValue = frame.data[config.headlightByteIndex];
  
  // Check for ON value
  if (byteValue == config.headlightOnValue) {
    return true;
  }
  
  // Check for OFF value  
  if (byteValue == config.headlightOffValue) {
    return false;
  }
  
  // Unknown value - maintain current state
  return headlightsOn;
}

// ==============================================
// MOTOR FUNCTIONS
// ==============================================

void updateAnimation() {
  if (!isAnimating || animState == ANIM_IDLE) return;
  
  unsigned long currentTime = millis();
  
  switch (animState) {
    case ANIM_MOVE_TO_MAX_UP:
      if (currentTime >= animTimer) {
        Serial.println("🎬 Animation: Moving to MAX UP");
        moveToPositionNonBlocking(config.maxPosition, config.maxPosition);
        animState = ANIM_WAIT_AT_MAX_UP;
        animTimer = currentTime + 800;
      }
      break;
      
    case ANIM_WAIT_AT_MAX_UP:
      if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE && rightMotorState == MOTOR_IDLE) {
        Serial.println("🎬 Animation: Moving to MAX DOWN");
        moveToPositionNonBlocking(config.minPosition, config.minPosition);
        animState = ANIM_MOVE_TO_MAX_DOWN;
        animTimer = currentTime + 800;
      }
      break;
      
    case ANIM_MOVE_TO_MAX_DOWN:
      if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE && rightMotorState == MOTOR_IDLE) {
        animState = ANIM_WAIT_AT_MAX_DOWN;
        animTimer = currentTime + 800;
      }
      break;
      
    case ANIM_WAIT_AT_MAX_DOWN:
      if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE && rightMotorState == MOTOR_IDLE) {
        Serial.println("🎬 Animation: Moving to DEFAULT positions");
        moveToPositionNonBlocking(config.leftDefaultPosition, config.rightDefaultPosition);
        animState = ANIM_MOVE_TO_DEFAULT;
        animTimer = currentTime + 500;
      }
      break;
      
    case ANIM_MOVE_TO_DEFAULT:
      if (currentTime >= animTimer && leftMotorState == MOTOR_IDLE && rightMotorState == MOTOR_IDLE) {
        animState = ANIM_COMPLETE;
        animTimer = currentTime + 1000;
      }
      break;
      
    case ANIM_COMPLETE:
      if (currentTime >= animTimer) {
        isAnimating = false;
        animState = ANIM_IDLE;
        lastMovementTime = currentTime;
        Serial.println("✅ Animation complete - motors at default positions");
      }
      break;
  }
}

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
        Serial.printf("✓ Left motor reached position: %d\n", leftCurrentPosition);
      }
    }
  }
  
  // Update right motor
  if (rightMotorState == MOTOR_MOVING && rightStepsRemaining > 0) {
    if (currentTime >= rightStepTimer) {
      stepRightMotor();
      rightStepTimer = currentTime + config.animationSpeed;
      rightStepsRemaining--;
      
      if (rightStepsRemaining <= 0) {
        rightMotorState = MOTOR_IDLE;
        Serial.printf("✓ Right motor reached position: %d\n", rightCurrentPosition);
      }
    }
  }
}

void moveToPositionNonBlocking(int leftTarget, int rightTarget) {
  leftTarget = constrain(leftTarget, config.minPosition, config.maxPosition);
  rightTarget = constrain(rightTarget, config.minPosition, config.maxPosition);
  
  int leftSteps = leftTarget - leftCurrentPosition;
  int rightSteps = rightTarget - rightCurrentPosition;
  
  Serial.printf("🔧 Move: L:%d→%d (%+d) R:%d→%d (%+d)\n", 
    leftCurrentPosition, leftTarget, leftSteps,
    rightCurrentPosition, rightTarget, rightSteps);
  
  moveStepsNonBlocking(leftSteps, rightSteps);
}

void moveStepsNonBlocking(int leftSteps, int rightSteps) {
  if (leftSteps == 0 && rightSteps == 0) return;
  
  enableMotors();
  
  // Setup left motor movement
  if (leftSteps != 0) {
    leftStepsRemaining = abs(leftSteps);
    leftDirection = leftSteps > 0;
    leftMotorState = MOTOR_MOVING;
    leftStepTimer = millis();
    
    if (STEPPERS_CONNECTED) {
      digitalWrite(config.leftDirPin, leftDirection ? LOW : HIGH);
    }
  }
  
  // Setup right motor movement
  if (rightSteps != 0) {
    rightStepsRemaining = abs(rightSteps);
    rightDirection = rightSteps > 0;
    rightMotorState = MOTOR_MOVING;
    rightStepTimer = millis();
    
    if (STEPPERS_CONNECTED) {
      digitalWrite(config.rightDirPin, rightDirection ? LOW : HIGH);
    }
  }
  
  lastMovementTime = millis();
}

void stepLeftMotor() {
  if (STEPPERS_CONNECTED) {
    digitalWrite(config.leftStepPin, HIGH);
    delayMicroseconds(2);
    digitalWrite(config.leftStepPin, LOW);
    delayMicroseconds(2);
  }
  
  leftCurrentPosition += leftDirection ? 1 : -1;
  leftCurrentPosition = constrain(leftCurrentPosition, config.minPosition, config.maxPosition);
}

void stepRightMotor() {
  if (STEPPERS_CONNECTED) {
    digitalWrite(config.rightStepPin, HIGH);
    delayMicroseconds(2);
    digitalWrite(config.rightStepPin, LOW);
    delayMicroseconds(2);
  }
  
  rightCurrentPosition += rightDirection ? 1 : -1;
  rightCurrentPosition = constrain(rightCurrentPosition, config.minPosition, config.maxPosition);
}

void startAnimation() {
  if (isAnimating) return;
  
  Serial.println("✨ Starting animation sequence: MAX UP → MAX DOWN → DEFAULT");
  isAnimating = true;
  animState = ANIM_MOVE_TO_MAX_UP;
  animTimer = millis() + 100;
}

void enableMotors() {
  if (!motorsEnabled) {
    if (STEPPERS_CONNECTED) {
      digitalWrite(config.enablePin, LOW);
    }
    motorsEnabled = true;
    lastMovementTime = millis();
    Serial.println("🔥 Motors ENABLED");
  }
}

void disableMotors() {
  if (motorsEnabled) {
    if (STEPPERS_CONNECTED) {
      digitalWrite(config.enablePin, HIGH);
    }
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

// ==============================================
// BLUETOOTH FUNCTIONS
// ==============================================

void setupBluetooth() {
  Serial.println("📱 Starting Bluetooth...");
  
  if (!SerialBT.begin(btDeviceName)) {
    Serial.println("❌ Bluetooth failed");
    return;
  }
  
  SerialBT.enableSSP();
  Serial.printf("✅ Bluetooth ready: %s\n", btDeviceName);
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

void processBluetoothCommand(String command) {
  String cmdLower = command;
  cmdLower.toLowerCase();
  
  if (cmdLower == "status") {
    sendBluetoothStatusUpdate();
    return;
  }
  
  DynamicJsonDocument doc(1024);
  DeserializationError error = deserializeJson(doc, command);
  
  if (error) {
    sendBluetoothError("Invalid JSON");
    return;
  }
  
  String action = doc["action"];
  
  if (action == "status") {
    sendBluetoothStatusUpdate();
  }
  else if (action == "move_left") {
    int steps = doc.containsKey("steps") ? doc["steps"] : 20;
    moveStepsNonBlocking(steps, 0);
    sendBluetoothSuccess("Left motor moving");
  }
  else if (action == "move_right") {
    int steps = doc.containsKey("steps") ? doc["steps"] : 20;
    moveStepsNonBlocking(0, steps);
    sendBluetoothSuccess("Right motor moving");
  }
  else if (action == "move_both") {
    int steps = doc.containsKey("steps") ? doc["steps"] : 20;
    moveStepsNonBlocking(steps, steps);
    sendBluetoothSuccess("Both motors moving");
  }
  else if (action == "position_set") {
    if (doc.containsKey("left") && doc.containsKey("right")) {
      int leftPos = doc["left"];
      int rightPos = doc["right"];
      moveToPositionNonBlocking(leftPos, rightPos);
    } else if (doc.containsKey("left")) {
      int leftPos = doc["left"];
      moveToPositionNonBlocking(leftPos, rightCurrentPosition);
    } else if (doc.containsKey("right")) {
      int rightPos = doc["right"];
      moveToPositionNonBlocking(leftCurrentPosition, rightPos);
    }
    sendBluetoothSuccess("Position set");
  }
  else if (action == "max_up") {
    moveToPositionNonBlocking(config.maxPosition, config.maxPosition);
    sendBluetoothSuccess("Moving to max");
  }
  else if (action == "max_down") {
    moveToPositionNonBlocking(config.minPosition, config.minPosition);
    sendBluetoothSuccess("Moving to min");
  }
  else if (action == "animate") {
    startAnimation();
    sendBluetoothSuccess("Animation started");
  }
  else if (action == "center") {
    moveToPositionNonBlocking(config.leftDefaultPosition, config.rightDefaultPosition);
    sendBluetoothSuccess("Moving to center (default) positions");
  }
  else if (action == "config_set") {
    bool changed = false;
    if (doc.containsKey("left_default")) {
      config.leftDefaultPosition = constrain((int)doc["left_default"], 0, 320);
      changed = true;
    }
    if (doc.containsKey("right_default")) {
      config.rightDefaultPosition = constrain((int)doc["right_default"], 0, 320);
      changed = true;
    }
    if (doc.containsKey("animation_speed")) {
      config.animationSpeed = constrain((int)doc["animation_speed"], 1, 20);
      changed = true;
    }
    if (doc.containsKey("motor_timeout")) {
      config.motorTimeout = constrain((int)doc["motor_timeout"], 1000, 10000);
      changed = true;
    }
    if (changed) {
      saveConfig(); // Save to EEPROM
      sendBluetoothSuccess("Configuration saved to EEPROM");
    } else {
      sendBluetoothError("No valid config parameters");
    }
  }
  else if (action == "config_get") {
    DynamicJsonDocument response(512);
    response["type"] = "config";
    response["left_default"] = config.leftDefaultPosition;
    response["right_default"] = config.rightDefaultPosition;
    response["animation_speed"] = config.animationSpeed;
    response["motor_timeout"] = config.motorTimeout;
    response["max_position"] = config.maxPosition;
    response["min_position"] = config.minPosition;
    
    String responseStr;
    serializeJson(response, responseStr);
    SerialBT.println(responseStr);
  }
  else {
    sendBluetoothError("Unknown action: " + action);
  }
}

void sendBluetoothStatusUpdate() {
  if (!SerialBT.hasClient()) return;
  
  DynamicJsonDocument doc(512);
  doc["type"] = "status";
  doc["leftPosition"] = leftCurrentPosition;
  doc["rightPosition"] = rightCurrentPosition;
  doc["headlightsOn"] = headlightsOn;
  doc["isAnimating"] = isAnimating;
  doc["motorsEnabled"] = motorsEnabled;
  doc["leftMoving"] = (leftMotorState == MOTOR_MOVING);
  doc["rightMoving"] = (rightMotorState == MOTOR_MOVING);
  doc["canInitialized"] = canInitialized;
  doc["frameCount"] = frameCount;
  
  String response;
  serializeJson(doc, response);
  SerialBT.println(response);
}

void sendBluetoothSuccess(String message) {
  if (!SerialBT.hasClient()) return;
  
  DynamicJsonDocument doc(256);
  doc["type"] = "success";
  doc["message"] = message;
  
  String response;
  serializeJson(doc, response);
  SerialBT.println(response);
}

void sendBluetoothError(String error) {
  if (!SerialBT.hasClient()) return;
  
  DynamicJsonDocument doc(256);
  doc["type"] = "error";
  doc["message"] = error;
  
  String response;
  serializeJson(doc, response);
  SerialBT.println(response);
}