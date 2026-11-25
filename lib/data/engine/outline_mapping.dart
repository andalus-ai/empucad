import 'dart:typed_data';

import 'package:empucad_engine/empucad_engine.dart' as rust;

import '../../domain/entities/outline.dart';

/// Domain <-> bridge conversions for outlines, shared by the Rust adapters.
abstract final class OutlineMapping {
  static rust.Outline toRust(Outline o) => rust.Outline(points: Float64List.fromList(o.points), closed: o.closed);
  static Outline fromRust(rust.Outline o) => Outline(o.points.toList(), closed: o.closed);
  static rust.ShapeOutlines shapeToRust(ShapeOutlines s) => rust.ShapeOutlines(outlines: [for (final o in s.outlines) toRust(o)]);
  static ShapeOutlines shapeFromRust(rust.ShapeOutlines s) => ShapeOutlines([for (final o in s.outlines) fromRust(o)]);
}
