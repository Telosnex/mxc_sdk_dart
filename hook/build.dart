/// Bundles mxc_ffi.dll, the C library of Microsoft MXC, as a Dart code asset.
///
/// MXC is Windows-only here, so other targets get no library: the Dart API
/// reports that MXC is unavailable.
///
/// With package:kiln, the hook downloads the library from the GitHub release
/// in native_artifacts/prebuilt.json when the package sources match it.
/// Otherwise it builds the `mxc_ffi` crate of the pinned microsoft/mxc commit
/// (native_artifacts/sources.json) with cargo. That needs a Windows host,
/// rustup, and the Rust target of the build (`rustup target add
/// aarch64-pc-windows-msvc`, for example). The mxc checkout pins its Rust
/// version in src/rust-toolchain.toml; rustup installs it on first use. Set
/// RUSTUP_TOOLCHAIN to use another one.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:kiln/kiln.dart';

/// Must match `assetId` in lib/src/native/bindings.dart.
const _assetName = 'mxc_ffi';

const _rustTargets = {
  'windows-arm64': 'aarch64-pc-windows-msvc',
  'windows-x64': 'x86_64-pc-windows-msvc',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    final kiln = Kiln(input: input, output: output, log: _log);
    if (!input.config.buildCodeAssets) return kiln.installWeb();
    final target = TargetName.of(input.config.code);
    if (!_rustTargets.containsKey(target.name)) return;
    await kiln.run((source) => _buildFromSource(input, output, target, source));
  });
}

void _log(String message) => stderr.writeln('[mxc_sdk_dart] $message');

Future<void> _buildFromSource(
  BuildInput input,
  BuildOutputBuilder output,
  TargetName target,
  SourceBuild source,
) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'mxc_sdk_dart: a source build of $target runs only on Windows, and '
      'this host is ${Platform.operatingSystem}.',
    );
  }
  final rustTarget = _rustTargets[target.name]!;
  final mxc = await source.pinnedSource('mxc');
  final workspace = Directory('${mxc.path}${Platform.pathSeparator}src');
  // One cargo target directory per Rust target. Cargo locks it, so two
  // builds of the same target wait for each other.
  final targetDir = input.outputDirectoryShared.resolve('cargo/$rustTarget/');
  _log('Building mxc_ffi for $rustTarget');
  final stopwatch = Stopwatch()..start();
  final process = await Process.start(
    'cargo',
    [
      'build',
      '--locked',
      '--release',
      '-p',
      'mxc_ffi',
      '--target',
      rustTarget,
      '--target-dir',
      targetDir.toFilePath(),
    ],
    workingDirectory: workspace.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw StateError(
      'mxc_sdk_dart: cargo build of mxc_ffi for $rustTarget failed with exit '
      'code $exitCode. Check that rustup has the target: rustup target add '
      '$rustTarget',
    );
  }
  _log('cargo took ${stopwatch.elapsed.inSeconds}s');

  final built = File.fromUri(
    targetDir.resolve('$rustTarget/release/mxc_ffi.dll'),
  );
  await Directory.fromUri(input.outputDirectory).create(recursive: true);
  final library = await built.copy(
    File.fromUri(input.outputDirectory.resolve('mxc_ffi.dll')).path,
  );
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: _assetName,
      linkMode: DynamicLoadingBundled(),
      file: library.uri,
    ),
  );
}
