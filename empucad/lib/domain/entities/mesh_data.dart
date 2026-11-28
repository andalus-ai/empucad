import 'dart:typed_data';

/// Indexed triangle mesh in millimetres, Z-up. Same layout the Rust engine uses.
final class MeshData {
  const MeshData(this.positions, this.indices);
  final Float32List positions;
  final Uint32List indices;
  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  bool get isEmpty => indices.isEmpty;
}
