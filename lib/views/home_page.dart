// lib/views/home_page.dart (Complete File Example)

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart'; // Import for ProcessingState enum

// Adjust import paths based on your actual project structure:
import 'package:demo_ai_even/services/music_service.dart';
import 'package:demo_ai_even/ble_manager.dart';
// Import other controllers if needed for other UI sections
// import 'package:demo_ai_even/controllers/evenai_model_controller.dart';

class HomePage extends StatelessWidget {
  // Use Get.lazyPut in main.dart or ensure Get.put is called before this widget builds
  // Get instances of your services/controllers using Get.find()
  // It's generally safe to call Get.find() multiple times for the same registered instance.
  final MusicService musicService = Get.find<MusicService>();
  final BleManager bleManager = Get.find<BleManager>();
  // final EvenaiModelController evenaiController = Get.find<EvenaiModelController>(); // Example

  HomePage({super.key}); // Add super.key for constructor

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Even G1 Demo Control'),
        // Optional: Add a refresh button for BLE status if it doesn't auto-update
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.refresh),
        //     tooltip: 'Refresh Status (Manual)',
        //     onPressed: () {
        //       // Force UI update? This is tricky without making BleManager reactive.
        //       // Maybe trigger a scan or status check if BleManager provides one.
        //       print("Manual refresh pressed - Needs implementation in BleManager or HomePage state");
        //       // If HomePage was a StatefulWidget, could call setState(() {});
        //     },
        //   ),
        // ],
      ),
      body: SingleChildScrollView( // Ensures content can scroll if it overflows
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch buttons horizontally
          children: [
            // --- Connection Status ---
            Card( // Use a Card for better visual grouping
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text(
                      'Connection',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 8),
                    // NOTE: This Text widget showing bleManager.connectionStatus
                    // will NOT automatically update unless BleManager is made reactive
                    // (e.g., a GetxController with an RxString) or you use the
                    // onStatusChanged callback to update state elsewhere.
                    Text(bleManager.connectionStatus),
                    const SizedBox(height: 8),
                    // Example: Button to trigger connection to the first paired device
                    // You would typically show a list and let the user choose
                    if (!bleManager.isConnected && bleManager.pairedGlasses.isNotEmpty)
                       ElevatedButton(
                           onPressed: () {
                              final firstDeviceName = bleManager.pairedGlasses.first['deviceName'];
                              if (firstDeviceName != null) {
                                 bleManager.connectToGlasses(firstDeviceName);
                              } else {
                                 print("Error: First paired device has no name.");
                              }
                           },
                           child: Text('Connect to ${bleManager.pairedGlasses.first['deviceName'] ?? 'First Device'}')
                       )
                    // Add buttons for Scan/Disconnect if needed
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Music Widget Section ---
            const Text('Music Widget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(thickness: 1),
            const SizedBox(height: 8),

            // GetBuilder listens to MusicService for changes triggered by notifyListeners()
            GetBuilder<MusicService>(
              builder: (controller) { // 'controller' is the MusicService instance
                final bool isReady = controller.processingState == ProcessingState.ready;
                final bool isCompleted = controller.processingState == ProcessingState.completed;
                final bool canPlay = isReady || isCompleted;
                final bool isConnected = bleManager.isConnected; // Check current connection state

                return Card( // Group music controls in a Card
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Activate/Deactivate Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded( // Make buttons share space
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.visibility, size: 18),
                                label: const Text('Show'),
                                tooltip: 'Show music info on glasses',
                                onPressed: controller.isMusicWidgetActive || !isConnected
                                    ? null // Disable if already active or not connected
                                    : () => controller.activateWidget(),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              ),
                            ),
                            const SizedBox(width: 10), // Spacing between buttons
                            Expanded( // Make buttons share space
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.visibility_off, size: 18),
                                label: const Text('Hide'),
                                tooltip: 'Hide music info from glasses',
                                onPressed: !controller.isMusicWidgetActive || !isConnected
                                    ? null // Disable if inactive or not connected
                                    : () => controller.deactivateWidget(),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            isConnected
                                ? (controller.isMusicWidgetActive ? '(Widget Active on Glasses)' : '(Widget Inactive on Glasses)')
                                : '(Glasses Not Connected)',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: isConnected ? (controller.isMusicWidgetActive ? Colors.green : Colors.grey) : Colors.red,
                            ),
                          ),
                        ),
                        const Divider(height: 24),

                        // Now Playing Info
                        const Text('Now Playing:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          controller.currentTitle,
                          style: const TextStyle(fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          controller.currentArtist,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),

                        // Loading/Buffering Indicator
                        if (controller.processingState == ProcessingState.loading || controller.processingState == ProcessingState.buffering)
                          const Center(child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
                          )),

                        // Phone Playback Controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              iconSize: 36.0,
                              tooltip: 'Previous',
                              onPressed: canPlay ? () => controller.skipPrevious() : null,
                            ),
                            IconButton(
                              icon: Icon(controller.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              iconSize: 48.0,
                              tooltip: controller.isPlaying ? 'Pause' : (isCompleted ? 'Replay' : 'Play'),
                              onPressed: canPlay ? () => controller.togglePlayPause() : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next),
                              iconSize: 36.0,
                              tooltip: 'Next',
                              onPressed: canPlay ? () => controller.skipNext() : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ), // End GetBuilder<MusicService>

            const SizedBox(height: 30),

            // --- Placeholder for Other Features ---
             const Text('Other Features', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
             const Divider(thickness: 1),
             const SizedBox(height: 8),
             Card(
                elevation: 2,
                 child: Padding(
                   padding: const EdgeInsets.all(12.0),
                   child: Column(
                      children: const [
                         Text("Controls for EvenAI, BMP Sending, etc. would go here."),
                         // Example:
                         // ElevatedButton(onPressed: () => Get.find<EvenaiModelController>().someAction(), child: Text("EvenAI Action")),
                      ],
                   ),
                 ),
             ),
            // --- End Other Features ---
          ],
        ),
      ),
    );
  }
}