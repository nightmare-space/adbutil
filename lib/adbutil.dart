library adbutil;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:global_repository/global_repository.dart';

import 'foundation/exception.dart';

export 'foundation/exception.dart';

class AdbResult {
  AdbResult(this.message);

  final String message;
}

class Arg {
  final String package;
  final String cmd;

  Arg(this.package, this.cmd);
}

Future<String> asyncExec(String cmd) async {
  if (kDebugMode) {
    return execCmd(cmd);
  }
  return await compute(execCmdForIsolate, Arg(RuntimeEnvir.packageName, cmd));
}

Future<String> execCmdForIsolate(
  Arg arg, {
  bool throwException = true,
}) async {
  RuntimeEnvir.initEnvirWithPackageName(arg.package);
  Map<String, String> envir = RuntimeEnvir.envir();
  envir['TMPDIR'] = RuntimeEnvir.binPath;
  envir['LD_LIBRARY_PATH'] = RuntimeEnvir.binPath;
  final List<String> args = arg.cmd.split(' ');
  ProcessResult execResult;
  if (Platform.isWindows) {
    Log.e(RuntimeEnvir.envir()['PATH']);
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: RuntimeEnvir.envir(),
      includeParentEnvironment: true,
      runInShell: true,
    );
  } else {
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: envir,
      includeParentEnvironment: true,
      runInShell: false,
    );
  }
  if ('${execResult.stderr}'.isNotEmpty) {
    if (throwException) {
      Log.w('adb stderr -> ${execResult.stderr}');
    }
  }
  // Log.e('adb stdout -> ${execResult.stdout}');
  return execResult.stdout.toString().trim();
}

Future<String> execCmd(
  String cmd, {
  bool throwException = true,
}) async {
  final List<String> args = cmd.split(' ');
  Map<String, String> envir = RuntimeEnvir.envir();
  envir['TMPDIR'] = RuntimeEnvir.binPath;
  envir['LD_LIBRARY_PATH'] = RuntimeEnvir.binPath;
  ProcessResult execResult;
  if (Platform.isWindows) {
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: RuntimeEnvir.envir(),
      includeParentEnvironment: true,
      runInShell: true,
    );
  } else {
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: envir,
      includeParentEnvironment: true,
      runInShell: false,
    );
  }
  if ('${execResult.stderr}'.isNotEmpty) {
    if (throwException) {
      Log.w('adb stderr -> ${execResult.stderr}');
      throw Exception(execResult.stderr);
    }
  }
  // Log.e('adb stdout -> ${execResult.stdout}');
  return execResult.stdout.toString().trim();
}

// ???????????????split(' ')???????????????????????????????????????
// ?????????????????????????????????????????????????????????
Future<String> execCmd2(List<String> args) async {
  ProcessResult execResult;
  if (Platform.isWindows) {
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: RuntimeEnvir.envir(),
      includeParentEnvironment: true,
      runInShell: true,
    );
  } else {
    execResult = await Process.run(
      args[0],
      args.sublist(1),
      environment: RuntimeEnvir.envir(),
      includeParentEnvironment: true,
      runInShell: false,
    );
  }
  if ('${execResult.stderr}'.isNotEmpty) {
    // Log.w('adb stderr -> ${execResult.stderr}');
    throw Exception(execResult.stderr);
  }
  // Log.e('adb stdout -> ${execResult.stdout}');
  return execResult.stdout.toString().trim();
}

bool _isPooling = false;

typedef ResultCall = void Function(String data);

class AdbUtil {
  static final List<ResultCall> _callback = [];
  static Isolate isolate;
  static Future<void> reconnectDevices(String ip, [String port]) async {
    await disconnectDevices(ip);
    connectDevices(ip);
  }

  static void addListener(ResultCall listener) {
    _callback.add(listener);
  }

  static void removeListener(ResultCall listener) {
    if (_callback.contains(listener)) {
      _callback.remove(listener);
    }
  }

  static void _notifiAll(String data) {
    for (ResultCall call in _callback) {
      call(data);
    }
  }

  static Future<void> startPoolingListDevices({
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (_isPooling) {
      return;
    }
    _isPooling = true;
    SendPort sendPort;
    final ReceivePort receivePort = ReceivePort();
    receivePort.listen((dynamic msg) {
      if (sendPort == null) {
        sendPort = msg as SendPort;
      } else {
        _notifiAll(msg);
        // Log.e('Isolate Message -> $msg');
      }
    });
    isolate = await Isolate.spawn(
      adbPollingIsolate,
      IsolateArgs(duration, receivePort.sendPort, RuntimeEnvir.packageName),
    );
  }

  static Future<void> stopPoolingListDevices() async {
    if (!_isPooling) {
      return;
    }
    _isPooling = false;
    isolate.kill(priority: Isolate.immediate);
  }

  static Future<AdbResult> connectDevices(String ipAndPort) async {
    String cmd = 'adb connect $ipAndPort';
    if (ipAndPort.contains(' ')) {
      cmd =
          'adb pair ${ipAndPort.split(' ').first} ${ipAndPort.split(' ').last}';
    }
    // ProcessResult resulta = await Process.run(
    //   'adb',
    //   ['pair', '192.168.237.156:40351', '723966'],
    //   environment: PlatformUtil.environment(),
    //   includeParentEnvironment: true,
    //   // runInShell: true,
    // );
    // Log.d(resulta.stdout);
    // Log.e(resulta.stderr);
    final String result = await execCmd(cmd);
    if (result.contains(RegExp('refused|failed'))) {
      throw ConnectFail('$ipAndPort ??????????????????????????????????????????ADB??????');
    } else if (result.contains('already connected')) {
      throw AlreadyConnect('??????????????????');
    } else if (result.contains('connect')) {
      return AdbResult('????????????');
    } else if (result.contains('Successfully paired')) {
      return AdbResult('????????????????????????????????????');
    }
    return AdbResult(result);
    //todo timed out
  }

  static Future<void> disconnectDevices(String ipAndPort) async {
    final String result = await execCmd('adb disconnect $ipAndPort');
  }

  static Future<int> getForwardPort(
    String serial, {
    int rangeStart = 27183,
    int rangeEnd = 27199,
    String targetArg = 'localabstract:scrcpy',
  }) async {
    while (rangeStart != rangeEnd) {
      try {
        await execCmd(
          'adb -s $serial forward tcp:$rangeStart $targetArg',
          throwException: false,
        );
        Log.d('??????$rangeStart????????????');
        return rangeStart;
      } catch (e) {
        Log.w('??????$rangeStart????????????');
        rangeStart++;
      }
    }
    return null;
  }

  static Future<bool> pushFile(
    String serial,
    String filePath,
    String pushPath,
  ) async {
    try {
      String data = await execCmd2([
        'adb',
        '-s',
        serial,
        'push',
        filePath,
        pushPath,
      ]);
      Log.d('PushFile log -> $data');
      return true;
    } catch (e) {
      Log.e('PushFile error -> $pushFile');
      return false;
    }
  }
}

class IsolateArgs {
  final Duration duration;
  final SendPort sendPort;
  final String package;

  IsolateArgs(this.duration, this.sendPort, this.package);
}

// ???isolate???????????????
Future<void> adbPollingIsolate(IsolateArgs args) async {
  // ???????????????ReceivePort ???????????????
  final ReceivePort receivePort = ReceivePort();
  RuntimeEnvir.initEnvirWithPackageName(args.package);
  // ?????????sendPort???????????????isolate???????????????????????????????????????
  args.sendPort.send(receivePort.sendPort);
  final Timer timer = Timer.periodic(args.duration, (timer) async {
    try {
      String result = await execCmd('adb devices');
      args.sendPort.send(result);
    } catch (e) {
      Log.i('e : ${e.toString()}');
    }
  });
}
