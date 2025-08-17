
import 'package:demo_ai_even/views/features/custom_text_reader_page.dart';
import 'package:demo_ai_even/views/home_page.dart';
import 'package:flutter/material.dart';

class LauncherPage extends StatelessWidget {
  const LauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Even G1 Custom App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
              child: const Text('公式デモ機能 (Official Demos)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomTextReaderPage()),
                );
              },
              child: const Text('カスタム機能 (Custom Features)'),
            ),
          ],
        ),
      ),
    );
  }
}
