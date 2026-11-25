import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saves bytes somewhere the user chooses. A port, so the UI never imports a file-picker package
/// and tests can substitute an in-memory implementation.
abstract interface class ExportService {
  /// Returns false when the user cancelled.
  Future<bool> save({required String suggestedName, required String extension, required Uint8List bytes});
}

/// Must be overridden at the composition root (`main.dart`).
final exportServiceProvider = Provider<ExportService>((ref) => throw UnimplementedError('exportServiceProvider must be overridden'));

/// Lets the user pick a text file to open. Same idea as [ExportService]: a port for the UI.
abstract interface class ImportService {
  /// Returns null when the user cancelled.
  Future<String?> pickText({required List<String> extensions});

  /// Returns null when the user cancelled.
  Future<Uint8List?> pickBytes({required List<String> extensions});
}

final importServiceProvider = Provider<ImportService>((ref) => throw UnimplementedError('importServiceProvider must be overridden'));
