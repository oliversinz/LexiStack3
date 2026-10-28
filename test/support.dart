import 'dart:convert';
import 'dart:io';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/domain/content.dart';
import 'package:lexistack/domain/game.dart';

Map<String, String> productionFiles() {
  final m =
      jsonDecode(File('assets/levels/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final f in [...m['campaign'] as List, m['daily']])
      f as String: File('assets/levels/$f').readAsStringSync(),
  };
}

Catalog productionCatalog() {
  final packs = productionFiles().entries
      .map((e) => Pack.parse(e.value, e.key))
      .toList();
  return Catalog(packs.sublist(0, 4), packs.last);
}

void solve(AppController c, Game g) {
  for (final group in g.remaining.toList()) {
    g.deselect();
    for (final t in group.tiles) {
      g.select(t.id);
    }
    c.submit(g);
  }
}

void mistake(AppController c, Game g, int index) {
  g.deselect();
  for (final id in [
    g.level.categories[0].tiles[0].id,
    g.level.categories[0].tiles[1].id,
    g.level.categories[1].tiles[(index ~/ 4) % 4].id,
    g.level.categories[2].tiles[index % 4].id,
  ]) {
    g.select(id);
  }
  c.submit(g);
}
