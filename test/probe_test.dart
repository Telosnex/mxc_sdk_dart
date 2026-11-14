import 'dart:io';

import 'package:mxc_sdk_dart/mxc_sdk_dart.dart';
import 'package:mxc_sdk_dart/src/probe.dart' show parseProbeOutput;
import 'package:test/test.dart';

Map<String, Object?> _facts() => {
  for (final field in ProbeFacts.booleanFields) field: true,
  'uiCapabilities': {
    for (final field in UiCapabilitySupport.fields) field: true,
  },
};

void main() {
  test('a tier answer parses', () {
    final output = parseProbeOutput({
      'tier': 'base-container',
      'needsDaclAugmentation': false,
      'warnings': ['w'],
      'probes': _facts(),
    });
    expect(output!.tier, IsolationTier.baseContainer);
    expect(output.needsDaclAugmentation, isFalse);
    expect(output.warnings, ['w']);
    expect(output.probes.baseContainerSupportsDenyPaths, isTrue);
    expect(output.probes.uiCapabilities.canBlockInputInjection, isTrue);
  });

  test('an error answer parses', () {
    final output = parseProbeOutput({
      'warnings': <String>[],
      'probes': _facts(),
      'error': 'no tier',
    });
    expect(output!.tier, isNull);
    expect(output.error, 'no tier');
  });

  test('answers outside the contract are refused', () {
    expect(
      parseProbeOutput({'warnings': <String>[], 'probes': _facts()}),
      isNull,
    );
    expect(
      parseProbeOutput({
        'tier': 'base-container',
        'needsDaclAugmentation': false,
        'warnings': <String>[],
        'probes': _facts(),
        'error': 'both',
      }),
      isNull,
    );
    expect(
      parseProbeOutput({
        'tier': 'base-container',
        'needsDaclAugmentation': false,
        'warnings': <String>[],
        'probes': _facts(),
        'extra': 1,
      }),
      isNull,
    );
    expect(
      parseProbeOutput({
        'tier': 'unknown-tier',
        'needsDaclAugmentation': false,
        'warnings': <String>[],
        'probes': _facts(),
      }),
      isNull,
    );
    expect(
      parseProbeOutput({
        'tier': 'base-container',
        'needsDaclAugmentation': false,
        'warnings': <String>[],
        'probes': {..._facts(), 'baseContainerApiPresent': 'yes'},
      }),
      isNull,
    );
  });

  test('off Windows, probe and spawn report that MXC is unavailable', () async {
    const request = ContainerRequest(command: 'x');
    final unavailable = throwsA(
      isA<MxcError>().having(
        (e) => e.code,
        'code',
        MxcErrorCode.backendUnavailable,
      ),
    );
    expect(() => probe(request), unavailable);
    await expectLater(spawn(request), unavailable);
  }, skip: Platform.isWindows ? 'Windows has MXC' : null);
}
