import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/mesh_data.dart';

/// Text form of a mesh for `.empucad` files: positions as little-endian float32 and indices as
/// little-endian uint32, each base64. Endianness is explicit so a file reads the same everywhere.
/// Decoding is strict: a corrupt or hostile file must never yield a mesh the renderer or the engine
/// could index out of range.
abstract final class MeshCodec {
  static const _maxTriangles = 2000000;

  static Map<String, Object?> encode(MeshData m) {
    final pos = ByteData(m.positions.length * 4);
    for (var i = 0; i < m.positions.length; i++) {
      pos.setFloat32(i * 4, m.positions[i], Endian.little);
    }
    final idx = ByteData(m.indices.length * 4);
    for (var i = 0; i < m.indices.length; i++) {
      idx.setUint32(i * 4, m.indices[i], Endian.little);
    }
    return {
      'vertices': m.vertexCount,
      'triangles': m.triangleCount,
      'positions': base64Encode(pos.buffer.asUint8List()),
      'indices': base64Encode(idx.buffer.asUint8List()),
    };
  }

  static MeshData decode(Map<String, dynamic> j) {
    final nv = j['vertices'], nt = j['triangles'];
    if (nv is! int || nt is! int || nv < 3 || nt < 1 || nt > _maxTriangles || nv > nt * 3) {
      throw const FormatException('Mesh has an invalid size');
    }
    final Uint8List posBytes, idxBytes;
    try {
      posBytes = base64Decode(j['positions'] as String);
      idxBytes = base64Decode(j['indices'] as String);
    } on Object {
      throw const FormatException('Mesh data is not valid base64');
    }
    if (posBytes.length != nv * 12) throw const FormatException('Mesh positions do not match the declared vertex count');
    if (idxBytes.length != nt * 12) throw const FormatException('Mesh indices do not match the declared triangle count');
    final pb = ByteData.sublistView(posBytes), ib = ByteData.sublistView(idxBytes);
    final positions = Float32List(nv * 3);
    for (var i = 0; i < positions.length; i++) {
      final v = pb.getFloat32(i * 4, Endian.little);
      if (!v.isFinite) throw const FormatException('Mesh contains a non-finite coordinate');
      positions[i] = v;
    }
    final indices = Uint32List(nt * 3);
    for (var i = 0; i < indices.length; i++) {
      final v = ib.getUint32(i * 4, Endian.little);
      if (v >= nv) throw const FormatException('Mesh refers to a vertex that does not exist');
      indices[i] = v;
    }
    return MeshData(positions, indices);
  }
}
