import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'empucad_engine_pigeon.dart';

abstract class EmpucadEnginePlatform extends PlatformInterface {
  /// Constructs a EmpucadEnginePlatform.
  EmpucadEnginePlatform() : super(token: _token);

  static final Object _token = Object();

  static EmpucadEnginePlatform _instance = PigeonEmpucadEngine();

  /// The instance of [EmpucadEnginePlatform] to use.
  ///
  /// Defaults to [PigeonEmpucadEngine].
  static EmpucadEnginePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EmpucadEnginePlatform] when
  /// they register themselves.
  static set instance(EmpucadEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
