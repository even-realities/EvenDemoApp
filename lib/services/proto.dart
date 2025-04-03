import 'dart:convert';
import 'dart:typed_data';

import 'package:demo_ai_even/ble_manager.dart'; // Assuming this path is correct
import 'package:demo_ai_even/services/evenai_proto.dart'; // Assuming this path is correct
import 'package:demo_ai_even/utils/utils.dart'; // Assuming this path is correct

class Proto {
  // =========================================================================
  // === NEW FUNCTIONS FOR MUSIC WIDGET / GENERAL TEXT DISPLAY             ===
  // =========================================================================

  /// Formats text into lines and screens based on estimated dimensions.
  /// !!! PLACEHOLDER - Needs proper text measurement logic for accuracy !!!
  static Map<String, dynamic> formatTextForDisplay(String text,
      {int maxWidthPx = 488, int fontSize = 21, int linesPerScreen = 5}) {
    // Replace this with accurate logic using Platform Channels or TextPainter approximation
    int approxCharsPerLine = maxWidthPx ~/ (fontSize * 0.6); // Very rough estimate
    List<String> lines = [];
    LineSplitter ls = const LineSplitter();
    List<String> rawLines = ls.convert(text);
    for (var rawLine in rawLines) {
      if (rawLine.isEmpty) {
        lines.add(''); // Keep empty lines
        continue;
      }
      if (rawLine.length <= approxCharsPerLine) {
        lines.add(rawLine);
      } else {
        // Simple wrapping
        for (int i = 0; i < rawLine.length; i += approxCharsPerLine) {
          lines.add(rawLine.substring(
              i,
              (i + approxCharsPerLine > rawLine.length)
                  ? rawLine.length
                  : i + approxCharsPerLine));
        }
      }
    }
    List<List<String>> screens = [];
    if (lines.isEmpty && text.isNotEmpty) {
      // Handle case where formatting fails badly
      screens.add(["Error"]);
    } else if (lines.isEmpty && text.isEmpty) {
      screens.add([""]); // Ensure empty text sends one empty screen
    } else {
      for (int i = 0; i < lines.length; i += linesPerScreen) {
        screens.add(lines.sublist(
            i,
            (i + linesPerScreen > lines.length)
                ? lines.length
                : i + linesPerScreen));
      }
    }
    // Ensure totalPages is at least 1 if sending empty or only one screen
    int totalPages = screens.isEmpty ? 1 : screens.length;
    return {'screens': screens, 'totalPages': totalPages};
  }

  /// Builds a single 0x4E text packet for Music/General Text Display.
  static Uint8List buildTextPacket({
    required int seq,
    required int totalPackagesForScreen, // How many packets for THIS screen
    required int currentPackageNumForScreen, // Index of THIS packet for the screen (0-based)
    required String screenDataChunk, // The text data for THIS specific packet
    required int currentPageNum, // Index of the current screen (0-based)
    required int maxPageNum, // Total number of screens
  }) {
    List<int> header = [];
    // Ensure empty chunks are encoded as something (e.g., space) if needed by glasses
    String dataToSend = screenDataChunk.isEmpty ? " " : screenDataChunk;
    Uint8List dataBytes = Uint8List.fromList(utf8.encode(dataToSend));

    header.add(0x4E); // Command
    header.add(seq & 0xFF); // Sequence number
    header.add(totalPackagesForScreen & 0xFF);
    header.add(currentPackageNumForScreen & 0xFF);
    // ***** Use 0x71 for generic Text Show state *****
    header.add(0x71); // newscreen: 0x70 (Text Show) + 0x01 (New Content)
    // ***** Use 0x00 for default position *****
    header.add(0x00); // new_char_pos0 (Higher 8 bits)
    header.add(0x00); // new_char_pos1 (Lower 8 bits)
    header.add(currentPageNum & 0xFF);
    // Ensure maxPageNum is at least 1
    header.add((maxPageNum <= 0 ? 1 : maxPageNum) & 0xFF);

    // Combine header and data, respecting MTU (~251 -> payload ~230-240)
    int maxDataLength = 230 - header.length; // Safe estimate based on MTU 251
    if (dataBytes.length > maxDataLength) {
      print("Warning: Truncating text packet data!");
      dataBytes = dataBytes.sublist(0, maxDataLength);
    }

    return Uint8List.fromList([...header, ...dataBytes]);
  }

  // =========================================================================
  // === ORIGINAL FUNCTIONS FROM YOUR PROVIDED CODE                      ===
  // =========================================================================

  static String lR() {
    // todo: Re-evaluate this logic if needed. Does BleManager provide a better way?
    if (BleManager.isBothConnected()) return "R";
    //if (BleManager.isConnectedR()) return "R"; // Check if BleManager has individual checks
    return "L"; // Default or fallback
  }

  /// Turns the microphone on.
  /// Returns the estimated time the command was processed and whether it was successful.
  static Future<(int, bool)> micOn({
    String? lr, // Allow specifying L/R if needed, otherwise defaults based on request logic
  }) async {
    var begin = Utils.getTimestampMs();
    var data = Uint8List.fromList([0x0E, 0x01]); // Command: Enable Mic
    // Use requestRetry for robustness if simple request fails often
    var receive = await BleManager.request(data, lr: lr);

    var end = Utils.getTimestampMs();
    // Estimate midpoint time, could be useful for latency calculations
    var startMic = (begin + ((end - begin) ~/ 2));

    print("Proto---micOn---estimated process time---$startMic-------");
    // Check response: Not timed out and status byte (index 1) is success (0xC9)
    return (startMic, (!receive.isTimeout && receive.data.length > 1 && receive.data[1] == 0xc9));
  }

  /// Even AI related sequence number
  static int _evenaiSeq = 0;

  /// Sends AI result text using the 0x4E command.
  /// Relies on EvenaiProto helper for packetization specific to AI state.
  static Future<bool> sendEvenAIData(String text,
      {int? timeoutMs,
      required int newScreen, // Specific state code for EvenAI
      required int pos,       // Specific position code for EvenAI
      required int current_page_num,
      required int max_page_num}) async {

    var data = utf8.encode(text);
    var syncSeq = _evenaiSeq & 0xff; // Use lower 8 bits for sequence

    // Uses a specific helper to create packets for EvenAI state
    List<Uint8List> dataList = EvenaiProto.evenaiMultiPackListV2(0x4E,
        data: data,
        syncSeq: syncSeq,
        newScreen: newScreen,
        pos: pos,
        current_page_num: current_page_num,
        max_page_num: max_page_num);
    _evenaiSeq++; // Increment sequence number for next call

    print(
        '${DateTime.now()} proto--sendEvenAIData---text---$text---_evenaiSeq----$_evenaiSeq---newScreen---$newScreen---pos---$pos---current_page_num--$current_page_num---max_page_num--$max_page_num--dataList----$dataList---');

    // Send list sequentially to Left, then Right using requestList
    bool isSuccess = await BleManager.requestList(dataList,
        lr: "L", timeoutMs: timeoutMs ?? 2000); // Use provided or default timeout

    print('${DateTime.now()} sendEvenAIData-----L success-----$isSuccess-------');
    if (!isSuccess) {
      print("${DateTime.now()} sendEvenAIData failed L ");
      return false; // Fail early if Left side fails
    } else {
      // Proceed to send to Right side only if Left succeeded
      isSuccess = await BleManager.requestList(dataList,
          lr: "R", timeoutMs: timeoutMs ?? 2000);

      if (!isSuccess) {
        print("${DateTime.now()} sendEvenAIData failed R ");
        return false; // Fail if Right side fails
      }
      print('${DateTime.now()} sendEvenAIData-----R success-----$isSuccess-------');
      return true; // Both sides succeeded
    }
  }

  /// Heartbeat related sequence number
  static int _beatHeartSeq = 0;

  /// Sends a heartbeat command (0x25) to keep connection alive or check status.
  static Future<bool> sendHeartBeat() async {
    var length = 6; // Fixed length for this heartbeat command
    var seqByte = _beatHeartSeq & 0xff; // Use lower 8 bits for sequence

    var data = Uint8List.fromList([
      0x25,         // Command: Heartbeat
      length & 0xff, // Length LSB
      (length >> 8) & 0xff, // Length MSB (likely 0)
      seqByte,      // Sequence number
      0x04,         // Parameter specific to heartbeat?
      seqByte,      // Parameter repeated? (or checksum?)
    ]);
    _beatHeartSeq++; // Increment for next beat

    print('${DateTime.now()} sendHeartBeat--------data---$data--');
    // Send to Left and wait for response
    var ret = await BleManager.request(data, lr: "L", timeoutMs: 1500);

    print('${DateTime.now()} sendHeartBeat----L----ret---${ret.data.hexString}--'); // Log hex data
    if (ret.isTimeout) {
      print('${DateTime.now()} sendHeartBeat----L----time out--');
      return false;
    }
    // Check specific response pattern for Left
    else if (ret.data.isNotEmpty && // Check length before accessing indices
               ret.data[0] == 0x25 &&
               ret.data.length > 4 && // Ensure index 4 exists
               ret.data[4] == 0x04) {

      // If Left is OK, send to Right and wait for response
      var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
      print('${DateTime.now()} sendHeartBeat----R----retR---${retR.data.hexString}--'); // Log hex data
      if (retR.isTimeout) {
        print('${DateTime.now()} sendHeartBeat----R----time out--');
        return false;
      }
      // Check specific response pattern for Right
      else if (retR.data.isNotEmpty && // Check length
                 retR.data[0] == 0x25 &&
                 retR.data.length > 4 && // Ensure index 4 exists
                 retR.data[4] == 0x04) {
        print('${DateTime.now()} sendHeartBeat----Success Both--');
        return true; // Both responded correctly
      } else {
        print('${DateTime.now()} sendHeartBeat----R----Bad Response--');
        return false; // Right response incorrect
      }
    } else {
      print('${DateTime.now()} sendHeartBeat----L----Bad Response--');
      return false; // Left response incorrect
    }
  }

  /// Gets the serial number (SN) from a specific leg (Left or Right).
  static Future<String> getLegSn(String lr) async {
    var cmd = Uint8List.fromList([0x34]); // Command: Get SN?
    var resp = await BleManager.request(cmd, lr: lr); // Send to specified leg

    if (resp.isTimeout || resp.data.length < 18) { // Check for timeout and sufficient length
        print("getLegSn($lr) failed: Timeout or insufficient data length (${resp.data.length})");
        return "Error"; // Return error string or throw exception
    }

    // Extract bytes assuming SN is at indices 2-17 (16 bytes)
    var snBytes = resp.data.sublist(2, 18);
    try {
        // Attempt to decode as ASCII/UTF-8 (adjust if encoding is different)
        var sn = String.fromCharCodes(snBytes).trim(); // Trim whitespace
        print("getLegSn($lr): Success, SN = $sn");
        return sn;
    } catch (e) {
        print("getLegSn($lr) failed: Error decoding SN bytes - $e");
        return "Decode Error"; // Return error string
    }
  }

  /// Sends a command (0x18) to tell the glasses to exit the current function/feature.
  static Future<bool> exit() async {
    print("Proto: Sending exit command (0x18)");
    var data = Uint8List.fromList([0x18]); // Command: Exit

    // Send to Left
    var retL = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    print('${DateTime.now()} exit----L----ret---${retL.data.hexString}--');
    if (retL.isTimeout) {
      print('${DateTime.now()} exit----L----Timeout--');
      return false;
    }
    // Check response: Not timeout, has data, status byte (index 1) is success (0xC9)
    else if (retL.data.isNotEmpty && retL.data.length > 1 && retL.data[1] == 0xc9) {
      // If Left OK, send to Right
      var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
      print('${DateTime.now()} exit----R----retR---${retR.data.hexString}--');
      if (retR.isTimeout) {
        print('${DateTime.now()} exit----R----Timeout--');
        return false;
      }
      // Check response for Right
      else if (retR.data.isNotEmpty && retR.data.length > 1 && retR.data[1] == 0xc9) {
        print('${DateTime.now()} exit----Success Both--');
        return true; // Both succeeded
      } else {
        print('${DateTime.now()} exit----R----Bad Response--');
        return false; // Right failed
      }
    } else {
      print('${DateTime.now()} exit----L----Bad Response--');
      return false; // Left failed
    }
  }

  /// Internal helper to split data into packets with a specific command/sequence header.
  static List<Uint8List> _getPackList(int cmd, Uint8List data,
      {int count = 20}) { // Default packet size seems small? Check usage.
    // Calculate data payload size per packet (total size - 3 header bytes)
    final realCount = count - 3;
    if (realCount <= 0) {
       print("Error: Packet size 'count' ($count) must be greater than 3.");
       return [];
    }

    List<Uint8List> send = [];
    int maxSeq = data.length ~/ realCount; // Total number of full packets
    if (data.length % realCount > 0) {
      maxSeq++; // Add one more packet for the remainder
    }
    // Ensure maxSeq fits in a byte if needed, though it's used as an int here
    // maxSeq = maxSeq > 255 ? 255 : maxSeq; // Clamp if necessary

    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * realCount;
      var end = start + realCount;
      if (end > data.length) {
        end = data.length; // Adjust end for the last packet
      }
      var itemData = data.sublist(start, end);
      // Header: [Command, Total Packets (maxSeq), Current Packet Index (seq)]
      // Use the external Utils helper to prepend the header
      var pack = Utils.addPrefixToUint8List([cmd, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }

  /// Sends a new app whitelist JSON string to the glasses (using command 0x04).
  static Future<void> sendNewAppWhiteListJson(String whitelistJson) async {
    print("proto -> sendNewAppWhiteListJson: whitelist = $whitelistJson");
    final whitelistData = utf8.encode(whitelistJson); // Encode JSON to bytes

    // Split data into packets using command 0x04 and a larger packet size (180)
    final dataList = _getPackList(0x04, whitelistData, count: 180);
    print(
        "proto -> sendNewAppWhiteListJson: length = ${dataList.length}, dataList preview = ${dataList.isNotEmpty ? dataList.first.hexString : '[]'}");

    // Try sending the list to the Left leg up to 3 times
    for (var i = 0; i < 3; i++) {
      print("proto -> sendNewAppWhiteListJson: Attempt ${i+1}/3");
      final isSuccess =
          await BleManager.requestList(dataList, timeoutMs: 300, lr: "L");
      if (isSuccess) {
        print("proto -> sendNewAppWhiteListJson: Success on attempt ${i+1}");
        return; // Exit if successful
      }
       print("proto -> sendNewAppWhiteListJson: Failed attempt ${i+1}");
       await Future.delayed(const Duration(milliseconds: 100)); // Small delay before retry
    }
     print("proto -> sendNewAppWhiteListJson: Failed after 3 attempts.");
  }

  /// Sends notification data (as JSON) to the glasses using command 0x4B.
  static Future<void> sendNotify(Map appData, int notifyId,
      {int retry = 6}) async {
    // Wrap the app data into the expected JSON structure
    final notifyJson = jsonEncode({
      "ncs_notification": appData,
    });
    final notifyDataBytes = utf8.encode(notifyJson); // Encode to bytes

    // Split into packets using the specific notification format
    final dataList = _getNotifyPackList(0x4B, notifyId, notifyDataBytes);
    print(
        "proto -> sendNotify: notifyId = $notifyId, data length = ${dataList.length}, app = $notifyJson");
    print("proto -> sendNotify: dataList preview = ${dataList.isNotEmpty ? dataList.first.hexString : '[]'}");


    // Try sending the list to the Left leg up to 'retry' times
    for (var i = 0; i < retry; i++) {
       print("proto -> sendNotify: Attempt ${i+1}/$retry");
      // Use a longer timeout for potentially larger notification data
      final isSuccess =
          await BleManager.requestList(dataList, timeoutMs: 1000, lr: "L");
      if (isSuccess) {
        print("proto -> sendNotify: Success on attempt ${i+1}");
        return; // Exit if successful
      }
      print("proto -> sendNotify: Failed attempt ${i+1}");
      await Future.delayed(const Duration(milliseconds: 100)); // Small delay before retry
    }
     print("proto -> sendNotify: Failed after $retry attempts.");
  }

  /// Internal helper to split notification data into packets with command/msgId/sequence header.
  static List<Uint8List> _getNotifyPackList(
      int cmd, int msgId, Uint8List data) {

    final int payloadSize = 176; // Data payload size per packet for notifications
    if (payloadSize <= 0) {
       print("Error: Notification payload size must be positive.");
       return [];
    }

    List<Uint8List> send = [];
    // Calculate total packets needed
    int maxSeq = data.length ~/ payloadSize;
    if (data.length % payloadSize > 0) {
      maxSeq++;
    }
    // maxSeq = maxSeq > 255 ? 255 : maxSeq; // Clamp if maxSeq needs to fit in a byte

    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * payloadSize;
      var end = start + payloadSize;
      if (end > data.length) {
        end = data.length; // Adjust end for the last packet
      }
      var itemData = data.sublist(start, end);
      // Header: [Command, Message ID, Total Packets, Current Packet Index]
      var pack =
          Utils.addPrefixToUint8List([cmd, msgId, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }

} // End of Proto class definition