import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/views/launcher_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');
  debugPrint('Starting app in $env mode');
  BleManager.get();
  Get.put(EvenaiModelController());
  runApp(const MyAppDev());
}

class MyAppDev extends StatelessWidget {
  const MyAppDev({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Even AI Demo (Dev)',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const LauncherPage(),
    );
  }
}
