import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android touch, hints, SharedPreferences restart and clipboard', (
    t,
  ) async {
    final catalog = await AppController.loadCatalog(), storage = LocalStorage();
    var c = AppController(
      catalog,
      storage,
      clock: () => DateTime(2026, 10, 27),
    );
    await c.reset();
    await t.pumpWidget(LexiStackApp(controller: c));
    await t.pumpAndSettle();
    Future<void> tap(String key) async {
      final f = find.byKey(Key(key));
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await tap('continue');
    var g = c.campaigns.values.single;
    final from = find.byKey(Key('tile-${g.order[0]}')),
        to = find.byKey(Key('tile-${g.order[1]}'));
    final gesture = await t.startGesture(t.getCenter(from));
    await t.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(t.getCenter(to));
    await t.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await t.pumpAndSettle();
    expect(g.selection.length, 2);
    await tap('boost-pair');
    expect(c.coins, 120);
    await c.flushed;
    final saved = g.toJson();
    await t.pumpWidget(const SizedBox());
    c = AppController(
      catalog,
      LocalStorage(),
      clock: () => DateTime(2026, 10, 27),
    );
    await c.load();
    await t.pumpWidget(LexiStackApp(controller: c));
    await t.pumpAndSettle();
    await tap('continue');
    g = c.campaigns.values.single;
    expect(g.toJson(), saved);
    expect(c.coins, 120);
    await tap('deselect');
    for (final cat in g.level.categories) {
      for (final tile in cat.tiles) {
        await tap('tile-${tile.id}');
      }
      await tap('submit');
    }
    expect(c.history.length, 1);
    expect(c.coins, 170);
    await tap('share');
    expect(
      (await Clipboard.getData('text/plain'))?.text,
      g.share(c.heading(g)),
    );
    expect(t.takeException(), isNull);
    await c.flushed;
    await t.pumpWidget(const SizedBox());
  });
}
