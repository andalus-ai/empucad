import 'dart:typed_data';

import 'package:empucad/application/document_ops.dart';
import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/data/codec/gray_codec.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/laser/laser_models.dart';
import 'package:test/test.dart';

RasterAsset asset({int w = 4, int h = 2, Uint8List? gray, RasterSettings settings = const RasterSettings(x: 5, y: 6, widthMm: 40)}) =>
    RasterAsset(name: 'logo.png', image: RasterImage(width: w, height: h, gray: gray ?? Uint8List.fromList(List.generate(w * h, (i) => i * 30 % 256))), settings: settings);

void main() {
  group('GrayCodec', () {
    test('roundtrips arbitrary data, including runs longer than 256 and noise', () {
      for (final data in [
        Uint8List(0),
        Uint8List.fromList([7]),
        Uint8List(1000), // one long run of zeros: needs 4 runs of <=256
        Uint8List.fromList(List.generate(999, (i) => (i * 37 + i ~/ 7) % 256)),
        Uint8List.fromList([...List.filled(300, 255), ...List.filled(5, 0), 255]),
      ]) {
        expect(GrayCodec.decode(GrayCodec.encode(data), data.length), data);
      }
    });

    test('flat artwork compresses to a small fraction of the raw size', () {
      final flat = Uint8List(1000000)..fillRange(0, 500000, 255);
      final text = GrayCodec.encode(flat);
      expect(text.length < 20000, isTrue, reason: '${text.length} chars for 1,000,000 pixels');
    });

    test('rejects truncated, oversize, wrong-length and non-base64 data', () {
      final good = GrayCodec.encode(Uint8List.fromList([1, 1, 2, 2, 2]));
      expect(() => GrayCodec.decode(good, 6), throwsA(isA<FormatException>()), reason: 'too short');
      expect(() => GrayCodec.decode(good, 4), throwsA(isA<FormatException>()), reason: 'too long');
      expect(() => GrayCodec.decode('not base64!!', 5), throwsA(isA<FormatException>()));
      expect(() => GrayCodec.decode('AA==', 1), throwsA(isA<FormatException>()), reason: 'odd byte count');
    });
  });

  group('document', () {
    test('the image and its settings survive save and open', () {
      var d = DocumentOps.setRaster(const Document(), asset());
      d = DocumentOps.updateRasterSettings(d, d.laser.raster!.settings.copyWith(powerMax: 70, invert: true, mode: RasterMode.dither, overscan: 1.5));
      final back = DocumentCodec.decode(DocumentCodec.encode(d)).laser.raster!;
      expect(back.name, 'logo.png');
      expect([back.image.width, back.image.height], [4, 2]);
      expect(back.image.gray, d.laser.raster!.image.gray);
      expect([back.settings.x, back.settings.y, back.settings.widthMm, back.settings.powerMax, back.settings.invert, back.settings.overscan], [5, 6, 40, 70, true, 1.5]);
      expect(back.settings.mode, RasterMode.dither);
    });

    test('a design with no image saves no raster key and reopens without one', () {
      final text = DocumentCodec.encode(const Document());
      expect(text.contains('"raster"'), isFalse);
      expect(DocumentCodec.decode(text).laser.raster, isNull);
    });

    test('updating settings with no image is a no-op; clearing removes it; other laser setup is kept', () {
      const empty = Document();
      expect(identical(DocumentOps.updateRasterSettings(empty, const RasterSettings()), empty), isTrue);
      var d = DocumentOps.setMachine(DocumentOps.setRaster(empty, asset()), const LaserMachine(bedWidth: 123));
      d = DocumentOps.clearRaster(d);
      expect(d.laser.raster, isNull);
      expect(d.laser.machine.bedWidth, 123);
      expect(identical(DocumentOps.clearRaster(d), d), isTrue);
    });

    test('machine and layer edits keep the loaded image', () {
      var d = DocumentOps.setRaster(const Document(), asset());
      d = DocumentOps.setMachine(d, const LaserMachine(bedWidth: 200));
      d = DocumentOps.updateLayer(d, d.laser.layer(0)!.copyWith(power: 10));
      expect(d.laser.raster, isNotNull);
    });

    String doc(String raster) => '{"app":"EmpuCAD","version":1,"nodes":[],"laser":{"machine":{"bedW":1,"bedH":1,"sMax":1,"rapid":1},'
        '"layers":[{"index":0,"speed":1,"power":1,"passes":1,"interval":1,"overscan":0}],"raster":$raster}}';
    const okSettings = '{"x":0,"y":0,"widthMm":10,"interval":0.1,"speed":100,"powerMin":0,"powerMax":50,"overscan":0}';

    for (final (label, raster) in [
      ('pixel count mismatch', '{"width":2,"height":2,"data":"AAA=","settings":$okSettings}'),
      ('absurd size', '{"width":100000,"height":100000,"data":"","settings":$okSettings}'),
      ('zero size', '{"width":0,"height":1,"data":"","settings":$okSettings}'),
      ('missing data', '{"width":1,"height":1,"settings":$okSettings}'),
      ('power order', '{"width":1,"height":1,"data":"AAA=","settings":{"x":0,"y":0,"widthMm":10,"interval":0.1,"speed":100,"powerMin":60,"powerMax":50,"overscan":0}}'),
      ('power over 100', '{"width":1,"height":1,"data":"AAA=","settings":{"x":0,"y":0,"widthMm":10,"interval":0.1,"speed":100,"powerMin":0,"powerMax":150,"overscan":0}}'),
      ('zero speed', '{"width":1,"height":1,"data":"AAA=","settings":{"x":0,"y":0,"widthMm":10,"interval":0.1,"speed":0,"powerMin":0,"powerMax":50,"overscan":0}}'),
    ]) {
      test('rejects: $label', () => expect(() => DocumentCodec.decode(doc(raster)), throwsA(isA<FormatException>())));
    }

    test('a valid minimal raster decodes', () {
      final r = DocumentCodec.decode(doc('{"width":1,"height":1,"data":"AAA=","settings":$okSettings}')).laser.raster!;
      expect(r.image.gray, [0]);
      expect(r.settings.widthMm, 10);
    });
  });
}
