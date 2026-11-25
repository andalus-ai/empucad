import 'package:flutter_test/flutter_test.dart';
import 'package:empucad_engine/empucad_engine.dart';
import 'package:empucad_engine/empucad_engine_pigeon.dart';
import 'package:empucad_engine/empucad_engine_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockEmpucadEnginePlatform
    with MockPlatformInterfaceMixin
    implements EmpucadEnginePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final initialPlatform = EmpucadEnginePlatform.instance;

  test('PigeonEmpucadEngine is the default instance', () {
    expect(initialPlatform, isInstanceOf<PigeonEmpucadEngine>());
  });

  test('getPlatformVersion', () async {
    EmpucadEngine empucadEnginePlugin = EmpucadEngine();
    MockEmpucadEnginePlatform fakePlatform = MockEmpucadEnginePlatform();
    EmpucadEnginePlatform.instance = fakePlatform;

    expect(await empucadEnginePlugin.getPlatformVersion(), '42');
  });
}
