import 'dart:io';

import 'package:mxc_sdk_dart/mxc_sdk_dart.dart';

// Run with `dart run example/main.dart` on Windows. This only probes the
// requested policy; it does not start a container or run the command.
void main() {
  if (!Platform.isWindows) {
    print('MXC ProcessContainer probing is only available on Windows.');
    return;
  }

  final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final work = Platform.environment['USERPROFILE'] ?? Directory.current.path;
  final request = ContainerRequest(
    command: '"$windows\\System32\\cmd.exe" /d /s /c "echo Hello from MXC"',
    workingDirectory: work,
    filesystem: FilesystemPolicy(readonlyPaths: [windows, work]),
    network: const NetworkPolicy(
      egress: NetworkEgressConfig(defaultAction: NetworkAction.deny),
    ),
  );

  try {
    final result = probe(request);
    if (result.tier == IsolationTier.baseContainer) {
      print('BaseContainer can serve the request.');
    } else {
      print(result.error ?? 'BaseContainer is not available for this request.');
    }
    for (final warning in result.warnings) {
      print('Warning: $warning');
    }
  } on MxcError catch (error) {
    stderr.writeln('Could not probe MXC: $error');
    exitCode = 1;
  }
}
