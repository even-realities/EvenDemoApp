import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/services/api_services_deepseek.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class EvenAI {
  static EvenAI? _instance;
  static EvenAI get get => _instance ??= EvenAI._();

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  bool isReceivingAudio = false;
  List<int> audioDataBuffer = [];
  Uint8List? audioData;

  File? lc3File;
  File? pcmFile;
  int durationS = 0;

  static int maxRetry = 10;
  static int _currentLine = 0;
  static Timer? _timer; // Text sending timer
  static List<String> list = [];
  static List<String> sendReplys = [];

  Timer? _recordingTimer;
  final int maxRecordingDuration = 30; // todo

  static bool _isManual = false; 

  static set isRunning(bool value) {
    _isRunning = value;
    isEvenAIOpen.value = value;

    isEvenAISyncing.value = value;
  }

  static RxBool isEvenAIOpen = false.obs;

  static RxBool isEvenAISyncing = false.obs;

  int _lastStartTime = 0; // Avoid repeated startup commands of Android Bluetooth in a short period of time
  int _lastStopTime = 0; // Avoid repeated termination commands of Android Bluetooth within a short period of time
  final int startTimeGap = 500; // Filter repeated Bluetooth intervals
  final int stopTimeGap = 500;

  static const _eventSpeechRecognize = "eventSpeechRecognize"; 
  final _eventSpeechRecognizeChannel =
      const EventChannel(_eventSpeechRecognize).receiveBroadcastStream(_eventSpeechRecognize);

  String combinedText = '';

  static final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  static Stream<String> get textStream => _textStreamController.stream;

  static void updateDynamicText(String newText) {
    _textStreamController.add(newText);
  }

  EvenAI._(); 

  void startListening() {
    combinedText = '';
    _eventSpeechRecognizeChannel.listen((event) {
      var txt = event["script"] as String;
      combinedText = txt;
    }, onError: (error) {
      print("Error in event: $error");
    });
  }

  // receiving starting Even AI request from ble
  void toStartEvenAIByOS() async {
    // restart to avoid ble data conflict
    BleManager.get().startSendBeatHeart();

    startListening(); 
    
    // avoid duplicate ble command in short time, especially android
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStartTime < startTimeGap) {
      return;
    }

    _lastStartTime = currentTime;

    clear();
    isReceivingAudio = true;

    isRunning = true;
    _currentLine = 0;

    await BleManager.invokeMethod("startEvenAI");
    
    await openEvenAIMic();

    startRecordingTimer();
  }

  // Monitor the recording time to prevent the recording from ending when the OS exits unexpectedly
  void startRecordingTimer() {
    _recordingTimer = Timer(Duration(seconds: maxRecordingDuration), () {
      if (isReceivingAudio) {
        print("${DateTime.now()} Even AI startRecordingTimer-----exit-----");
        clear();
        //Proto.exit();
      } else {
        _recordingTimer?.cancel();
        _recordingTimer = null;
      }
    });
  }

  // 收到眼镜端Even AI录音结束指令
  Future<void> recordOverByOS() async {
    print('${DateTime.now()} EvenAI -------recordOverByOS-------');

    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStopTime < stopTimeGap) {
      return;
    }
    _lastStopTime = currentTime;

    isReceivingAudio = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    await BleManager.invokeMethod("stopEvenAI");
    await Future.delayed(Duration(seconds: 2)); // todo

    print("recordOverByOS----startSendReply---pre------combinedText-------*$combinedText*---");

    if (combinedText.isEmpty) {
      
      updateDynamicText("No Speech Recognized");
      isEvenAISyncing.value = false;
      startSendReply("No Speech Recognized");
      return;
    }

    final apiService = ApiDeepSeekService();
    String answer = await apiService.sendChatRequest(combinedText);
  
    print("recordOverByOS----startSendReply---combinedText-------*$combinedText*-----answer----$answer----");

    updateDynamicText("$combinedText\n\n$answer");
    isEvenAISyncing.value = false;
    saveQuestionItem(combinedText, answer);
    startSendReply(answer);
  }

  void saveQuestionItem(String title, String content) {
    print("saveQuestionItem----title----$title----content---$content-");
    final controller = Get.find<EvenaiModelController>();
    controller.addItem(title, content);
  }

  int getTotalPages() {
    if (list.isEmpty) {
      return 0;
    }
    if (list.length < 6) {
      return 1;
    }
    int pages = 0;
    int div = list.length ~/ 5;
    int rest = list.length % 5;
    pages = div;
    if (rest != 0) {
      pages++;
    }
    return pages;
  }

  int getCurrentPage() {
    if (_currentLine == 0) {
      return 1;
    }
    int currentPage = 1;
    int div = _currentLine ~/ 5;
    int rest = _currentLine % 5;
    currentPage = 1 + div;
    if (rest != 0) {
      currentPage++;
    }
    return currentPage;
  }

  Future sendNetworkErrorReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);

    String ryplyWords =
        list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
    String headString = '\n\n';
    ryplyWords = headString + ryplyWords;

    // After sending the network error prompt glasses, exit automatically
    await sendEvenAIReply(ryplyWords, 0x01, 0x60, 0);
    clear();
  }

  Future startSendReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);
   
    if (list.length < 4) {
      String startScreenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      startScreenWords = headString + startScreenWords;

      // Switch to Text Show to avoid EvenAI listening UI
      bool isSuccess = await sendEvenAIReply(startScreenWords, 0x01, 0x70, 0);
      return;
    }
    if (list.length == 4) {
      String startScreenWords =
          list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      startScreenWords = headString + startScreenWords;

      // Text Show (no 0x40 finalize)
      bool isSuccess = await sendEvenAIReply(startScreenWords, 0x01, 0x70, 0);
      return;
    }

    if (list.length == 5) {
      String startScreenWords =
          list.sublist(0, 5).map((str) => '$str\n').join();
      // Text Show (no 0x40 finalize)
      bool isSuccess = await sendEvenAIReply(startScreenWords, 0x01, 0x70, 0);
      return;
    }

    String startScreenWords = list.sublist(0, 5).map((str) => '$str\n').join();
    // Text Show first page instead of EvenAI display
    bool isSuccess = await sendEvenAIReply(startScreenWords, 0x01, 0x70, 0);

    if (isSuccess) {
      _currentLine = 0;
      await updateReplyToOSByTimer();
    } else {
      clear(); 
    }
  }

  Future updateReplyToOSByTimer() async {

    int interval = 5; // The paging interval can be customized
   
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      // Switched to manual mode, abolished timer update
      if (_isManual) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      _currentLine = min(_currentLine + 5, list.length - 1);
      sendReplys = list.sublist(_currentLine);

      if (_currentLine > list.length - 1) {
        _timer?.cancel();
        _timer = null;
      } else {
        if (sendReplys.length < 4) {
          var mergedStr = sendReplys
              .sublist(0, sendReplys.length)
              .map((str) => '$str\n')
              .join();

          await sendEvenAIReply(mergedStr, 0x01, 0x70, 0);
        } else {
          var mergedStr = sendReplys
              .sublist(0, min(5, sendReplys.length))
              .map((str) => '$str\n')
              .join();

          await sendEvenAIReply(mergedStr, 0x01, 0x70, 0);
        }
      }
    });
  }

  // Click the TouchBar on the right to turn the page down
  void nextPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine + 5 > list.length - 1) {
      return;
    } else {
      _currentLine += 5;
    }
    updateReplyToOSByManual();
  }

  // Click the TouchBar on the right to turn the page down
  void lastPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine - 5 < 0) {
      _currentLine == 0;
    } else {
      _currentLine -= 5;
    }
    updateReplyToOSByManual();
  }

  Future updateReplyToOSByManual() async {
    if (_currentLine < 0 || _currentLine > list.length - 1) {
      return;
    }

    sendReplys = list.sublist(_currentLine);
    if (sendReplys.length < 4) {
      var mergedStr = sendReplys
          .sublist(0, sendReplys.length)
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x70, 0);
    } else {
      var mergedStr = sendReplys
          .sublist(0, min(5, sendReplys.length))
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x70, 0);
    }
  }

  // When there is only one page of text, click the page turn TouchBar
  Future manualForJustOnePage() async {
    if (list.length < 4) {
      String screenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x70, 0);
      return;
    }

    if (list.length == 4) {
      String screenWords = list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x70, 0);
      return;
    }

    if (list.length == 5) {
      String screenWords = list.sublist(0, 5).map((str) => '$str\n').join();

      await sendEvenAIReply(screenWords, 0x01, 0x70, 0);
      return;
    }
  }

  Future stopEvenAIByOS() async {
    isRunning = false;
    clear();

    await BleManager.invokeMethod("stopEvenAI");
  }

  void clear() {
    isReceivingAudio = false;
    isRunning = false;
    _isManual = false;
    _currentLine = 0;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _timer?.cancel();
    _timer = null;
    audioDataBuffer.clear();
    audioDataBuffer = [];
    audioData = null;
    list = [];
    sendReplys = [];
    durationS = 0;
    retryCount = 0;
  }

  Future openEvenAIMic() async {
    final (micStartMs, isStartSucc) = await Proto.micOn(lr: "R"); 
    print(
        '${DateTime.now()} openEvenAIMic---isStartSucc----$isStartSucc----micStartMs---$micStartMs---');
    
    if (!isStartSucc && isReceivingAudio && isRunning) {
      await Future.delayed(Duration(seconds: 1));
      await openEvenAIMic();
    }
  }

  // Send text data to the glasses，including status information
  int retryCount = 0;
  Future<bool> sendEvenAIReply(
      String text, int type, int status, int pos) async {
    // todo
    print('${DateTime.now()} sendEvenAIReply---text----$text-----type---$type---status---$status----pos---$pos-');
    if (!isRunning) {
      return false;
    }

    bool isSuccess = await Proto.sendEvenAIData(text,
        newScreen: EvenAIDataMethod.transferToNewScreen(type, status),
        pos: pos,
        current_page_num: getCurrentPage(),
        max_page_num: getTotalPages()); // todo pos
    if (!isSuccess) {
      if (retryCount < maxRetry) {
        retryCount++;
        await sendEvenAIReply(text, type, status, pos);
      } else {
        retryCount = 0;
        // todo
        return false;
      }
    }
    retryCount = 0;
    return true;
  }

  static void dispose() {
    _textStreamController.close();
  }
}

extension EvenAIDataMethod on EvenAI {
  static int transferToNewScreen(int type, int status) {
    int newScreen = status | type;
    return newScreen;
  }

  static List<String> measureStringList(String text, [double? maxW]) {
    final double maxWidth = maxW ?? 488; 
    const double fontSize = 21; // legacy default

    List<String> paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    List<String> ret = [];

    TextStyle ts = TextStyle(fontSize: fontSize);

    for (String paragraph in paragraphs) {
      final textSpan = TextSpan(text: paragraph, style: ts);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: null,
      );

      textPainter.layout(maxWidth: maxWidth);

      final lineCount = textPainter.computeLineMetrics().length;

      var start = 0;
      for (var i = 0; i < lineCount; i++) {
        final line = textPainter.getLineBoundary(TextPosition(offset: start));
        ret.add(paragraph.substring(line.start, line.end).trim());
        start = line.end;
      }
    }
    return ret;
  }

  /// Advanced splitter allowing custom maxWidth and fontSize.
  /// Defaults mimic the legacy behavior (488, 21).
  static List<String> measureStringListAdvanced(
    String text, {
    double? maxWidth,
    double fontSize = 21,
  }) {
    final double mw = maxWidth ?? 488;

    final List<String> paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final List<String> ret = [];
    final TextStyle ts = TextStyle(fontSize: fontSize);

    for (final String paragraph in paragraphs) {
      final textSpan = TextSpan(text: paragraph, style: ts);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: null,
      );
      textPainter.layout(maxWidth: mw);

      final int lineCount = textPainter.computeLineMetrics().length;
      var start = 0;
      for (var i = 0; i < lineCount; i++) {
        final line = textPainter.getLineBoundary(TextPosition(offset: start));
        ret.add(paragraph.substring(line.start, line.end).trim());
        start = line.end;
      }
    }
    return ret;
  }
}
