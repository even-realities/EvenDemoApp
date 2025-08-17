import 'dart:async';
import 'dart:math';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';

class CustomTextService {
  bool isRunning = false;
  int maxRetry = 5;
  int _currentLine = 0;
  Timer? _timer;
  List<String> _lines = [];
  int retryCount = 0;

  // 状態変更をUIに通知するためのコールバック
  Function()? onPageChanged;

  // テキストをセットアップし、ページに分割
  void setupText(String text) {
    _lines = EvenAIDataMethod.measureStringList(text);
    _currentLine = 0;
    isRunning = true;
  }

  // 最初のページを送信
  Future<void> sendFirstPage() async {
    if (!isRunning) return;
    String pageText = _getPageTextForLine(_currentLine);
    await _sendText(pageText, 0x01, 0x70, 0);
    onPageChanged?.call();
  }

  // 次のページを送信
  Future<void> sendNextPage() async {
    if (!isRunning || _currentLine + 5 >= _lines.length) return;
    _currentLine += 5;
    String pageText = _getPageTextForLine(_currentLine);
    await _sendText(pageText, 0x01, 0x70, 0);
    onPageChanged?.call();
  }

  // 前のページを送信
  Future<void> sendPreviousPage() async {
    if (!isRunning || _currentLine <= 0) return;
    _currentLine = max(0, _currentLine - 5);
    String pageText = _getPageTextForLine(_currentLine);
    await _sendText(pageText, 0x01, 0x70, 0);
    onPageChanged?.call();
  }

  // 自動スクロールを開始
  void startAutoScroll(int seconds) {
    stopAutoScroll(); // 既存のタイマーは停止
    if (!isRunning) return;
    _timer = Timer.periodic(Duration(seconds: seconds), (timer) async {
      if (_currentLine + 5 >= _lines.length) {
        stopAutoScroll(); // 最後のページに達したら停止
      } else {
        await sendNextPage();
      }
    });
  }

  // 自動スクロールを停止
  void stopAutoScroll() {
    _timer?.cancel();
    _timer = null;
  }

  // 内部的なテキスト送信メソッド
  Future<bool> _sendText(String text, int type, int status, int pos) async {
    if (!isRunning) return false;

    bool isSuccess = await Proto.sendEvenAIData(text,
        newScreen: EvenAIDataMethod.transferToNewScreen(type, status),
        pos: pos,
        current_page_num: getCurrentPage(),
        max_page_num: getTotalPages());

    if (!isSuccess && retryCount < maxRetry) {
      retryCount++;
      return await _sendText(text, type, status, pos);
    } else {
      retryCount = 0;
      return isSuccess;
    }
  }

  // 現在の行番号から表示用テキストを取得
  String _getPageTextForLine(int line) {
    final end = min(line + 5, _lines.length);
    final pageLines = _lines.sublist(line, end);
    return pageLines.map((str) => '$str\n').join();
  }

  // 総ページ数を取得
  int getTotalPages() {
    if (_lines.isEmpty) return 0;
    return (_lines.length / 5).ceil();
  }

  // 現在のページ番号を取得
  int getCurrentPage() {
    if (_lines.isEmpty) return 0;
    return (_currentLine / 5).floor() + 1;
  }

  // 状態をクリア
  void clear() {
    isRunning = false;
    _currentLine = 0;
    stopAutoScroll();
    _lines = [];
    retryCount = 0;
  }
}
