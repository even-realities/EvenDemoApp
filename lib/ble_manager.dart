// lib/services/ble_manager.dart (Complete Code - Updated for Path B / GetX Access)

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:get/get.dart'; // Import GetX for Get.find and GetPlatform

// Adjust these paths based on your project structure:
import 'package:demo_ai_even/app.dart'; // Keep if App.navigatorKey is used elsewhere
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
// Import the MusicService (which will act as our ExternalMediaService placeholder for now)
import 'package:demo_ai_even/services/music_service.dart';

// --- Helper Class for Received Data ---
// Represents data coming back from the native layer via EventChannel
class BleReceive {
  bool isTimeout = false;
  String lr = "L"; // Side ('L' or 'R') determined by native code
  Uint8List data = Uint8List(0); // Raw byte data
  String type = "Receive"; // Type identifier (e.g., "Receive", "VoiceChunk")

  // Factory constructor to parse the map sent from native EventChannel
  // Adapt the keys ('lr', 'data', 'type') if native sends different keys
  static BleReceive fromMap(dynamic map) {
    var receive = BleReceive();
    if (map is Map) {
      receive.lr = map['lr']?.toString() ?? 'L'; // Default to 'L' if missing
      // Ensure data is Uint8List, default to empty if null or wrong type
      receive.data = map['data'] as Uint8List? ?? Uint8List(0);
      receive.type = map['type']?.toString() ?? 'Receive'; // Default type
    } else {
      // Handle cases where map is not the expected type (e.g., null)
      // print("BleReceive.fromMap: Received non-Map data: $map");
    }
    return receive;
  }

  // Helper to get the command byte (usually the first byte)
  // Returns -1 if data is empty to avoid RangeError
  int getCmd() {
    return data.isNotEmpty ? data[0] : -1;
  }
}

// --- Main Bluetooth Manager Class ---
class BleManager {
  // Callback for UI or other services to listen for status changes
  Function()? onStatusChanged;

  // --- Singleton Pattern ---
  BleManager._() {} // Private constructor
  static BleManager? _instance;
  static BleManager get() {
    // Initialize instance and call _init only once on first access
    _instance ??= BleManager._().._init();
    return _instance!;
  }
  // --- End Singleton ---

  // --- Platform Channel Setup ---
  static const methodSend = "send"; // Native method name for sending data
  static const _eventBleReceive = "eventBleReceive"; // Event channel name for receiving data
  static const _channel = MethodChannel('method.bluetooth'); // Method channel name (must match native)
  // --- End Channel Setup ---

  // --- Stream for Receiving Data ---
  // Populated by the native EventChannel (_eventBleReceive)
  // Marked 'late final' as it's initialized in _init
  late final Stream<BleReceive> eventBleReceive;
  // --- End Stream ---

  // --- State Variables ---
  Timer? beatHeartTimer; // Timer for sending keep-alive heartbeats
  final List<Map<String, String>> pairedGlasses = []; // List of discovered/paired device info maps
  bool isConnected = false; // Overall connection flag (true if both legs connected)
  String connectionStatus = 'Not connected'; // User-friendly status text
  // --- End State ---

  // --- Initialization ---
  // Called once when the singleton instance is created. Sets up communication.
  void _init() {
    // Initialize the stream that listens to the native EventChannel and maps the data
    eventBleReceive = const EventChannel(_eventBleReceive)
        .receiveBroadcastStream() // Use default stream (often dynamic)
        .map((nativeData) => BleReceive.fromMap(nativeData)); // Convert native data map to BleReceive object

    print("BleManager: Instance initialized. Setting native method call handler.");
    // Set the handler for methods called FROM native code TO Flutter
    setMethodCallHandler();

    // IMPORTANT: startListening() must be called externally (e.g., in main.dart)
    // after this instance is created and potentially after other services are ready.
  }
  // --- End Initialization ---

  /// Start listening to the eventBleReceive stream for data from native.
  /// Should ideally be called only once during app startup.
  void startListening() {
    print("BleManager: Starting to listen to native BLE events (eventBleReceive stream)...");
    // TODO: Add logic to prevent multiple subscriptions if startListening can be called more than once.
    eventBleReceive.listen(
      (receivedData) { // Callback for each data event from native
        _handleReceivedData(receivedData);
      },
      onError: (error) { // Callback for errors on the stream
        print("BleManager: **ERROR** on eventBleReceive stream: $error");
        // Consider updating connection status or notifying the user
        connectionStatus = 'Stream Error: $error'; // Include error in status
        isConnected = false;
        onStatusChanged?.call();
      },
      onDone: () { // Callback for when the stream is closed
        print("BleManager: eventBleReceive stream closed.");
        connectionStatus = 'Stream Closed';
        isConnected = false;
        onStatusChanged?.call();
      },
      cancelOnError: false // Keep listening after errors (optional)
    );
  }

  // --- Methods Calling Native Code via MethodChannel ---

  /// Initiates a BLE scan on the native side.
  Future<void> startScan() async {
    print("BleManager: Requesting native 'startScan'");
    try {
      // Invoke the method on the native side
      await _channel.invokeMethod('startScan');
    } catch (e) {
      print('BleManager: Error invoking native startScan: $e');
      // Handle error (e.g., show message to user)
    }
  }

  /// Stops an ongoing BLE scan on the native side.
  Future<void> stopScan() async {
    print("BleManager: Requesting native 'stopScan'");
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      print('BleManager: Error invoking native stopScan: $e');
    }
  }

  /// Attempts to connect to a specific pair of glasses by deviceName/channel.
  Future<void> connectToGlasses(String deviceName) async {
    print("BleManager: Requesting native 'connectToGlasses' for device: $deviceName");
    // Update UI state optimistically
    connectionStatus = 'Connecting...';
    isConnected = false;
    onStatusChanged?.call();
    try {
      // Pass the device name as an argument in a map
      await _channel.invokeMethod('connectToGlasses', {'deviceName': deviceName});
    } catch (e) {
      print('BleManager: Error invoking native connectToGlasses: $e');
      // Update UI on error
      connectionStatus = 'Connection Error';
      isConnected = false;
      onStatusChanged?.call();
    }
  }

  /// Sets the handler that listens for method calls *coming from* the native side.
  void setMethodCallHandler() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  // --- Native -> Flutter Callback Handling ---

  /// Handles method calls received FROM the native side (e.g., connection status updates).
  Future<void> _methodCallHandler(MethodCall call) async {
    print("BleManager: Received native method call: ${call.method} | Args: ${call.arguments}");
    switch (call.method) {
      case 'glassesConnected':
        _onGlassesConnected(call.arguments);
        break;
      case 'glassesConnecting':
        _onGlassesConnecting();
        break;
      case 'glassesDisconnected':
        _onGlassesDisconnected();
        break;
      case 'foundPairedGlasses':
        // Safely cast arguments, expecting a Map
        if (call.arguments is Map) {
          try {
            _onPairedGlassesFound(Map<String, String>.from(call.arguments as Map));
          } catch (e) {
            print("BleManager: Error casting foundPairedGlasses arguments: $e");
          }
        } else {
          print("BleManager: Invalid arguments type for foundPairedGlasses: ${call.arguments.runtimeType}");
        }
        break;
      default:
        print('BleManager: Received unknown native method call: ${call.method}');
    }
  }

  /// Callback executed when native side confirms connection.
  void _onGlassesConnected(dynamic arguments) {
    print("BleManager: Native reported glasses connected. Args: $arguments");
    String leftName = "Unknown L";
    String rightName = "Unknown R";
    if (arguments is Map) { // Safely extract names if available
      leftName = arguments['leftDeviceName']?.toString() ?? leftName;
      rightName = arguments['rightDeviceName']?.toString() ?? rightName;
    }
    connectionStatus = 'Connected:\n$leftName\n$rightName';
    isConnected = true;
    onStatusChanged?.call(); // Notify listeners (e.g., UI)
    startSendBeatHeart(); // Start heartbeat keep-alive
  }

  /// Callback executed when native side starts connecting.
  void _onGlassesConnecting() {
    print("BleManager: Native reported glasses connecting...");
    connectionStatus = 'Connecting...';
    isConnected = false; // Not fully connected yet
    onStatusChanged?.call();
  }

  /// Callback executed when native side reports disconnection.
  void _onGlassesDisconnected() {
    print("BleManager: Native reported glasses disconnected.");
    connectionStatus = 'Not connected';
    isConnected = false;
    beatHeartTimer?.cancel(); // Stop heartbeat
    beatHeartTimer = null;
    onStatusChanged?.call();
    // Notify ExternalMediaService (MusicService placeholder) to deactivate widget
    try {
      // Use Get.find to access the service instance
      Get.find<MusicService>().deactivateWidget();
      print("BleManager: Notified MusicService (ExternalMedia) to deactivate on disconnect.");
    } catch(e) {
      // Log error if service not found or deactivate fails
      print("BleManager: Could not notify MusicService (ExternalMedia) on disconnect: $e");
    }
  }

  /// Callback executed when native side finds a pair of glasses during scan.
  void _onPairedGlassesFound(Map<String, String> deviceInfo) {
    print("BleManager: Native found paired glasses. Info: $deviceInfo");
    final String? channelNumber = deviceInfo['channelNumber'];
    if (channelNumber == null) {
      print("BleManager: Warning - foundPairedGlasses missing 'channelNumber'.");
      return;
    }
    // Avoid adding duplicates
    final isAlreadyPaired = pairedGlasses.any((glasses) => glasses['channelNumber'] == channelNumber);
    if (!isAlreadyPaired) {
      print("BleManager: Adding new paired glasses (Channel: $channelNumber) to list.");
      pairedGlasses.add(deviceInfo);
      onStatusChanged?.call(); // Notify UI about the updated list
    }
  }

  // --- Heartbeat Logic ---
  int tryTime = 0; // Simple retry counter for heartbeat
  void startSendBeatHeart() {
    // Avoid starting multiple timers
    if (beatHeartTimer != null && beatHeartTimer!.isActive) {
      print("BleManager: Heartbeat timer already active.");
      return;
    }
    print("BleManager: Starting heartbeat timer (8s interval).");
    beatHeartTimer?.cancel(); // Cancel just in case
    beatHeartTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      if (!isConnected) { // Stop if disconnected
        print("BleManager: Heartbeat - Disconnected. Stopping timer.");
        timer.cancel();
        beatHeartTimer = null;
        return;
      }
      // print("BleManager: Heartbeat - Sending..."); // Reduce log spam
      bool isSuccess = await Proto.sendHeartBeat();
      if (!isSuccess) {
        // print("BleManager: Heartbeat - Send failed (attempt ${tryTime + 1}).");
        if (tryTime < 2) { // Retry logic
          tryTime++;
          // print("BleManager: Heartbeat - Retrying...");
          await Future.delayed(const Duration(milliseconds: 200));
          isSuccess = await Proto.sendHeartBeat(); // Retry send
          if (!isSuccess && tryTime >= 1) { // Check again after retry
            print("BleManager: Heartbeat - Send failed after retry ${tryTime}. Stopping timer.");
            timer.cancel(); beatHeartTimer = null; // Stop on persistent failure
            // Optionally trigger disconnect logic: _onGlassesDisconnected();
          } else if (isSuccess) { tryTime = 0; /*print("BleManager: Heartbeat - Success on retry.");*/ }
        } else {
          print("BleManager: Heartbeat - Send failed after final attempt. Stopping timer.");
          timer.cancel(); beatHeartTimer = null; // Stop on persistent failure
          // Optionally trigger disconnect logic: _onGlassesDisconnected();
        }
      } else { /*print("BleManager: Heartbeat - Success.");*/ tryTime = 0; } // Reset counter
    });
  }
  // --- End Heartbeat ---


  // --- Data Handling ---

  /// Handles incoming data (`BleReceive` objects) from the `eventBleReceive` stream.
  /// This is the central point for processing notifications and command responses.
  void _handleReceivedData(BleReceive res) {
    // --- Voice Chunk Handling ---
    if (res.type == "VoiceChunk") {
      // TODO: Route voice data appropriately if/when needed for ASR features
      // EvenAI.get.handleVoiceData(res.data);
      // print("BleManager: VoiceChunk received (${res.data.length} bytes).");
      return; // Exit early, voice data handled separately
    }

    // --- Standard Command/Notification Handling ---
    String cmdHex = res.getCmd().toRadixString(16).padLeft(2, '0');
    String cmd = "${res.lr}$cmdHex"; // Key for request/response matching

    // Log non-microphone, non-heartbeat data for easier debugging
    if (res.getCmd() != 0xf1 && res.getCmd() != 0x25) {
      print(
        "${DateTime.now()} BleManager: Received | Side: ${res.lr} | Cmd: 0x$cmdHex | Len: ${res.data.length} | Data: ${res.data.hexString}",
      );
    }

    // --- F5 Touch Event Handling (Includes Music/ExternalMedia Widget Routing) ---
    if (res.getCmd() == 0xF5) {
      if (res.data.length < 2) {
        print("BleManager: Error - Received F5 command with invalid length: ${res.data.length}");
        return; // Ignore invalid F5 packet
      }
      final notifyIndex = res.data[1].toInt(); // The sub-command (0, 1, 23, 24, etc.)

      // **** TRY ROUTING TO ExternalMediaService (MusicService placeholder) via GetX ****
      try {
        // Use Get.find to get the singleton instance registered in main.dart
        // Make sure MusicService (or your future ExternalMediaService) is registered with Get.put()
        final externalMediaService = Get.find<MusicService>(); // Use MusicService for now

        // Check if the widget feature is active AND if it's a relevant command (Tap or Double Tap)
        if (externalMediaService.isMusicWidgetActive && (notifyIndex == 0 || notifyIndex == 1)) {
          TouchSide side = (res.lr == 'L') ? TouchSide.left : (res.lr == 'R' ? TouchSide.right : TouchSide.unknown);
          print("BleManager: Routing F5 (SubCmd: $notifyIndex, Side: $side) to ExternalMediaService (MusicService)...");
          // Call the handler in the service (don't await, let it run)
          externalMediaService.handleTouchInput(notifyIndex, side);
          return; // IMPORTANT: Exit here, event handled by media service
        }
        // If widget not active or command not relevant, fall through...
      } catch (e) {
        // Log if Get.find fails (service not registered?) or if service check throws error
        print("BleManager: Info - ExternalMediaService (MusicService) inactive or error accessing it via Get.find. Falling through. Error: $e");
        // Fall through to default handling
      }
      // **** END ExternalMediaService CHECK ****

      // --- Default F5 Handling (if not handled above) ---
      print("BleManager: F5 (SubCmd: $notifyIndex) not handled by ExternalMediaService, processing default...");
      switch (notifyIndex) {
        case 0: // Double Tap (Exit)
          print("BleManager: Handling F5/0 (Exit) via App.get.exitAll()");
          App.get.exitAll(); // Assuming App.get() works or replace with appropriate exit logic
          break;
        case 1: // Single Tap (PageUp/Down for EvenAI)
          print("BleManager: Handling F5/1 (Page Tap) via EvenAI...");
          if (res.lr == 'L') {
            EvenAI.get.lastPageByTouchpad();
          } else {
            EvenAI.get.nextPageByTouchpad();
          }
          break;
        case 23: // EvenAI Start
          print("BleManager: Handling F5/23 (EvenAI Start)...");
          EvenAI.get.toStartEvenAIByOS();
          break;
        case 24: // EvenAI Record Over
          print("BleManager: Handling F5/24 (EvenAI Record Over)...");
          EvenAI.get.recordOverByOS();
          break;
        // TODO: Add cases for 0x04/0x05 (Triple Tap) if needed by any feature
        default:
          print("BleManager: Unhandled F5 SubCmd: $notifyIndex");
      }
      return; // F5 event processed, exit
    } // --- End F5 Handling ---

    // --- Handle Responses to Specific Requests ---
    // Check if we have a completer waiting for this specific command response
    Completer<BleReceive>? completer = _reqListen.remove(cmd);
    if (completer != null) {
      // print("BleManager: Completing listener for cmd: $cmd");
      if (!completer.isCompleted) {
        completer.complete(res); // Complete the Future with the received data
      }
      _reqTimeout.remove(cmd)?.cancel(); // Cancel the associated timeout timer
    }
    // Check the less common 'useNext' completer
    else if (_nextReceive != null && !_nextReceive!.isCompleted) {
      // print("BleManager: Completing _nextReceive listener.");
      _nextReceive!.complete(res);
      _nextReceive = null;
    } else {
      // Optional: Log if data is received for a command we weren't explicitly waiting for
      // This might happen with unsolicited notifications if not handled elsewhere
      // print("BleManager: Received data for cmd '$cmd' but no active listener found.");
    }
    // --- End Response Handling ---

  } // --- End _handleReceivedData ---

  // --- Public Getters ---
  String getConnectionStatus() {
    return connectionStatus;
  }

  List<Map<String, String>> getPairedGlasses() {
    return List<Map<String, String>>.from(pairedGlasses); // Return immutable copy
  }
  // --- End Getters ---


  // =========================================================================
  // === Static Methods for Sending Commands / Handling Requests          ===
  // =========================================================================


  // --- Static Request/Response Handling Logic ---
  // Store completers waiting for responses, keyed by "LR"+"CmdHex"
  // Made static so request/send methods can access them without instance
  static final _reqListen = <String, Completer<BleReceive>>{};
  // Store timers associated with requests to handle timeouts
  static final _reqTimeout = <String, Timer>{};
  // Special completer for waiting for the *next* unknown response (use cautiously)
  static Completer<BleReceive>? _nextReceive;

  // Timeout handler for requests - Completes the future with a timeout indication
  static void _checkTimeout(String cmd, int timeoutMs, Uint8List data, String lr) {
    _reqTimeout.remove(cmd)?.cancel(); // Cancel timer if it exists
    var completer = _reqListen.remove(cmd); // Remove and get completer
    if (completer != null && !completer.isCompleted) {
      print("${DateTime.now()} BleManager: Request Timeout ($timeoutMs ms) for cmd: $cmd (Side: $lr)");
      var res = BleReceive()
        ..isTimeout = true
        ..lr = lr // Include side info
        ..data = data; // Optionally include original sent data
      completer.complete(res); // Complete the future with timeout result
    }
  }

  /// Helper to invoke native methods via the MethodChannel.
  static Future<T?> invokeMethod<T>(String method, [dynamic params]) {
    // print("BleManager: Invoking method '$method' with params: $params"); // Reduce log spam
    return _channel.invokeMethod<T>(method, params);
  }

  /// Sends a request via `request` and retries automatically on timeout.
  static Future<BleReceive> requestRetry(
    Uint8List data, {
    String? lr, // Specific leg (L/R) or null for both (handled by sendData/request)
    Map<String, dynamic>? other, // Extra params for native send
    int timeoutMs = 200, // Timeout PER attempt
    bool useNext = false, // Use 'next' listener? (Usually false)
    int retry = 3, // Number of RETRIES (total attempts = retry + 1)
  }) async {
    BleReceive ret;
    String cmdHex = data.isNotEmpty ? data[0].toRadixString(16) : '??';
    for (var i = 0; i <= retry; i++) {
      // print("BleManager: requestRetry (Attempt ${i + 1}/${retry + 1}) for cmd 0x$cmdHex (Side: ${lr ?? 'Both'})");
      ret = await request(data, lr: lr, other: other, timeoutMs: timeoutMs, useNext: useNext);
      if (!ret.isTimeout) {
        // print("BleManager: requestRetry successful on attempt ${i + 1}.");
        return ret; // Success! Return the valid response.
      }
      // If timed out, check connection before retrying
      if (!BleManager.isBothConnected()) {
        print("BleManager: requestRetry aborted during retries - Connection lost.");
        return ret; // Return the last timeout result
      }
      // print("BleManager: requestRetry attempt ${i + 1} timed out.");
      if (i < retry) await Future.delayed(const Duration(milliseconds: 50)); // Small delay
    }
    // If loop finishes, all attempts failed
    print("BleManager: requestRetry failed after ${retry + 1} attempts for cmd 0x$cmdHex (Side: ${lr ?? 'Both'}).");
    return ret..isTimeout = true..lr = lr ?? 'Both'; // Ensure final result indicates timeout
  }

  /// Sends the same data to both legs sequentially (L then R), waiting for success on L.
  /// Optionally checks the response payload using `isSuccess` callback.
  static Future<bool> sendBoth(
    Uint8List dataToSend, { // Renamed param for clarity
    int timeoutMs = 250, // Timeout per leg request
    SendResultParse? isSuccess, // Optional callback to validate response data
    int? retry, // Number of retries PER leg (0 = 1 attempt)
  }) async {
    String cmdHex = dataToSend.isNotEmpty ? dataToSend[0].toRadixString(16) : '??';
    // print("BleManager: sendBoth - Sending cmd 0x$cmdHex...");
    int retryCount = retry ?? 0;

    // --- Send to Left ---
    // print("BleManager: sendBoth - Sending to LEFT leg.");
    var retL = await BleManager.requestRetry(dataToSend, lr: "L", timeoutMs: timeoutMs, retry: retryCount);
    if (retL.isTimeout) {
      print("BleManager: sendBoth - LEFT leg timed out for cmd 0x$cmdHex.");
      return false;
    }
    if (isSuccess != null && !isSuccess.call(retL.data)) {
      print("BleManager: sendBoth - LEFT leg response failed 'isSuccess' check for cmd 0x$cmdHex.");
      return false;
    }
    // print("BleManager: sendBoth - LEFT leg successful for cmd 0x$cmdHex.");

    // --- Send to Right (Only if Left was successful) ---
    // print("BleManager: sendBoth - Sending to RIGHT leg.");
    var retR = await BleManager.requestRetry(dataToSend, lr: "R", timeoutMs: timeoutMs, retry: retryCount);
    if (retR.isTimeout) {
      print("BleManager: sendBoth - RIGHT leg timed out for cmd 0x$cmdHex.");
      return false;
    }
    if (isSuccess != null && !isSuccess.call(retR.data)) {
      print("BleManager: sendBoth - RIGHT leg response failed 'isSuccess' check for cmd 0x$cmdHex.");
      return false;
    }
    // print("BleManager: sendBoth - RIGHT leg successful for cmd 0x$cmdHex. Overall Success.");
    return true; // Both legs succeeded (or passed checks)
  }

  /// Lower-level function to invoke the native 'send' method.
  /// Handles sending to specific leg or both (L then R).
  static Future<dynamic> sendData(Uint8List data,
      {String? lr, Map<String, dynamic>? other, int secondDelay = 0}) async { // Default delay 0ms
    var params = <String, dynamic>{ 'data': data }; // Base parameters
    if (other != null) params.addAll(other); // Add optional extra params
    dynamic nativeResult; // Result from native invokeMethod call

    if (lr != null) {
      // Send to specific leg (L or R)
      params["lr"] = lr;
      // print("BleManager: sendData -> Native 'send' (Side: $lr)");
      nativeResult = await BleManager.invokeMethod(methodSend, params);
      // print("BleManager: sendData response (Side: $lr): $nativeResult");
    } else {
      // Send to Left first
      params["lr"] = "L";
      // print("BleManager: sendData -> Native 'send' (Side: L)");
      nativeResult = await BleManager.invokeMethod(methodSend, params);
      // print("BleManager: sendData response (Side: L): $nativeResult");

      // Decide whether to proceed to Right leg
      // Assume proceed unless native explicitly returns 'false'
      bool proceedToRight = (nativeResult != false);
      if (!proceedToRight) {
         print("BleManager: sendData - Native indicated failure/stop after L send. Not sending to R.");
      }

      // Optional delay between sending to L and R
      if (secondDelay > 0 && proceedToRight) {
        // print("BleManager: sendData - Delaying ${secondDelay}ms before sending to R.");
        await Future.delayed(Duration(milliseconds: secondDelay));
      }

      // Send to Right leg if appropriate
      if (proceedToRight) {
        params["lr"] = "R";
        // print("BleManager: sendData -> Native 'send' (Side: R)");
        nativeResult = await BleManager.invokeMethod(methodSend, params);
        // print("BleManager: sendData response (Side: R): $nativeResult");
      }
    }
    // Return the result of the last native call made
    return nativeResult;
  }

  /// Sends data and sets up a listener (Completer) to wait for a specific response.
  /// Handles timeouts and ensures only one listener exists per command key.
  static Future<BleReceive> request(Uint8List data,
      {String? lr, // Target leg (L/R) or null (uses lr0 logic)
      Map<String, dynamic>? other, // Extra params for native send
      int timeoutMs = 1000, // Timeout for this specific request
      bool useNext = false}) async // Use the single _nextReceive listener? (Rarely needed)
  {
    // Determine key for listener map - includes specific side if provided
    var lr0 = lr ?? "Both"; // Identifier if lr is null
    if (data.isEmpty) {
      print("BleManager: Error - Cannot send empty data in request.");
      return BleReceive()..isTimeout = true..lr = lr0; // Fail fast
    }
    String cmdHex = data[0].toRadixString(16).padLeft(2, '0');
    String cmdKey = "${lr ?? lr0}$cmdHex"; // e.g., "L4E", "R4E", "Both4E"

    var completer = Completer<BleReceive>(); // The Future we will return

    // Setup the listener (either specific key or the single 'next' listener)
    if (useNext) {
      // print("BleManager: request - Setting up _nextReceive listener for cmd 0x$cmdHex (Side: $lr0). Caution advised.");
      if (_nextReceive != null && !_nextReceive!.isCompleted) {
         print("BleManager: Warning - Overwriting existing _nextReceive listener.");
          _nextReceive!.complete(BleReceive()..isTimeout = true..lr="Unknown"); // Timeout old one
      }
      _nextReceive = completer;
    } else {
      // Standard request using cmdKey
      if (_reqListen.containsKey(cmdKey)) {
        // print("BleManager: Warning - Overwriting existing listener for cmd: $cmdKey.");
        _reqListen[cmdKey]?.complete(BleReceive()..isTimeout = true..lr = lr0..data = data); // Timeout old one
        _reqTimeout.remove(cmdKey)?.cancel(); // Cancel old timer
      }
      _reqListen[cmdKey] = completer; // Store the new completer
      // print("BleManager: request - Added listener for cmd: $cmdKey");
    }

    // Setup timeout timer for this request
    Timer? requestTimer; // Hold timer locally
    if (timeoutMs > 0) {
      // print("BleManager: request - Setting timeout ($timeoutMs ms) for cmd: $cmdKey");
      requestTimer = Timer(Duration(milliseconds: timeoutMs), () {
        // This lambda runs if the timer expires before completion
        _checkTimeout(cmdKey, timeoutMs, data, lr0); // Completes the future with timeout
      });
      _reqTimeout[cmdKey] = requestTimer; // Store timer (might overwrite if key reused quickly)
    }

    // Ensure timer is cancelled when the future completes (success or timeout)
    completer.future.whenComplete(() {
      requestTimer?.cancel(); // Cancel this specific request's timer
      _reqTimeout.remove(cmdKey); // Remove from map to be sure
      // If it was a 'useNext' request, clear _nextReceive if it's still our completer
      if (useNext && _nextReceive == completer) {
        _nextReceive = null;
      }
      // No need to remove from _reqListen here, done by _handleReceivedData or _checkTimeout
    });

    // Initiate the actual data send via the lower-level sendData function
    try {
      // Add a safety timeout around the native call itself, in case it hangs
      await sendData(data, lr: lr, other: other).timeout(
        const Duration(seconds: 3), // Increased safety timeout slightly
        onTimeout: () {
          print("BleManager: **FATAL** - invokeMethod('send') timed out for cmd: $cmdKey. Native layer unresponsive?");
          // If invokeMethod times out, the command likely never reached native or response was lost
          // Ensure our listener future is completed with a timeout.
          if (!completer.isCompleted) {
            _checkTimeout(cmdKey, timeoutMs, data, lr0); // Trigger timeout logic
          }
          // Rethrow to indicate a severe problem
          throw TimeoutException("invokeMethod('send') timed out after 3 seconds");
        },
      );
      // print("BleManager: request - sendData initiated for cmd: $cmdKey");
    } catch (e) {
      print("BleManager: Error during sendData/invokeMethod for cmd: $cmdKey - $e");
      // If sending fails, ensure the listener future is completed with a timeout/error
      if (!completer.isCompleted) {
        _checkTimeout(cmdKey, timeoutMs, data, lr0); // Trigger timeout logic
      }
    }

    // Return the future which will be completed either by response or timeout
    return completer.future;
  }

  /// Checks connection status based on the instance variable `isConnected`.
  static bool isBothConnected() {
    // Access the singleton instance's state variable
    return _instance?.isConnected ?? false;
  }


  /// Sends a list of packets sequentially, first all to L, then all to R,
  /// or all to a specific leg if 'lr' is provided.
  static Future<bool> requestList(
    List<Uint8List> sendList, {
    String? lr, // Target leg (L, R) or null for both
    int? timeoutMs, // Timeout PER request in the list
  }) async {
    if (sendList.isEmpty) {
      // print("BleManager: requestList called with empty list.");
      return true; // No packets to send
    }
    String listCmd = sendList.first.isNotEmpty ? sendList.first[0].toRadixString(16) : '??';
    // print("BleManager: requestList - Sending ${sendList.length} packets for cmd 0x$listCmd (Side: ${lr ?? 'Both'}, Timeout per req: $timeoutMs ms)");

    if (lr != null) {
      // Send all packets sequentially to the specified leg (L or R)
      return await _requestList(sendList, lr, timeoutMs: timeoutMs);
    } else {
      // Send all to Left, then all to Right if Left succeeds
      // print("BleManager: requestList - Sending to LEFT first...");
      bool leftSuccess = await _requestList(sendList, "L", timeoutMs: timeoutMs);
      if (!leftSuccess) {
        print("BleManager: requestList - LEFT leg failed for cmd 0x$listCmd. Aborting.");
        return false; // Fail fast
      }

      // print("BleManager: requestList - LEFT leg successful. Sending to RIGHT...");
      bool rightSuccess = await _requestList(sendList, "R", timeoutMs: timeoutMs);
      if (!rightSuccess) {
        print("BleManager: requestList - RIGHT leg failed for cmd 0x$listCmd.");
        return false;
      }

      // print("BleManager: requestList - Both legs successful for cmd 0x$listCmd.");
      return true; // Both legs completed successfully
    }
  }

  /// Internal helper: Sends a list of packets sequentially to ONE specified leg (L or R).
  /// Waits for a success response (0xC9 or 0xCB) for each packet before sending the next.
  static Future<bool> _requestList(List<Uint8List> sendList, String lr, {int? timeoutMs}) async {
    for (int i = 0; i < sendList.length; i++) {
      var pack = sendList[i];
      // print("BleManager: _requestList (Side: $lr) - Sending packet ${i + 1}/${sendList.length}...");
      // Use 'request' to send and wait for the response/timeout for this packet
      var resp = await request(pack, lr: lr, timeoutMs: timeoutMs ?? 350); // Default 350ms timeout per packet

      if (resp.isTimeout) {
        print("BleManager: _requestList (Side: $lr) - Timeout waiting for response to packet ${i + 1}. Aborting list.");
        return false; // Fail list if one packet times out
      }
      // Check for expected success response codes (0xC9 or 0xCB at index 1)
      // Ensure data has at least 2 bytes before checking index 1
      else if (!(resp.data.length > 1 && (resp.data[1] == 0xc9 || resp.data[1] == 0xcB))) {
        print("BleManager: _requestList (Side: $lr) - Received non-success response for packet ${i + 1}. Response: ${resp.data.hexString}. Aborting list.");
        return false; // Fail list if response is not success
      } else {
        // Packet successful, add small delay before next one (helps reliability)
        await Future.delayed(const Duration(milliseconds: 15)); // Adjusted delay
      }
    }
    // print("BleManager: _requestList (Side: $lr) - Successfully sent all ${sendList.length} packets.");
    return true; // All packets sent and acknowledged successfully
  }

  // =========================================================================
  // === NEW STATIC METHOD TO START NATIVE ANDROID MEDIA LISTENER SERVICE ===
  // =========================================================================

  /// Calls the native Android code to start the MediaListenerService.
  /// Returns true if the native method was invoked successfully, false otherwise.
  static Future<bool> startMediaListenerService() async {
    // Only attempt to start on the Android platform
    if (GetPlatform.isAndroid) {
      print("BleManager: Requesting native to start MediaListenerService...");
      try {
        // Invoke the method on the platform channel.
        // The name 'nativeStartMediaListener' must exactly match the function
        // name defined inside BleMethodChannel class in BleChannelHelper.kt
        final result = await _channel.invokeMethod<bool>('nativeStartMediaListener');
        print("BleManager: nativeStartMediaListener invoked, native result: $result");
        // Return true if native specifically returned true (indicating success), otherwise false
        return result ?? false;
      } catch (e) {
        // Log any errors during the platform channel communication
        print("BleManager: Error invoking native 'nativeStartMediaListener': $e");
        return false; // Return false on error
      }
    } else {
      // Informative message if running on a non-Android platform
      print("BleManager: MediaListenerService is only available on Android. Skipping start.");
      return false; // Indicate service cannot be started on this platform
    }
  }
  // =========================================================================

} // End of BleManager class

// Extension for easy hex string conversion of byte lists (useful for logging)
extension Uint8ListEx on Uint8List {
  String get hexString {
    return map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}