import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/views/launcher_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  const env = String.fromEnvironment('ENV', defaultValue: 'prod');
  debugPrint('Starting app in $env mode');
  BleManager.get();
  Get.put(EvenaiModelController());
  runApp(const MyAppProd());
}

class MyAppProd extends StatelessWidget {
  const MyAppProd({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Even AI',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LauncherPage(),
    );
  }
}
