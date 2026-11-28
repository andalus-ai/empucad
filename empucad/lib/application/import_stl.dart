import 'dart:typed_data';

import '../domain/entities/scene_node.dart';
import '../domain/ports/geometry_engine.dart';
import 'mesh_tools.dart';

final class StlImport {
  const StlImport(this.node, this.warnings);
  final MeshNode node;
  final List<String> warnings;
}

/// STL bytes -> a [MeshNode] resting on the workplane. Throws [InvalidInputFailure] for an unreadable or
/// empty file. A mesh that is not a closed solid still imports (it can be viewed, moved and exported),
/// with a warning, because boolean operations need a closed solid.
final class ImportStl {
  const ImportStl(this._engine);
  final GeometryEngine _engine;

  /// Bigger meshes make slow, huge design files; refuse rather than hang the app.
  static const maxTriangles = 500000;

  Future<StlImport> call(Uint8List bytes, {required String id, String name = 'Imported mesh'}) async {
    final raw = await _engine.decodeStl(bytes);
    if (raw.isEmpty) throw const InvalidInputFailure('The STL file contains no triangles.');
    if (raw.triangleCount > maxTriangles) {
      throw InvalidInputFailure('The STL has ${raw.triangleCount} triangles; the limit is $maxTriangles. Simplify it in a mesh tool first.');
    }
    final mesh = MeshTools.restOnWorkplane(raw);
    final report = await _engine.inspect(mesh);
    return StlImport(
      MeshNode.fromMesh(id: id, name: name, mesh: mesh),
      [
        if (!report.closed) 'The mesh is not a closed solid (it has holes or loose faces). It can be placed and exported, but combining it with other shapes will not work.',
        if (report.closed && report.volume <= 0) 'The mesh has no volume; its triangles may be wound inside out.',
      ],
    );
  }
}
