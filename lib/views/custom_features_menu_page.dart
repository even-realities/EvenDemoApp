import 'package:demo_ai_even/views/features/custom_text_reader_page.dart';
import 'package:demo_ai_even/views/features/voice_asr_page.dart';
import 'package:demo_ai_even/views/settings/api_settings_page.dart';
import 'package:demo_ai_even/views/settings/input_mapping_page.dart';
import 'package:demo_ai_even/views/settings/elevenlabs_settings_page.dart';
       import 'package:demo_ai_even/views/features/web_reader_page.dart';
import 'package:flutter/material.dart';

class CustomFeaturesMenuPage extends StatelessWidget {
  const CustomFeaturesMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('カスタム機能')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomTextReaderPage(),
                    ),
                  );
                },
                child: const Text('テキスト機能'),
              ),
              const SizedBox(height: 16),
                   ElevatedButton(
                     onPressed: () {
                       Navigator.push(
                         context,
                         MaterialPageRoute(
                           builder: (context) => const WebReaderPage(),
                         ),
                       );
                     },
                     child: const Text('Webテキストリーダー'),
                   ),
                   const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VoiceAsrPage(),
                    ),
                  );
                },
                child: const Text('音声機能（ASR）'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ApiSettingsPage(),
                    ),
                  );
                },
                child: const Text('API設定'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ElevenLabsSettingsPage(),
                    ),
                  );
                },
                child: const Text('ElevenLabs 設定'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InputMappingPage(),
                    ),
                  );
                },
                child: const Text('入力マッピング設定'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
