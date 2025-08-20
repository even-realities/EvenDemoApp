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
  ReaderAction _activeAction = ReaderAction.nextPage;

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
          // 編集対象アクションの選択（SVGホットマップはこのアクションに対してトグル）
          SegmentedButton<ReaderAction>(
            segments: const [
              ButtonSegment(value: ReaderAction.nextPage, label: Text('次ページ')),
              ButtonSegment(value: ReaderAction.previousPage, label: Text('前ページ')),
              ButtonSegment(value: ReaderAction.autoScrollStart, label: Text('開始')),
              ButtonSegment(value: ReaderAction.autoScrollStop, label: Text('停止')),
            ],
            selected: <ReaderAction>{_activeAction},
            onSelectionChanged: (s) => setState(() => _activeAction = s.first),
          ),
          const SizedBox(height: 12),
          // コントローラのSVGを表示（参考図）
          _ControllerHotmap(
            height: 220,
            selectedProvider: () => service.mapping[_activeAction] ?? {},
            toggleCallback: (controlId) {
              final current = {...(service.mapping[_activeAction] ?? {})};
              if (current.contains(controlId)) {
                current.remove(controlId);
              } else {
                current.add(controlId);
              }
              setState(() => service.setControls(_activeAction, current));
            },
            currentAction: _activeAction,
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

class _ControllerHotmap extends StatelessWidget {
  final double height;
  final Set<String> Function() selectedProvider;
  final void Function(String controlId) toggleCallback;
  final ReaderAction currentAction;

  const _ControllerHotmap({
    required this.height,
    required this.selectedProvider,
    required this.toggleCallback,
    required this.currentAction,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedProvider();
    // 正規化座標（0..1）で定義し、実表示サイズにスケール
    final normalized = <String, Rect>{
      // 左右ショルダー/トリガー（上部）
      'leftShoulder': const Rect.fromLTWH(0.08, 0.06, 0.22, 0.10),
      'rightShoulder': const Rect.fromLTWH(0.70, 0.06, 0.22, 0.10),
      'leftTrigger': const Rect.fromLTWH(0.08, 0.16, 0.22, 0.09),
      'rightTrigger': const Rect.fromLTWH(0.70, 0.16, 0.22, 0.09),
      // D-Pad（左）
      'dpadLeft': const Rect.fromLTWH(0.15, 0.52, 0.10, 0.15),
      'dpadRight': const Rect.fromLTWH(0.27, 0.52, 0.10, 0.15),
      'dpadUp': const Rect.fromLTWH(0.21, 0.44, 0.10, 0.15),
      'dpadDown': const Rect.fromLTWH(0.21, 0.60, 0.10, 0.15),
      // ABXY（右）
      'buttonB': const Rect.fromLTWH(0.62, 0.52, 0.10, 0.15),
      'buttonA': const Rect.fromLTWH(0.74, 0.52, 0.10, 0.15),
      'buttonY': const Rect.fromLTWH(0.68, 0.44, 0.10, 0.15),
      'buttonX': const Rect.fromLTWH(0.68, 0.60, 0.10, 0.15),
      // メニュー
      'pauseButton': const Rect.fromLTWH(0.45, 0.50, 0.10, 0.08),
      // リモート（下部）
      'previousTrack': const Rect.fromLTWH(0.20, 0.88, 0.16, 0.08),
      'play': const Rect.fromLTWH(0.42, 0.88, 0.16, 0.08),
      'nextTrack': const Rect.fromLTWH(0.64, 0.88, 0.16, 0.08),
    };

    final allMappings = InputMappingService.instance.mapping;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/additional_images/game_controller_svg.svg',
                  fit: BoxFit.contain,
                ),
              ),
              for (final entry in normalized.entries)
                _hotspotNorm(
                  x: entry.value.left * width,
                  y: entry.value.top * height,
                  w: entry.value.width * width,
                  h: entry.value.height * height,
                  id: entry.key,
                  selected: selected.contains(entry.key),
                  alsoUsedElsewhere: allMappings.entries.any((e) => e.key != currentAction && (e.value.contains(entry.key))),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _hotspotNorm({
    required double x,
    required double y,
    required double w,
    required double h,
    required String id,
    required bool selected,
    required bool alsoUsedElsewhere,
  }) {
    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: () => toggleCallback(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: selected ? Colors.amber.withOpacity(0.35) : Colors.transparent,
            border: Border.all(
              color: selected ? Colors.amber : (alsoUsedElsewhere ? Colors.blueAccent : Colors.transparent),
              width: selected ? 2 : (alsoUsedElsewhere ? 1.5 : 0),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
