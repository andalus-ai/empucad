import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:empucad_engine/empucad_engine_pigeon.dart';
import 'package:empucad_engine/src/messages.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getPlatformVersion', () async {
    final api = FakeEmpucadEnginePluginApi(platformVersion: '42');
    final plugin = PigeonEmpucadEngine(api: api);

    expect(await plugin.getPlatformVersion(), '42');
  });
}

/// Fake implementation of the Pigeon API that provides a pre-set response.
class FakeEmpucadEnginePluginApi implements EmpucadEnginePluginApi {
  FakeEmpucadEnginePluginApi({required this.platformVersion});

  final String platformVersion;

  @override
  Future<String> getPlatformVersion() async {
    return platformVersion;
  }

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
