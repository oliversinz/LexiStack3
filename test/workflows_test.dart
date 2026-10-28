import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/domain/game.dart';
import 'package:lexistack/ui/app.dart';
import 'support.dart';

Future<AppController> mount(
  WidgetTester tester, {
  MemoryStorage? storage,
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = AppController(
    productionCatalog(),
    storage ?? MemoryStorage(),
    clock: () => DateTime(2026, 10, 27),
  );
  await c.load();
  await tester.pumpWidget(LexiStackApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

Future<void> tap(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, List<String> ids) async {
  for (final id in ids) {
    await tap(t, 'tile-$id');
  }
}

Future<void> finish(WidgetTester t, AppController c) async {
  await c.flushed;
  await t.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('midnight expires an open unfinished Daily without counting it', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var now = DateTime(2026, 10, 27, 23, 59);
    final c = AppController(
      productionCatalog(),
      MemoryStorage(),
      clock: () => now,
    );
    await t.pumpWidget(LexiStackApp(controller: c));
    await t.pumpAndSettle();
    await tap(t, 'daily');
    await tap(t, 'boost-pair');
    now = DateTime(2026, 10, 28, 0, 1);
    await t.pump(const Duration(seconds: 31));
    await t.pumpAndSettle();
    expect(c.daily, isNull);
    expect(c.history, isEmpty);
    expect(c.coins, 120);
    expect(find.byKey(const Key('continue')), findsOneWidget);
    await tap(t, 'daily');
    expect(c.daily!.date, '2026-10-28');
    expect(c.daily!.pairs, isEmpty);
    await finish(t, c);
  });
  testWidgets('explicit replay flow cannot farm practice payouts', (t) async {
    final c = await mount(t);
    await tap(t, 'continue');
    for (var attempt = 0; attempt < 3; attempt++) {
      final g = c.campaigns['pack1_lvl01']!;
      for (final cat in g.level.categories) {
        await choose(t, cat.tiles.map((v) => v.id).toList());
        await tap(t, 'submit');
      }
      expect(c.coins, attempt == 0 ? 200 : 205);
      if (attempt < 2) {
        await tap(t, 'back');
        await tap(t, 'all-packs');
        await t.tap(find.text('Everyday Echoes'));
        await t.pumpAndSettle();
        await tap(t, 'level-pack1_lvl01');
      }
    }
    expect(c.history.length, 3);
    await finish(t, c);
  });
  testWidgets('four packs, daily and locked stage navigation', (t) async {
    final c = await mount(t);
    for (final p in c.catalog.campaign) {
      expect(find.text(p.title), findsOneWidget);
    }
    expect(find.text('The Daily Stack'), findsOneWidget);
    await tap(t, 'all-packs');
    await t.tap(find.text('Everyday Echoes'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('level-pack1_lvl02')), findsNothing);
    await tap(t, 'level-pack1_lvl01');
    expect(c.campaigns.values.single.order.length, 16);
    for (var i = 1; i <= 4; i++) {
      expect(find.byKey(Key('slot-g$i')), findsOneWidget);
    }
    await finish(t, c);
  });
  testWidgets('fifth selection, One Away, duplicate, and touch drag', (
    t,
  ) async {
    final c = await mount(t);
    await tap(t, 'continue');
    final g = c.campaigns.values.single;
    final a = g.level.categories[0].tiles, b = g.level.categories[1].tiles;
    final ids = [a[0].id, a[1].id, a[2].id, b[0].id];
    await choose(t, ids);
    await tap(t, 'tile-${b[1].id}');
    expect(g.selection, ids);
    await tap(t, 'submit');
    expect(find.text('One Away! Swap one tile.'), findsOneWidget);
    expect(g.lives, 3);
    await tap(t, 'deselect');
    await choose(t, ids.reversed.toList());
    await tap(t, 'submit');
    expect(find.text('Already guessed! Try a different set.'), findsOneWidget);
    expect(g.lives, 3);
    expect(g.guesses.length, 1);
    await tap(t, 'deselect');
    final from = find.byKey(Key('tile-${a[0].id}')),
        to = find.byKey(Key('tile-${b[0].id}'));
    await t.ensureVisible(from);
    final gesture = await t.startGesture(t.getCenter(from));
    await t.pump(const Duration(milliseconds: 250));
    await gesture.moveTo(t.getCenter(to));
    await t.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await t.pumpAndSettle();
    expect(g.selection, [a[0].id, b[0].id]);
    final another = find.byKey(Key('tile-${a[1].id}'));
    final tray = find.byKey(const Key('selection-tray'));
    final drag = await t.startGesture(t.getCenter(another));
    await t.pump(const Duration(milliseconds: 250));
    await drag.moveTo(t.getCenter(tray));
    await t.pump(const Duration(milliseconds: 100));
    await drag.up();
    await t.pumpAndSettle();
    expect(g.selection, [a[0].id, b[0].id, a[1].id]);
    await finish(t, c);
  });
  testWidgets('all three boosters change visible board and coins', (t) async {
    final c = await mount(t);
    await tap(t, 'continue');
    final g = c.campaigns.values.single;
    await tap(t, 'boost-pair');
    expect(c.coins, 120);
    expect(g.pairs.length, 1);
    expect(find.text('120'), findsOneWidget);
    await tap(t, 'boost-peek');
    expect(c.coins, 80);
    expect(find.text(g.level.categories.first.title), findsOneWidget);
    mistake(c, g, 0);
    await t.pumpAndSettle();
    await tap(t, 'boost-life');
    expect(g.lives, 4);
    expect(c.coins, 20);
    expect(find.text('20'), findsOneWidget);
    expect(
      (t.widget(find.byKey(const Key('boost-pair'))) as OutlinedButton)
          .onPressed,
      isNull,
    );
    await finish(t, c);
  });
  testWidgets('pending loss hides solutions, rescue works, reveal is final', (
    t,
  ) async {
    final c = await mount(t);
    await tap(t, 'continue');
    final g = c.campaigns.values.single;
    for (var i = 0; i < 4; i++) {
      mistake(c, g, i);
    }
    await t.pumpAndSettle();
    for (final cat in g.level.categories) {
      expect(find.text(cat.title), findsNothing);
      expect(find.text(cat.fact), findsNothing);
    }
    expect(find.byKey(const Key('share')), findsNothing);
    expect(c.history, isEmpty);
    await tap(t, 'back');
    await tap(t, 'continue');
    expect(find.byKey(const Key('rescue')), findsOneWidget);
    await tap(t, 'rescue');
    expect(g.status, GameStatus.playing);
    expect(g.lives, 1);
    expect(c.coins, 90);
    mistake(c, g, 4);
    await t.pumpAndSettle();
    await tap(t, 'reveal');
    expect(g.status, GameStatus.lostFinal);
    expect(c.history.length, 1);
    expect(find.text(g.level.categories.first.fact), findsOneWidget);
    expect(find.byKey(const Key('rescue')), findsNothing);
    await finish(t, c);
  });
  testWidgets('restart keeps hints; reset requires its confirmation', (
    t,
  ) async {
    final storage = MemoryStorage();
    final c = await mount(t, storage: storage);
    await tap(t, 'continue');
    final g = c.campaigns.values.single;
    await tap(t, 'tile-${g.order.first}');
    await tap(t, 'boost-pair');
    await c.flushed;
    await t.pumpWidget(const SizedBox());
    final restored = await mount(t, storage: storage);
    await tap(t, 'continue');
    expect(restored.campaigns.values.single.toJson(), g.toJson());
    expect(restored.coins, 120);
    await tap(t, 'back');
    await tap(t, 'settings');
    await tap(t, 'reset');
    expect(find.text('Start fresh?'), findsOneWidget);
    await t.tap(find.text('Keep my progress'));
    await t.pumpAndSettle();
    expect(restored.coins, 120);
    await tap(t, 'reset');
    await tap(t, 'confirm-reset');
    expect(restored.coins, 150);
    expect(restored.campaigns, isEmpty);
    expect(find.text('150'), findsOneWidget);
    await finish(t, restored);
  });
  testWidgets('daily exact clipboard format and no repeated reward', (t) async {
    String? clipboard;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final c = await mount(t);
    await tap(t, 'daily');
    final g = c.daily!,
        a = g.level.categories[0].tiles,
        b = g.level.categories[1].tiles;
    await choose(t, [a[0].id, a[1].id, a[2].id, b[0].id]);
    await tap(t, 'submit');
    await tap(t, 'deselect');
    await choose(t, [a[0].id, b[0].id, a[1].id, b[1].id]);
    await tap(t, 'submit');
    await tap(t, 'deselect');
    for (final cat in g.level.categories) {
      await choose(t, cat.tiles.map((v) => v.id).toList());
      await tap(t, 'submit');
    }
    await tap(t, 'share');
    expect(
      clipboard,
      'LexiStack · Daily 2026-10-27\n★★☆ · 2 mistakes\n🟨🟨🟨🟩\n🟨🟩🟨🟩\n🟨🟨🟨🟨\n🟩🟩🟩🟩\n🟦🟦🟦🟦\n🟪🟪🟪🟪',
    );
    expect(c.coins, 205);
    await tap(t, 'back');
    await tap(t, 'daily');
    expect(c.coins, 205);
    expect(c.history.length, 1);
    expect(find.byKey(const Key('submit')), findsNothing);
    await finish(t, c);
  });
  testWidgets('haptics toggle suppresses platform calls', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final c = await mount(t);
    await tap(t, 'continue');
    final g = c.campaigns.values.single;
    await tap(t, 'tile-${g.order.first}');
    expect(calls, contains('HapticFeedbackType.selectionClick'));
    c.settings(haptics: false);
    calls.clear();
    await t.pumpAndSettle();
    await tap(t, 'tile-${g.order[1]}');
    expect(calls, isEmpty);
    await finish(t, c);
  });
  for (final spec in [
    (const Size(360, 640), 1.0),
    (const Size(360, 640), 1.3),
    (const Size(390, 844), 1.3),
    (const Size(1280, 800), 1.0),
  ]) {
    testWidgets('screens fit ${spec.$1} at ${spec.$2}x', (t) async {
      final c = await mount(t, size: spec.$1, scale: spec.$2);
      expect(t.takeException(), isNull);
      await tap(t, 'continue');
      final g = c.campaigns.values.single;
      c.buy(g, Booster.peek);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const Key('boost-life')));
      solve(c, g);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('share')));
      expect(t.takeException(), isNull);
      await tap(t, 'back');
      await tap(t, 'settings');
      c.settings(theme: 'dark');
      await t.pumpAndSettle();
      await tap(t, 'reset');
      expect(t.takeException(), isNull);
      await t.tap(find.text('Keep my progress'));
      await t.pumpAndSettle();
      await finish(t, c);
    });
  }
}
