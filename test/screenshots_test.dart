import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/ui/app.dart';
import 'support.dart';

Future<void> loadCaptureFonts() async {
  for (final entry in {
    'Roboto': [
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/Roboto-Bold.ttf',
    ],
    'Tile': ['assets/fonts/RobotoCondensed-Bold.ttf'],
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

void main() {
  testWidgets(
    'longest production tile labels stay at least eleven pixels on a small phone',
    (tester) async {
      await loadCaptureFonts();
      const textWidth = (360 - 40 - 21) / 4 - 8;
      for (final l in productionCatalog().levels) {
        for (final tile in l.tiles) {
          for (final word in tile.text.split(' ')) {
            final painter = TextPainter(
              text: TextSpan(
                text: word,
                style: const TextStyle(
                  fontFamily: 'Tile',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            final effective = painter.width > textWidth
                ? 15 * textWidth / painter.width
                : 15.0;
            expect(
              effective,
              greaterThanOrEqualTo(11),
              reason: '${l.id}: $word',
            );
            painter.dispose();
          }
        }
      }
    },
  );
  testWidgets('capture six real Flutter states with bundled fonts', (
    tester,
  ) async {
    await loadCaptureFonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(
      productionCatalog(),
      MemoryStorage(),
      clock: () => DateTime(2026, 10, 27),
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: LexiStackApp(controller: c),
      ),
    );
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File(
          'docs/screenshots/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('01_home');
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();
    final g = c.campaigns.values.single;
    for (final t in g.level.categories.first.tiles) {
      await tester.tap(find.byKey(Key('tile-${t.id}')));
    }
    await capture('02_board_selected');
    c.submit(g);
    for (final t in g.level.categories[1].tiles) {
      c.toggle(g, t.id);
    }
    c.submit(g);
    await capture('03_board_solved');
    solve(c, g);
    await capture('04_result');
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('all-packs')));
    await tester.tap(find.byKey(const Key('all-packs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyday Echoes'));
    await capture('05_packs');
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 800);
    await capture('06_desktop_frame');
    await c.flushed;
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('render the native app mark for launchers', (tester) async {
    final targets = <String, int>{
      'web/favicon.png': 32,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
      for (final e in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries)
        'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png': e.value,
    };
    for (final e in targets.entries) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final s = e.value.toDouble();
      canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = violet);
      final gap = s * 0.07, tile = s * 0.27, start = (s - 2 * tile - gap) / 2;
      for (var i = 0; i < 4; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              start + (i % 2) * (tile + gap),
              start + (i ~/ 2) * (tile + gap),
              tile,
              tile,
            ),
            Radius.circular(s * 0.05),
          ),
          Paint()..color = tierColors[i],
        );
      }
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final image = await picture.toImage(e.value, e.value);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        await File(e.key).writeAsBytes(bytes);
        if (e.value == 192 && e.key == 'web/icons/Icon-192.png') {
          final header = ByteData(22)
            ..setUint16(2, 1, Endian.little)
            ..setUint16(4, 1, Endian.little)
            ..setUint8(6, 192)
            ..setUint8(7, 192)
            ..setUint16(10, 1, Endian.little)
            ..setUint16(12, 32, Endian.little)
            ..setUint32(14, bytes.length, Endian.little)
            ..setUint32(18, 22, Endian.little);
          await File(
            'windows/runner/resources/app_icon.ico',
          ).writeAsBytes([...header.buffer.asUint8List(), ...bytes]);
        }
        image.dispose();
      });
      picture.dispose();
    }
  });
}
