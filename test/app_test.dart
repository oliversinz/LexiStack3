import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/ui/app.dart';

void main() {
  testWidgets('actual app opens a stage and solves a production group', (tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final c=AppController(await AppController.loadCatalog(),MemoryStorage(),clock:()=>DateTime(2026,10,27));
    await tester.pumpWidget(LexiStackApp(controller:c));
    expect(find.text('150'),findsOneWidget);
    await tester.tap(find.byKey(const Key('continue'))); await tester.pumpAndSettle();
    final g=c.campaigns.values.single;
    expect(g.order.length,16);
    for(final tile in g.level.categories.first.tiles) {await tester.tap(find.byKey(Key('tile-${tile.id}'))); await tester.pumpAndSettle();}
    expect(g.selection.length,4);
    await tester.tap(find.byKey(const Key('submit'))); await tester.pumpAndSettle();
    expect(find.text(g.level.categories.first.fact),findsOneWidget);
    expect(g.order.length,12); expect(tester.takeException(),isNull);
    await c.flushed; await tester.pumpWidget(const SizedBox());
  });
}
