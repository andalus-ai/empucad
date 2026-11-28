import 'dart:typed_data';

import 'package:empucad/application/document_ops.dart';
import 'package:empucad/application/generate_laser_job.dart';
import 'package:empucad/application/grayscale.dart';
import 'package:empucad/application/laser_job_builder.dart';
import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/laser/laser_models.dart';
import 'package:test/test.dart';

import 'support/fake_laser_engine.dart';

ShapeNode box(String id, {double x = 10, double y = 10}) =>
    ShapeNode(id: id, name: id, kind: ShapeKind.box, width: 20, depth: 20, height: 5, placement: Placement(x: x, y: y));

void main() {
  layerColourTests();
  group('layer resolution', () {
    test('a node burns on its own layer, else its group\'s, else layer 0', () {
      final g = GroupNode(id: 'g', name: 'g', children: [box('a'), box('b', x: 100)]);
      var d = Document(roots: [g, box('c', x: 200)]);
      d = DocumentOps.assignLayer(d, {'g'}, 2); // the group
      d = DocumentOps.assignLayer(d, {'b'}, 1); // overrides the group for b
      final plan = LaserJobBuilder.build(d);
      // order follows the design tree: a (group -> 2), b (own -> 1), c (default -> 0)
      expect(plan.shapes.map((s) => s.layer), [2, 1, 0]);
      expect(plan.layers.map((l) => l.index), [0, 1, 2]);
    });

    test('disabled layers are skipped and unused layers are not sent', () {
      var d = Document(roots: [box('a'), box('b', x: 100)]);
      d = DocumentOps.assignLayer(d, {'b'}, 1);
      d = DocumentOps.updateLayer(d, d.laser.layer(1)!.copyWith(enabled: false));
      final plan = LaserJobBuilder.build(d);
      expect(plan.shapes, hasLength(1));
      expect(plan.layers.map((l) => l.index), [0]);
    });

    test('hole nodes never burn; selection restricts what is planned', () {
      final hole = box('h').withHole(true);
      final d = Document(roots: [box('a'), hole, box('b', x: 100)]);
      expect(LaserJobBuilder.build(d).shapes, hasLength(2));
      expect(LaserJobBuilder.build(d, only: {'b'}).shapes, hasLength(1));
    });

    test('assigning to an unknown layer is ignored', () {
      final d = Document(roots: [box('a')]);
      expect(identical(DocumentOps.assignLayer(d, {'a'}, 99), d), isTrue);
    });
  });

  group('bed check', () {
    test('warns once with a count when shapes leave the bed, silent when they fit', () {
      final fits = Document(roots: [box('a', x: 100, y: 100)]);
      expect(LaserJobBuilder.build(fits).warnings, isEmpty);
      final d = Document(roots: [box('a', x: 100, y: 100), box('b', x: 395), box('c', x: 0, y: 0)]);
      final w = LaserJobBuilder.build(d).warnings;
      expect(w, hasLength(1));
      expect(w.single, contains('2 shapes'));
      expect(w.single, contains('400 x 400'));
    });

    test('a shape exactly touching the bed edge is fine', () {
      final d = Document(roots: [box('a', x: 10, y: 10)]); // 20 mm box centred at (10,10) spans 0..20
      expect(LaserJobBuilder.build(d).warnings, isEmpty);
    });
  });

  test('removing a node drops its layer assignment', () {
    var d = Document(roots: [box('a'), box('b', x: 100)]);
    d = DocumentOps.assignLayer(d, {'a', 'b'}, 1);
    d = DocumentOps.remove(d, {'a'});
    expect(d.laser.layerOf.keys, ['b']);
  });

  group('codec', () {
    test('roundtrips machine, layers and assignments', () {
      var d = Document(roots: [box('a')]);
      d = DocumentOps.assignLayer(d, {'a'}, 2);
      d = DocumentOps.updateLayer(d, d.laser.layer(2)!.copyWith(speed: 77, power: 33, passes: 2, interval: 0.2, angle: 45, mode: LaserLayerMode.fill, enabled: false));
      d = DocumentOps.setMachine(d, const LaserMachine(bedWidth: 300, bedHeight: 200, sMax: 255, rapid: 4000, dynamicPower: false));
      final back = DocumentCodec.decode(DocumentCodec.encode(d)).laser;
      expect(back.layerOf['a'], 2);
      final l = back.layer(2)!;
      expect([l.speed, l.power, l.passes, l.interval, l.angle, l.enabled], [77, 33, 2, 0.2, 45, false]);
      expect(l.mode, LaserLayerMode.fill);
      expect([back.machine.bedWidth, back.machine.bedHeight, back.machine.sMax, back.machine.dynamicPower], [300, 200, 255, false]);
    });

    test('a file written before laser support opens with defaults', () {
      final d = DocumentCodec.decode('{"app":"EmpuCAD","version":1,"nodes":[]}');
      expect(d.laser.layers, hasLength(5));
      expect(d.laser.machine.bedWidth, 400);
    });

    for (final (label, laser) in [
      ('power over 100', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[{"index":0,"speed":1,"power":150,"passes":1,"interval":1,"overscan":0}]}'),
      ('duplicate layer index', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[{"index":0,"speed":1,"power":1,"passes":1,"interval":1,"overscan":0},{"index":0,"speed":1,"power":1,"passes":1,"interval":1,"overscan":0}]}'),
      ('zero speed', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[{"index":0,"speed":0,"power":1,"passes":1,"interval":1,"overscan":0}]}'),
      ('zero passes', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[{"index":0,"speed":1,"power":1,"passes":0,"interval":1,"overscan":0}]}'),
      ('assignment to unknown layer', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[{"index":0,"speed":1,"power":1,"passes":1,"interval":1,"overscan":0}],"assign":{"a":7}}'),
      ('no layers', '{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},"layers":[]}'),
    ]) {
      test('rejects: $label', () {
        expect(() => DocumentCodec.decode('{"app":"EmpuCAD","version":1,"nodes":[],"laser":$laser}'), throwsA(isA<FormatException>()));
      });
    }
  });

  group('use cases', () {
    test('GenerateLaserJob sends shapes, only the used layers and the machine to the engine, merging warnings', () async {
      final engine = FakeLaserEngine()..warnings = ['engine says hi'];
      final d = Document(roots: [box('a', x: 395)]);
      final r = await GenerateLaserJob(engine)(d);
      expect(engine.lastShapes, hasLength(1));
      expect(engine.lastLayers!.map((l) => l.index), [0]);
      expect(engine.lastMachine!.bedWidth, 400);
      expect(r.warnings, hasLength(2));
      expect(r.warnings.last, 'engine says hi');
    });

    test('GenerateLaserJob refuses an empty design instead of producing a blank job', () async {
      Object? err;
      try {
        await GenerateLaserJob(FakeLaserEngine())(const Document());
      } on LaserFailure catch (e) {
        err = e;
      }
      expect(err, isNotNull);
    });

    test('raster: height follows the aspect ratio; off-bed placement warns; bad settings are refused', () async {
      final engine = FakeLaserEngine();
      final img = RasterImage(width: 200, height: 100, gray: Uint8List(200 * 100));
      expect(GenerateRasterJob.heightFor(img, 80), 40);
      final job = GenerateRasterJob(engine);
      final ok = await job(img, const RasterSettings(x: 10, y: 10, widthMm: 80), const LaserMachine());
      expect(ok.warnings, isEmpty);
      expect(engine.lastRaster!.widthMm, 80);
      final off = await job(img, const RasterSettings(x: 350, y: 10, widthMm: 80), const LaserMachine());
      expect(off.warnings.single, contains('outside'));
      for (final bad in [const RasterSettings(widthMm: 0), const RasterSettings(powerMin: 80, powerMax: 20), const RasterSettings(powerMax: 120)]) {
        Object? err;
        try {
          await job(img, bad, const LaserMachine());
        } on LaserFailure catch (e) {
          err = e;
        }
        expect(err, isNotNull);
      }
    });
  });

  group('grayscale', () {
    test('black, white, luma weights and transparency', () {
      final rgba = Uint8List.fromList([
        0, 0, 0, 255, // black
        255, 255, 255, 255, // white
        255, 0, 0, 255, // red -> 0.2126*255 = 54
        0, 0, 0, 0, // fully transparent black -> white
        0, 0, 0, 128, // half transparent black -> ~127
      ]);
      final g = Grayscale.fromRgba(rgba, 5, 1).gray;
      expect(g[0], 0);
      expect(g[1], 255);
      expect(g[2], closeTo(54, 1));
      expect(g[3], 255);
      expect(g[4], closeTo(127, 1));
    });

    test('rejects a buffer of the wrong size; RasterImage validates its pixel count', () {
      expect(() => Grayscale.fromRgba(Uint8List(7), 2, 1), throwsA(isA<ArgumentError>()));
      expect(() => RasterImage(width: 2, height: 2, gray: Uint8List(3)), throwsA(isA<ArgumentError>()));
    });
  });
}

void layerColourTests() {
  group('laser layer colours', () {
    final cut = LaserSetup.defaultLayers[0].color, score = LaserSetup.defaultLayers[1].color, engrave = LaserSetup.defaultLayers[2].color;

    test('a node takes its own layer, else its group\'s, else layer 1', () {
      final g = GroupNode(id: 'g', name: 'g', children: [box('a'), box('b', x: 100)]);
      var d = Document(roots: [g, box('c', x: 200)]);
      d = DocumentOps.assignLayer(d, {'g'}, 2);
      d = DocumentOps.assignLayer(d, {'b'}, 1);
      expect(LaserJobBuilder.viewColor(d, 'a'), engrave, reason: 'inherits the group');
      expect(LaserJobBuilder.viewColor(d, 'b'), score, reason: 'own assignment wins');
      expect(LaserJobBuilder.viewColor(d, 'g'), engrave, reason: 'a boolean result is drawn under the group id');
      expect(LaserJobBuilder.viewColor(d, 'c'), cut, reason: 'default layer');
      expect([for (final id in ['a', 'b', 'g', 'c']) LaserJobBuilder.layerOfNode(d, id)], [2, 1, 2, 0]);
    });

    test('a switched-off layer is faded but keeps its hue; unknown nodes have no colour', () {
      var d = Document(roots: [box('a')]);
      d = DocumentOps.updateLayer(d, d.laser.layer(0)!.copyWith(enabled: false));
      final c = LaserJobBuilder.viewColor(d, 'a')!;
      expect(c & 0x00FFFFFF, cut & 0x00FFFFFF);
      expect(c >> 24, lessThan(0xFF));
      expect(LaserJobBuilder.viewColor(d, 'nope'), isNull);
      expect(LaserJobBuilder.layerOfNode(d, 'nope'), isNull);
    });

    test('the view and the job agree: whatever colour a shape shows is the layer it is planned on', () {
      var d = Document(roots: [box('a'), GroupNode(id: 'g', name: 'g', children: [box('b', x: 100), box('c', x: 200)])]);
      d = DocumentOps.assignLayer(d, {'a'}, 3);
      d = DocumentOps.assignLayer(d, {'g'}, 4);
      final plan = LaserJobBuilder.build(d);
      expect(plan.shapes.map((s) => s.layer), [3, 4, 4]);
      expect([LaserJobBuilder.layerOfNode(d, 'a'), LaserJobBuilder.layerOfNode(d, 'b'), LaserJobBuilder.layerOfNode(d, 'c')], [3, 4, 4]);
    });
  });

  test('idPathTo lists the node then its ancestors, and is empty for a missing id', () {
    final inner = GroupNode(id: 'in', name: 'in', children: [box('leaf')]);
    final d = Document(roots: [GroupNode(id: 'out', name: 'out', children: [inner]), box('x')]);
    expect(d.idPathTo('leaf'), ['leaf', 'in', 'out']);
    expect(d.idPathTo('out'), ['out']);
    expect(d.idPathTo('x'), ['x']);
    expect(d.idPathTo('missing'), isEmpty);
  });
}
