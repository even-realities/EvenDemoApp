import 'package:demo_ai_even/services/input_mapping_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';

class InputMappingPage extends StatefulWidget {
  const InputMappingPage({super.key});

  @override
  State<InputMappingPage> createState() => _InputMappingPageState();
}

class _InputMappingPageState extends State<InputMappingPage> {
  final service = InputMappingService.instance;

  @override
  void initState() {
    super.initState();
    service.load().then((_) => setState(() {}));
  }

  Widget _chips(ReaderAction action) {
    final selected = service.mapping[action] ?? {};
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final c in InputMappingService.allControls)
          FilterChip(
            label: Text(c),
            selected: selected.contains(c),
            onSelected: (value) {
              setState(() {
                final set = {...selected};
                if (value) {
                  set.add(c);
                } else {
                  set.remove(c);
                }
                service.setControls(action, set);
              });
            },
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('入力マッピング設定'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await service.save();
              if (mounted) Navigator.pop(context);
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // コントローラのSVGを表示（参考図）
          Center(
            child: SvgPicture.asset(
              'assets/additional_images/game_controller_svg.svg',
              height: 160,
              semanticsLabel: 'Game Controller',
              placeholderBuilder: (context) => const SizedBox(height: 160),
            ),
          ),
          const SizedBox(height: 16),
          const Text('次ページ'),
          const SizedBox(height: 8),
          _chips(ReaderAction.nextPage),
          const Divider(height: 24),
          const Text('前ページ'),
          const SizedBox(height: 8),
          _chips(ReaderAction.previousPage),
          const Divider(height: 24),
          const Text('自動スクロール開始'),
          const SizedBox(height: 8),
          _chips(ReaderAction.autoScrollStart),
          const Divider(height: 24),
          const Text('自動スクロール停止'),
          const SizedBox(height: 8),
          _chips(ReaderAction.autoScrollStop),
        ],
      ),
    );
  }
}
