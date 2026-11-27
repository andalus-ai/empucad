import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../presentation/state/export_service.dart';

/// Desktop and web save dialog via `file_selector`.
/// (Mobile platforms have no save dialog in this package; add a share-sheet implementation there.)
final class FileSelectorExportService implements ExportService, ImportService {
  const FileSelectorExportService();

  @override
  Future<bool> save({required String suggestedName, required String extension, required Uint8List bytes}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [XTypeGroup(label: extension.toUpperCase(), extensions: [extension])],
    );
    if (location == null) return false;
    await XFile.fromData(bytes, name: suggestedName).saveTo(location.path);
    return true;
  }

  @override
  Future<String?> pickText({required List<String> extensions}) async {
    final file = await openFile(acceptedTypeGroups: [XTypeGroup(label: 'EmpuCAD', extensions: extensions)]);
    return file?.readAsString();
  }

  @override
  Future<Uint8List?> pickBytes({required List<String> extensions}) async {
    final file = await openFile(acceptedTypeGroups: [XTypeGroup(label: 'Image', extensions: extensions)]);
    return file?.readAsBytes();
  }
}
