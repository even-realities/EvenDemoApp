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
  bool _showRemote = false;

  @override
  void initState() {
    super.initState();
    service.load().then((_) => setState(() {}));
  }

  static const Set<String> _remoteControls = {
    'play', 'pause', 'togglePlayPause', 'nextTrack', 'previousTrack',
  };
  static const Set<String> _placeholderControls = {
    'power', 'remote1', 'remote2',
  };

  List<String> _controlsForMode(bool remote) {
    if (remote) {
      return _remoteControls.toList();
    }
    return InputMappingService.allControls
        .where((c) => !_remoteControls.contains(c) && !_placeholderControls.contains(c))
        .toList();
  }

  Widget _chips(ReaderAction action, {required bool remote}) {
    final selected = service.mapping[action] ?? {};
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final c in _controlsForMode(remote))
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('表示: '),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('ゲームパッド')),
                  ButtonSegment(value: true, label: Text('リモコン')),
                ],
                selected: {_showRemote},
                onSelectionChanged: (s) {
                  setState(() {
                    _showRemote = s.first;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
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
            showRemote: _showRemote,
          ),
          const SizedBox(height: 16),
          const Text('次ページ'),
          const SizedBox(height: 8),
          _chips(ReaderAction.nextPage, remote: _showRemote),
          const Divider(height: 24),
          const Text('前ページ'),
          const SizedBox(height: 8),
          _chips(ReaderAction.previousPage, remote: _showRemote),
          const Divider(height: 24),
          const Text('自動スクロール開始'),
          const SizedBox(height: 8),
          _chips(ReaderAction.autoScrollStart, remote: _showRemote),
          const Divider(height: 24),
          const Text('自動スクロール停止'),
          const SizedBox(height: 8),
          _chips(ReaderAction.autoScrollStop, remote: _showRemote),
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
  final bool showRemote;

  const _ControllerHotmap({
    required this.height,
    required this.selectedProvider,
    required this.toggleCallback,
    required this.currentAction,
    this.showRemote = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedProvider();
    // viewBox: 0 0 500 220 を基準に実座標で定義
    // D-Pad 原点(150,100), 腕の外形は約 -24..24 / 中央幹は約 -8..8
    final rectsViewBox = <String, Rect>{
      // Shoulders (L1/R1)
      'leftShoulder': const Rect.fromLTWH(120, 30, 40, 18),
      'rightShoulder': const Rect.fromLTWH(340, 30, 40, 18),
      // Triggers（SVGに明示は無いので肩の手前/奥を擬似配置）
      'leftTrigger': const Rect.fromLTWH(120, 52, 40, 14),
      'rightTrigger': const Rect.fromLTWH(340, 52, 40, 14),
      // D-Pad quadrants around (150,100)
      'dpadLeft': const Rect.fromLTWH(150 - 24, 100 - 8, 16, 16),
      'dpadRight': const Rect.fromLTWH(150 + 8, 100 - 8, 16, 16),
      'dpadUp': const Rect.fromLTWH(150 - 8, 100 - 24, 16, 16),
      'dpadDown': const Rect.fromLTWH(150 - 8, 100 + 8, 16, 16),
      // Action buttons center at (350,100): Y(0,-25) A(0,25) X(-25,0) B(25,0) with r=16
      'buttonY': const Rect.fromLTWH(350 - 16, 100 - 25 - 16, 32, 32),
      'buttonA': const Rect.fromLTWH(350 - 16, 100 + 25 - 16, 32, 32),
      'buttonX': const Rect.fromLTWH(350 - 25 - 16, 100 - 16, 32, 32),
      'buttonB': const Rect.fromLTWH(350 + 25 - 16, 100 - 16, 32, 32),
      // Center buttons (Select/Start) at translate(210,110)
      'pauseButton': const Rect.fromLTWH(250, 110, 36, 14), // map pause to START
      // Remote pseudo buttons at bottom
      'previousTrack': const Rect.fromLTWH(120, 192, 80, 18),
      'play': const Rect.fromLTWH(210, 192, 80, 18),
      'nextTrack': const Rect.fromLTWH(300, 192, 80, 18),
    };

    final allMappings = InputMappingService.instance.mapping;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = height;

        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // SVG本体
              Positioned.fill(
                child: SvgPicture.asset(
                  showRemote
                      ? 'assets/additional_images/remote_controller_svg.svg'
                      : 'assets/additional_images/game_controller_svg.svg',
                  fit: BoxFit.contain,
                ),
              ),
              // SVG内の <g id="hotspots"> の rect をパースしてホットスポット化
              FutureBuilder<String>(
                future: DefaultAssetBundle.of(context).loadString(
                    showRemote
                        ? 'assets/additional_images/remote_controller_svg.svg'
                        : 'assets/additional_images/game_controller_svg.svg'),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final svgText = snap.data!;
                  final rects = _parseHotspotsFromSvg(svgText);
                  final vb = _parseViewBox(svgText);
                  final svgW = vb.$1;
                  final svgH = vb.$2;
                  final scale = (boxW / svgW < boxH / svgH) ? (boxW / svgW) : (boxH / svgH);
                  final imgW = svgW * scale;
                  final imgH = svgH * scale;
                  final offX = (boxW - imgW) / 2.0;
                  final offY = (boxH - imgH) / 2.0;
                  return Stack(children: [
                    for (final e in rects.entries)
                      _hotspotNorm(
                        x: offX + e.value.left * scale,
                        y: offY + e.value.top * scale,
                        w: e.value.width * scale,
                        h: e.value.height * scale,
                        id: e.key,
                        selected: selected.contains(e.key),
                        alsoUsedElsewhere: allMappings.entries.any((m) => m.key != currentAction && (m.value.contains(e.key))),
                      ),
                  ]);
                },
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

// 簡易SVGパーサ: <g id="hotspots"> の直下にある <rect id=.. x=.. y=.. width=.. height=.. /> を抽出
Map<String, Rect> _parseHotspotsFromSvg(String svg) {
  final Map<String, Rect> rects = {};
  final gStart = svg.indexOf('<g id="hotspots"');
  if (gStart < 0) return rects;
  final gEnd = svg.indexOf('</g>', gStart);
  if (gEnd < 0) return rects;
  final hot = svg.substring(gStart, gEnd);
  final reg = RegExp(r'<rect[^>]*id\s*=\s*"([^"]+)"[^>]*x\s*=\s*"([0-9.]+)"[^>]*y\s*=\s*"([0-9.]+)"[^>]*width\s*=\s*"([0-9.]+)"[^>]*height\s*=\s*"([0-9.]+)"[^>]*/?>');
  for (final m in reg.allMatches(hot)) {
    final id = m.group(1)!;
    final x = double.parse(m.group(2)!);
    final y = double.parse(m.group(3)!);
    final w = double.parse(m.group(4)!);
    final h = double.parse(m.group(5)!);
    rects[id] = Rect.fromLTWH(x, y, w, h);
  }
  return rects;
}

/// Extracts viewBox width/height from the <svg> tag. Falls back to 500x220.
(double, double) _parseViewBox(String svg) {
  final m = RegExp(r'<svg[^>]*viewBox\s*=\s*"([^"]+)"', caseSensitive: false)
      .firstMatch(svg);
  if (m == null) return (500, 220);
  final parts = m.group(1)!.trim().split(RegExp(r"\s+"));
  if (parts.length != 4) return (500, 220);
  final w = double.tryParse(parts[2]) ?? 500;
  final h = double.tryParse(parts[3]) ?? 220;
  return (w, h);
}
