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

  const _ControllerHotmap({
    required this.height,
    required this.selectedProvider,
    required this.toggleCallback,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedProvider();
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
          // 左右ショルダー
          _hotspot(left: 24, top: 16, w: 80, h: 30, id: 'leftShoulder', selected: selected.contains('leftShoulder')),
          _hotspot(right: 24, top: 16, w: 80, h: 30, id: 'rightShoulder', selected: selected.contains('rightShoulder')),
          // トリガー
          _hotspot(left: 24, top: 52, w: 80, h: 24, id: 'leftTrigger', selected: selected.contains('leftTrigger')),
          _hotspot(right: 24, top: 52, w: 80, h: 24, id: 'rightTrigger', selected: selected.contains('rightTrigger')),
          // ABXY（右側）
          _hotspot(right: 64, bottom: 48, w: 36, h: 36, id: 'buttonA', selected: selected.contains('buttonA')),
          _hotspot(right: 100, bottom: 84, w: 36, h: 36, id: 'buttonY', selected: selected.contains('buttonY')),
          _hotspot(right: 100, bottom: 12, w: 36, h: 36, id: 'buttonX', selected: selected.contains('buttonX')),
          _hotspot(right: 136, bottom: 48, w: 36, h: 36, id: 'buttonB', selected: selected.contains('buttonB')),
          // D-Pad（左側）
          _hotspot(left: 64, bottom: 48, w: 36, h: 36, id: 'dpadRight', selected: selected.contains('dpadRight')),
          _hotspot(left: 28, bottom: 48, w: 36, h: 36, id: 'dpadLeft', selected: selected.contains('dpadLeft')),
          _hotspot(left: 46, bottom: 84, w: 36, h: 36, id: 'dpadUp', selected: selected.contains('dpadUp')),
          _hotspot(left: 46, bottom: 12, w: 36, h: 36, id: 'dpadDown', selected: selected.contains('dpadDown')),
          // メニューボタン
          _hotspot(w: 36, h: 24, id: 'pauseButton', selected: selected.contains('pauseButton')),
          // リモート（下部に擬似配置）
          _hotspot(bottom: 4, w: 54, h: 24, id: 'play', selected: selected.contains('play')),
          _hotspot(bottom: 4, left: 24, w: 54, h: 24, id: 'previousTrack', selected: selected.contains('previousTrack')),
          _hotspot(bottom: 4, right: 24, w: 54, h: 24, id: 'nextTrack', selected: selected.contains('nextTrack')),
        ],
      ),
    );
  }

  Widget _hotspot({
    double? left,
    double? top,
    double? right,
    double? bottom,
    required double w,
    required double h,
    required String id,
    required bool selected,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: GestureDetector(
        onTap: () => toggleCallback(id),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: selected ? Colors.amber.withOpacity(0.35) : Colors.transparent,
            border: Border.all(color: selected ? Colors.amber : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
