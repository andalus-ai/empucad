/// Flat x,y pairs in mm. Open outlines are for engraving; closed ones bound shapes.
final class Outline {
  const Outline(this.points, {this.closed = true});
  final List<double> points;
  final bool closed;
}

/// The outlines of ONE design shape (outer ring + holes, even-odd). Separate shapes are unioned.
final class ShapeOutlines {
  const ShapeOutlines(this.outlines);
  final List<Outline> outlines;
}
