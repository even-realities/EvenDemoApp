// lib/main.dart (Updated to Start MediaListenerService)

import 'package:flutter/material.dart';
import 'package:get/get.dart'; // Import GetX

// Adjust paths as needed:
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/services/music_service.dart'; // Or your new ExternalMediaService
import 'package:demo_ai_even/views/home_page.dart';
import 'package:demo_ai_even/app.dart'; // Import App if App.navigatorKey is needed

// Make main asynchronous if you need to await anything during init
void main() async {
  // Ensure Flutter bindings are initialized *before* using plugins or calling native code
  WidgetsFlutterBinding.ensureInitialized();
  print("main.dart: Flutter Widgets Binding Initialized.");

  // Initialize BleManager singleton instance
  // This also calls its _init method which sets up the method channel handler
  BleManager.get();
  print("main.dart: BleManager Singleton Initialized.");

  // Register your controllers/services with GetX for dependency injection
  print("main.dart: Registering GetX Controllers/Services...");
  Get.put(EvenaiModelController());
  // TODO: Replace MusicService here with your new ExternalMediaService once created for Path B
  Get.put(MusicService()); // For now, we keep MusicService for text display logic base
  print("main.dart: GetX Controllers/Services Registered.");

  // Start listening for BLE events from the native side
  // This should happen after BleManager is initialized
  try {
    print("main.dart: Starting BleManager listener...");
    BleManager.get().startListening();
     print("main.dart: BleManager listener started (listening for events).");
  } catch (e) {
     print("Error starting BleManager listener in main: $e");
     // Consider how to handle this error - maybe show an error message?
  }

  // Start the native media listener service (only on Android)
  // This call needs to happen after BleManager is initialized (as it uses its channel)
  if (GetPlatform.isAndroid) { // Use GetX platform check
      print("main.dart: Platform is Android. Attempting to start MediaListenerService...");
      // Call the static method, await it if necessary (though startService is often fire-and-forget)
      bool serviceStarted = await BleManager.startMediaListenerService();
      if (serviceStarted) {
           print("main.dart: Native method to start MediaListenerService invoked successfully.");
      } else {
           print("main.dart: Native method to start MediaListenerService failed or returned false.");
      }
  } else {
       print("main.dart: Platform is not Android. Skipping MediaListenerService start.");
  }


  // Run the Flutter application
  print("main.dart: Running Flutter App...");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
   MyApp({super.key}); // Add key to constructor

  @override
  Widget build(BuildContext context) {
    // Use GetMaterialApp for GetX features
    return GetMaterialApp(
      title: 'Even G1 Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Assign the global key if needed by BleManager for context access (e.g., Provider.of)
      // If using Get.find in BleManager, this might not be strictly necessary anymore.
      navigatorKey: App.navigatorKey, // Ensure App.navigatorKey is defined in app.dart

      home: HomePage(), // Your main UI screen
      debugShowCheckedModeBanner: false, // Optional: hide debug banner
    );
  }
}

// Ensure you have the App class defined, potentially in lib/app.dart
// Example definition:
/*
// lib/app.dart
import 'package:flutter/material.dart';

class App {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  // Add other global app configurations or singletons if needed

  // Example singleton pattern for App class itself (if desired)
  // static final App _instance = App._internal();
  // factory App() => _instance;
  // App._internal();

  // Helper method (example)
  static BuildContext? get currentContext => navigatorKey.currentContext;

  static void get() {
    // Placeholder if App.get() was used elsewhere, might not be needed now
  }

  static void exitAll() {
     // Placeholder for your exit logic
     print("App.exitAll() called - Implement exit behavior");
     // Maybe SystemNavigator.pop(); ?
  }
}
*/