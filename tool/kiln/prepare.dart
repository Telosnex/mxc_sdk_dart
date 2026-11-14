// Run directly with `dart tool/kiln/prepare.dart`, before native hooks.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

Future<void> main() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('MXC native builds require Windows.');
  }
  final target =
      Platform.environment['TARGET'] ??
      (Abi.current() == Abi.windowsArm64 ? 'windows-arm64' : 'windows-x64');
  final rustTarget = switch (target) {
    'windows-arm64' => 'aarch64-pc-windows-msvc',
    'windows-x64' => 'x86_64-pc-windows-msvc',
    _ => throw UnsupportedError('Unsupported MXC target: $target'),
  };
  final sources =
      jsonDecode(File('native_artifacts/sources.json').readAsStringSync())
          as Map<String, dynamic>;
  final source = (sources['sources'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['name'] == 'mxc');
  final client = HttpClient();
  try {
    // Read the toolchain at the same immutable commit used by the hook.
    final request = await client.getUrl(
      Uri.parse(
        'https://raw.githubusercontent.com/microsoft/mxc/'
        '${source['commit']}/src/rust-toolchain.toml',
      ),
    );
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'Cannot read pinned MXC Rust toolchain: '
        '${response.statusCode}',
      );
    }
    final toml = await utf8.decoder.bind(response).join();
    final channel = RegExp(
      r'^channel\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(toml)?.group(1);
    if (channel == null) throw StateError('No pinned MXC Rust channel.');
    final cargoHome =
        Platform.environment['CARGO_HOME'] ??
        '${Platform.environment['USERPROFILE']}\\.cargo';
    final bin = '$cargoHome\\bin';
    final rustup = File('$bin\\rustup.exe');
    final environment = {'PATH': '$bin;${Platform.environment['PATH']}'};
    if (!rustup.existsSync()) {
      final temp = await Directory.systemTemp.createTemp('mxc-rustup-');
      try {
        final download = await client.getUrl(
          Uri.parse(
            'https://static.rust-lang.org/rustup/dist/'
            '$rustTarget/rustup-init.exe',
          ),
        );
        final installer = await download.close();
        if (installer.statusCode != 200) {
          throw HttpException(
            'Cannot download rustup: ${installer.statusCode}',
          );
        }
        final executable = File('${temp.path}\\rustup-init.exe');
        await installer.pipe(executable.openWrite());
        await run(executable.path, [
          '-y',
          '--no-modify-path',
          '--default-toolchain',
          'none',
        ], environment);
      } finally {
        await temp.delete(recursive: true);
      }
    }
    await run(rustup.path, [
      'toolchain',
      'install',
      channel,
      '--profile',
      'minimal',
      '--target',
      rustTarget,
    ], environment);
    for (final entry in {
      'GITHUB_PATH': bin,
      'GITHUB_ENV': 'KILN_TOOLCHAIN_EXTRA=Rust $channel ($rustTarget)',
    }.entries) {
      final path = Platform.environment[entry.key];
      if (path != null) {
        File(path).writeAsStringSync('${entry.value}\n', mode: FileMode.append);
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> run(
  String executable,
  List<String> args,
  Map<String, String> environment,
) async {
  final process = await Process.start(
    executable,
    args,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) throw StateError('$executable failed with exit code $code');
}
