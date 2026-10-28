import 'dart:convert';

class ContentError implements Exception {
  final String message;
  ContentError(this.message);
  @override
  String toString() => message;
}
Never bad(String path, String reason) => throw ContentError('$path: $reason');
Map<String, dynamic> object(Object? value, String path) => value is Map<String, dynamic> ? value : bad(path, 'expected an object');
List<dynamic> array(Object? value, String path) => value is List ? value : bad(path, 'expected an array');
String string(Object? value, String path) => value is String && value.trim().isNotEmpty ? value : bad(path, 'expected a nonempty string');
int integer(Object? value, String path, int min, int max) => value is int && value >= min && value <= max ? value : bad(path, 'expected an integer in $min..$max');
String identifier(Object? value, String path) {
  final id = string(value, path);
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) bad(path, 'invalid identifier');
  return id;
}
String normalized(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
class Tile {
  final String id, text, categoryId;
  final int tier;
  const Tile(this.id, this.text, this.categoryId, this.tier);
}
class Category {
  final String id, title, fact;
  final int tier;
  final List<Tile> tiles;
  const Category(this.id, this.title, this.fact, this.tier, this.tiles);
}
class RedHerring {
  final List<String> tiles;
  final String note;
  const RedHerring(this.tiles, this.note);
}
class Level {
  final String id, packId, title;
  final List<Category> categories;
  final List<RedHerring> redHerrings;
  const Level(this.id, this.packId, this.title, this.categories, this.redHerrings);
  List<Tile> get tiles => categories.expand((c) => c.tiles).toList();
  Tile tile(String id) => tiles.firstWhere((t) => t.id == id);
  Category category(String id) => categories.firstWhere((c) => c.id == id);
}
class Pack {
  final String id, title, description;
  final List<Level> levels;
  const Pack(this.id, this.title, this.description, this.levels);
  static Pack parse(String source, String file) {
    dynamic decoded;
    try { decoded = jsonDecode(source); }
    on FormatException catch (e) { bad(file, 'malformed JSON: ${e.message}'); }
    final root = object(decoded, file);
    integer(root['schemaVersion'], '$file/schemaVersion', 2, 2);
    final p = object(root['pack'], '$file/pack');
    final id = identifier(p['id'], '$file/pack/id');
    final title = string(p['title'], '$file/pack/title');
    final description = string(p['description'], '$file/pack/description');
    final entries = array(root['levels'], '$file/levels');
    if (entries.length < 8) bad(file, 'a pack requires at least eight complete levels');
    final ids = <String>{};
    final levels = <Level>[];
    for (var i = 0; i < entries.length; i++) {
      final l = object(entries[i], '$file/levels[$i]');
      final lid = identifier(l['id'], '$file/levels[$i]/id');
      final path = '$file/$lid';
      if (!ids.add(lid)) bad(path, 'duplicate level ID');
      if (l['packId'] != id) bad(path, 'packId must be $id');
      final lt = string(l['title'], '$path/title');
      final groups = array(l['categories'], '$path/categories');
      if (groups.length != 4) bad(path, 'expected exactly four categories');
      final cids = <String>{}, words = <String>{};
      final tiers = <int>{};
      final categories = <Category>[];
      for (var j = 0; j < groups.length; j++) {
        final c = object(groups[j], '$path/categories[$j]');
        final cid = identifier(c['id'], '$path/categories[$j]/id');
        final cp = '$path/$cid';
        if (!cids.add(cid)) bad(cp, 'duplicate category ID');
        final tier = integer(c['difficultyTier'], '$cp/difficultyTier', 1, 4);
        if (!tiers.add(tier)) bad(cp, 'duplicate difficulty tier');
        final ct = string(c['title'], '$cp/title');
        final fact = string(c['triviaFact'], '$cp/triviaFact');
        if (fact.length < 40 || fact.length > 160) bad(cp, 'fact must be 40–160 characters');
        if (!RegExp(r'^[^.!?]+[.!?]$').hasMatch(fact)) bad(cp, 'fact must be exactly one sentence');
        final rawTiles = array(c['tiles'], '$cp/tiles');
        if (rawTiles.length != 4) bad(cp, 'expected exactly four tiles');
        final tiles = <Tile>[];
        for (var k = 0; k < rawTiles.length; k++) {
          final word = string(rawTiles[k], '$cp/tiles[$k]');
          if (!RegExp(r'^[A-Z]{1,10}( [A-Z]{1,10})?$').hasMatch(word)) bad(cp, 'invalid tile "$word": use 1–2 uppercase words, at most 10 letters each');
          if (!words.add(normalized(word))) bad(cp, 'duplicate board tile $word');
          tiles.add(Tile('$lid/$cid/$k', word, cid, tier));
        }
        categories.add(Category(cid, ct, fact, tier, List.unmodifiable(tiles)));
      }
      final rh = array(l['redHerrings'], '$path/redHerrings');
      if (rh.isEmpty) bad(path, 'at least one red herring required');
      final herrings = <RedHerring>[];
      for (final raw in rh) {
        final h = object(raw, '$path/redHerrings');
        final refs = array(h['tiles'], '$path/redHerrings/tiles').map((t) => string(t, '$path/redHerrings/tiles')).toList();
        if (refs.isEmpty || refs.toSet().length != refs.length || refs.any((t) => !words.contains(t))) bad(path, 'red herring must reference distinct, exact on-board tiles');
        final note = string(h['note'], '$path/redHerrings/note');
        if (note.length < 25) bad(path, 'red-herring note needs an explanation');
        herrings.add(RedHerring(refs, note));
      }
      categories.sort((a,b) => a.tier.compareTo(b.tier));
      levels.add(Level(lid, id, lt, List.unmodifiable(categories), List.unmodifiable(herrings)));
    }
    return Pack(id, title, description, List.unmodifiable(levels));
  }
}
class Catalog {
  final List<Pack> campaign;
  final Pack daily;
  Catalog(this.campaign, this.daily);
  List<Pack> get packs => [...campaign, daily];
  List<Level> get levels => packs.expand((p) => p.levels).toList();
  Level? find(String id) { for (final l in levels) { if (l.id == id) return l; } return null; }
  Pack pack(String id) => packs.firstWhere((p) => p.id == id);
}
class Validation {
  final List<String> errors = [], warnings = [];
  final List<Pack> packs = [];
  bool get ok => errors.isEmpty;
  int get levelCount => packs.fold(0, (n,p) => n + p.levels.length);
}
/// Structural checks cannot prove a unique semantic solution.
Validation validateCatalog(Map<String, String> files, {bool partial = false, String? dailyFile}) {
  final result = Validation();
  if (files.isEmpty) result.errors.add('No content files listed');
  for (final entry in files.entries) {
    try { result.packs.add(Pack.parse(entry.value, entry.key)); }
    on ContentError catch (e) { result.errors.add(e.message); }
  }
  if (!partial) {
    if (dailyFile == null || !files.containsKey(dailyFile)) result.errors.add('Missing separate daily pool');
    if (files.length - (dailyFile == null ? 0 : 1) < 4) result.errors.add('Final catalog requires at least four campaign packs');
  }
  final pids = <String>{}, lids = <String>{}, titles = <String>{};
  final uses = <String, Set<String>>{};
  final groups = <(String, Set<String>)>[];
  for (final p in result.packs) {
    if (!pids.add(p.id)) result.errors.add('${p.id}: duplicate pack ID');
    for (final l in p.levels) {
      if (!lids.add(l.id)) result.errors.add('${l.id}: duplicate level ID');
      for (final c in l.categories) {
        final path = '${p.id}/${l.id}/${c.id}';
        if (!titles.add(normalized(c.title))) result.errors.add('$path: duplicate category title ${c.title}');
        final words = c.tiles.map((t) => normalized(t.text)).toSet();
        for (final word in words) { (uses[word] ??= {}).add(l.id); }
        for (final other in groups) { if (other.$2.intersection(words).length >= 3) result.errors.add('$path: overlaps three or more tiles with ${other.$1}'); }
        groups.add((path, words));
        for (final tile in l.tiles.where((t) => t.categoryId != c.id && t.text.length >= 4)) {
          if (RegExp('\\b${RegExp.escape(tile.text)}\\b', caseSensitive: false).hasMatch(c.fact)) result.warnings.add('$path: trivia names unrelated board tile ${tile.text}');
        }
      }
    }
  }
  for (final e in uses.entries) { if (e.value.length > 2) result.errors.add('${e.key}: occurs in ${e.value.length} levels (${e.value.join(', ')})'); }
  return result;
}
