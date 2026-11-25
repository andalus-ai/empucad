import 'package:flutter/foundation.dart';

import 'empucad_engine_platform_interface.dart';
import 'src/messages.g.dart';

/// An implementation of [EmpucadEnginePlatform] that uses Pigeon, for
/// non-web platforms.
class PigeonEmpucadEngine extends EmpucadEnginePlatform {
  /// Creates a new plugin implementation instance.
  PigeonEmpucadEngine({@visibleForTesting EmpucadEnginePluginApi? api})
    : _hostApi = api ?? EmpucadEnginePluginApi();

  final EmpucadEnginePluginApi _hostApi;

  @override
  Future<String?> getPlatformVersion() async {
    return _hostApi.getPlatformVersion();
  }
}
