library adbutil;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:global_repository/global_repository.dart';

class AdbResult {
  AdbResult(this.message);

  final String message;
}

class AdbException implements Exception {
  AdbException({this.message});

  final String message;

  @override
  String toString() {
    return 'adb exception : $message';
  }
}

class Arg {
  final String package;
  final String cmd;

  Arg(this.package, this.cmd);
}

Future<String> asyncExec(String cmd) async {
  return await compute(execCmdForIsolate, Arg(RuntimeEnvir.packageName, cmd));
}

Future<String> execCmdForIsolate(
  Arg arg, {
  bool throwException = true,
}) async {
  RuntimeEnvir.initEnvirWithPackageName(arg.package);
  final List<String> args = arg.cmd.split(' ');
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
      runInShell: true,
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
    if (throwException) {
      Log.w('adb stderr -> ${execResult.stderr}');
      throw Exception(execResult.stderr);
    }
  }
  // Log.e('adb stdout -> ${execResult.stdout}');
  return execResult.stdout.toString().trim();
}

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
      runInShell: true,
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
    while (true) {
      try {
        String result = await asyncExec('adb devices');
        _notifiAll(result);
      } catch (e) {
        Log.i('e : $e');
      }
      await Future.delayed(duration);
      if (!_isPooling) {
        break;
      }
    }
  }

  static Future<void> stopPoolingListDevices() async {
    _isPooling = false;
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
      throw AdbException(message: '$ipAndPort 无法连接，对方可能未打开网络ADB调试');
    } else if (result.contains('already connected')) {
      throw AdbException(message: '该设备已连接');
    } else if (result.contains('connect')) {
      return AdbResult('连接成功');
    } else if (result.contains('Successfully paired')) {
      return AdbResult('配对成功，还需要连接一次');
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
        );
        Log.d('端口$rangeStart绑定成功');
        return rangeStart;
      } catch (e) {
        Log.w('端口$rangeStart绑定失败');
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
      Log.d('pushFile log -> $data');
      return true;
    } catch (e) {
      Log.e('pushFile error -> $pushFile');
      return false;
    }
  }
}
