import 'dart:convert';

import '../data/codec/document_codec.dart';
import '../data/import/dabble_importer.dart';
import '../domain/entities/document.dart';

enum DocumentSource { empucad, dabbleCad }

final class OpenedDocument {
  const OpenedDocument(this.document, this.source, this.warnings);
  final Document document;
  final DocumentSource source;
  final List<String> warnings;
}

/// Opens a design file of either format, recognised by its content, not its extension.
/// Throws [FormatException] with a readable message when the file is neither.
abstract final class DocumentOpener {
  static OpenedDocument open(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (DabbleImporter.looksLike(json)) {
      final r = DabbleImporter.fromJson(json as Map<String, dynamic>);
      return OpenedDocument(r.document, DocumentSource.dabbleCad, r.warnings);
    }
    return OpenedDocument(DocumentCodec.decode(text), DocumentSource.empucad, const []);
  }
}
