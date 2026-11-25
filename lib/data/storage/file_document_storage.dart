import 'dart:io';

import '../../domain/entities/document.dart';
import '../codec/document_codec.dart';

/// Reads and writes `.empucad` documents on disk. Writes go through a temp file and rename,
/// so a crash mid-save cannot leave a truncated design behind.
final class FileDocumentStorage {
  const FileDocumentStorage();

  Future<Document> load(String path) async => DocumentCodec.decode(await File(path).readAsString());

  Future<void> save(String path, Document d) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(DocumentCodec.encode(d), flush: true);
    await tmp.rename(path);
  }
}
