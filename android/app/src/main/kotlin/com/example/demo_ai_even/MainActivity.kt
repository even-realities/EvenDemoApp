package com.example.demo_ai_even // Adjust package name if needed

import android.util.Log
import com.example.demo_ai_even.bluetooth.BleChannelHelper // Import Helper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel // Import EventChannel

class MainActivity: FlutterActivity(), EventChannel.StreamHandler { // Implement StreamHandler
    private val TAG = "MainActivity" // Tag for logging

    /**
     * This method is called when the Flutter engine is ready.
     * We use it to initialize our platform channels via BleChannelHelper.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "Configuring Flutter Engine and initializing BleChannelHelper...")
        // Initialize the channel helper, passing this activity instance
        // This sets up the MethodChannel handler and stores activity context
        BleChannelHelper.initChannel(this, flutterEngine)
        Log.i(TAG, "BleChannelHelper initialized.")
    }

    // --- EventChannel.StreamHandler Implementation ---
    // These methods are required because we pass 'this' (MainActivity) as the
    // StreamHandler when setting up EventChannels in BleChannelHelper.initChannel.

    /**
     * Called when Flutter code starts listening to an EventChannel
     * (e.g., eventBleReceive.listen(...)).
     * The 'arguments' usually contain the name of the specific event channel.
     */
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        // We expect the argument to be the event channel name (tag)
        val eventTag = arguments as? String
        if (eventTag == null) {
            Log.e(TAG, "onListen called with invalid arguments: $arguments")
            return
        }
        Log.i(TAG, "Flutter started listening to EventChannel: $eventTag")
        // Store the EventSink in our helper so native code can send events back
        BleChannelHelper.addEventSink(eventTag, events)
    }

    /**
     * Called when Flutter code cancels its subscription to an EventChannel.
     */
    override fun onCancel(arguments: Any?) {
        val eventTag = arguments as? String
        if (eventTag == null) {
             Log.e(TAG, "onCancel called with invalid arguments: $arguments")
            return
        }
        Log.i(TAG, "Flutter stopped listening to EventChannel: $eventTag")
        // Remove the EventSink from storage as it's no longer valid
        BleChannelHelper.removeEventSink(eventTag)
    }
    // --- End StreamHandler Implementation ---

}