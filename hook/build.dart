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
///
/// The library is built without Microsoft telemetry routing. A release build
/// of MXC 1.1.0 and later reads a routing group from a signed DLL in the mxc
/// checkout, and then sends Required diagnostic events to Microsoft (see
/// docs/telemetry.md there). The hook sets MXC_TELEMETRY_COMPONENT_PATH to an
/// empty value, which mxc documents as the build without routing, and fails
/// if the built library still contains that group.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    // Empty, not absent: mxc's build script then selects no telemetry
    // component, so the provider is registered without a routing group.
    environment: {'MXC_TELEMETRY_COMPONENT_PATH': ''},
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
  await _checkNotRouted(mxc, built);
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

/// Fails if [library] contains a telemetry routing group of the mxc checkout.
///
/// Each signed component DLL under src/mxc-sdk/resources/telemetry-component
/// carries its metadata as the text `1;<group GUID>;...`. A routed build
/// stores that GUID in the ETW provider traits, in the Windows GUID layout.
Future<void> _checkNotRouted(Directory mxc, File library) async {
  final components = Directory(
    '${mxc.path}/src/mxc-sdk/resources/telemetry-component',
  );
  final groups = <String>{};
  if (components.existsSync()) {
    await for (final entity in components.list(recursive: true)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.dll')) {
        continue;
      }
      final text = latin1.decode(await entity.readAsBytes());
      for (final match in _componentGroup.allMatches(text)) {
        groups.add(match.group(1)!.toLowerCase());
      }
    }
  }
  if (groups.isEmpty) {
    throw StateError(
      'mxc_sdk_dart: no telemetry routing group found under '
      '${components.path}. MXC has changed how it routes telemetry: review '
      'docs/telemetry.md in the mxc checkout and update hook/build.dart.',
    );
  }
  final bytes = await library.readAsBytes();
  for (final group in groups) {
    if (_contains(bytes, _guidBytes(group)) ||
        _contains(bytes, ascii.encode(group))) {
      throw StateError(
        'mxc_sdk_dart: ${library.path} contains the telemetry routing group '
        '$group, so it would send diagnostic data to Microsoft. '
        'MXC_TELEMETRY_COMPONENT_PATH did not reach the mxc build script as '
        'an empty value.',
      );
    }
  }
  _log('No telemetry routing group in mxc_ffi.dll (${groups.join(', ')})');
}

final _componentGroup = RegExp(
  '1;([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12});0x',
);

/// The 16 bytes of a GUID struct: the first three fields are little-endian.
Uint8List _guidBytes(String guid) {
  final hex = guid.replaceAll('-', '');
  final raw = [
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return Uint8List.fromList([
    ...raw.sublist(0, 4).reversed,
    ...raw.sublist(4, 6).reversed,
    ...raw.sublist(6, 8).reversed,
    ...raw.sublist(8),
  ]);
}

bool _contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
