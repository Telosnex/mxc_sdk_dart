@TestOn('windows')
@Tags(['windows'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:mxc_sdk_dart/mxc_sdk_dart.dart';
import 'package:test/test.dart';

const _cmd = r'C:\Windows\System32\cmd.exe';

/// A sleep. ping fails at once in a container without network.
String _sleep(int seconds) =>
    'powershell -NoProfile -Command Start-Sleep $seconds';

void main() {
  late Directory work;
  late Directory outside;

  setUp(() async {
    // Under the profile: MXC refuses some system folders as write grants.
    final home = Platform.environment['USERPROFILE']!;
    work = await Directory(home).createTemp('mxc_sdk_dart_');
    outside = await Directory(home).createTemp('mxc_sdk_dart_outside_');
  });

  tearDown(() async {
    await work.delete(recursive: true);
    await outside.delete(recursive: true);
  });

  ContainerRequest request(
    String script, {
    int? timeoutMs,
    List<String> denied = const [],
  }) => ContainerRequest(
    command: '$_cmd /d /s /c "$script"',
    filesystem: FilesystemPolicy(
      readwritePaths: [work.path],
      readonlyPaths: [r'C:\'],
      deniedPaths: denied,
    ),
    network: const NetworkPolicy(
      egress: NetworkEgressConfig(defaultAction: NetworkAction.deny),
      ingress: NetworkIngressConfig(
        defaultAction: NetworkAction.deny,
        hostLoopback: NetworkAction.deny,
      ),
    ),
    ui: const UiPolicy(disable: false),
    timeoutMs: timeoutMs,
    workingDirectory: work.path,
    inheritDefaultEnvironment: true,
  );

  Future<({WaitResult result, String out, String err})> run(
    ContainerRequest request,
  ) async {
    final process = await spawn(request);
    final out = process.standardOutput!
        .transform(systemEncoding.decoder)
        .join();
    final err = process.standardError!.transform(systemEncoding.decoder).join();
    final result = await process.wait();
    return (result: result, out: await out, err: await err);
  }

  test('the probe finds BaseContainer for the request', () {
    final output = probe(request('echo x', denied: [r'C:\nothing\here']));
    expect(output.error, isNull);
    expect(output.tier, IsolationTier.baseContainer);
    expect(output.needsDaclAugmentation, isFalse);
    expect(output.probes.baseContainerSupportsDenyPaths, isTrue);
  });

  test('output and the exit code come back', () async {
    final run1 = await run(request('echo hello& echo oops 1>&2& exit /b 7'));
    expect(run1.out.trim(), 'hello');
    expect(run1.err.trim(), 'oops');
    expect(run1.result.exitCode, 7);
    expect(run1.result.timedOut, isFalse);
  });

  test('the file policy holds', () async {
    final secret = File('${work.path}\\secret.txt')..writeAsStringSync('s');
    final blocked = '${outside.path}\\blocked.txt';
    final result = await run(
      request(
        'echo in> inside.txt& echo out> $blocked& type secret.txt',
        denied: [secret.path],
      ),
    );
    expect(File('${work.path}\\inside.txt').existsSync(), isTrue);
    expect(File(blocked).existsSync(), isFalse);
    expect(result.out, isNot(contains('s')));
  });

  test('kill ends the whole tree', () async {
    final beat = File('${work.path}\\beat.txt');
    File('${work.path}\\child.bat').writeAsStringSync(
      '@echo off\r\n:loop\r\necho x>> "${beat.path}"\r\n'
      '${_sleep(1)}\r\ngoto loop\r\n',
    );
    final process = await spawn(
      request('start "" /b child.bat& ${_sleep(120)}'),
    );
    final waited = process.wait();
    while (!beat.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    process.kill();
    final result = await waited.timeout(const Duration(seconds: 10));
    expect(result.timedOut, isFalse);
    final length = beat.lengthSync();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(beat.lengthSync(), length);
  });

  test('a timeout ends the process', () async {
    final watch = Stopwatch()..start();
    final result = await run(request(_sleep(60), timeoutMs: 3000));
    expect(result.result.timedOut, isTrue);
    expect(result.result.exitCode, -1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('stdin reaches the process', () async {
    final process = await spawn(request('findstr .'));
    final out = process.standardOutput!
        .transform(systemEncoding.decoder)
        .join();
    final stdin = process.standardInput!;
    stdin.add(utf8.encode('one\r\ntwo\r\n'));
    await stdin.close();
    final result = await process.wait();
    expect(result.exitCode, 0);
    expect(LineSplitter.split(await out).toList(), ['one', 'two']);
  });

  test('dispose ends a running process and fails wait', () async {
    final marker = File('${work.path}\\late.txt');
    final process = await spawn(request('${_sleep(4)}& echo late> late.txt'));
    final waited = process.wait();
    process.dispose();
    await expectLater(waited, throwsStateError);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(marker.existsSync(), isFalse);
  });

  test('a program that does not exist fails the spawn', () async {
    await expectLater(
      spawn(request('x').copyWithCommand(r'C:\missing\program.exe')),
      throwsA(
        isA<MxcError>().having(
          (e) => e.code,
          'code',
          MxcErrorCode.backendError,
        ),
      ),
    );
  });
}

extension on ContainerRequest {
  ContainerRequest copyWithCommand(String command) => ContainerRequest(
    command: command,
    filesystem: filesystem,
    network: network,
    ui: ui,
    workingDirectory: workingDirectory,
    inheritDefaultEnvironment: inheritDefaultEnvironment,
  );
}
