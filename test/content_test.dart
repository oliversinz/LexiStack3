import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/domain/content.dart';
import 'package:lexistack/domain/game.dart';
import 'support.dart';

void main() {
  test('final production catalog: exact counts, no errors or warnings', () {
    final v = validateCatalog(productionFiles(), dailyFile: 'daily.json');
    expect(v.errors, isEmpty);
    expect(v.warnings, isEmpty);
    expect(v.levelCount, 40);
    expect(v.packs.length, 5);
    expect(v.packs.map((p) => p.levels.length), everyElement(8));
  });
  test('every shipped puzzle solves using its intended partition', () {
    for (final l in productionCatalog().levels) {
      final g = Game(l, attemptId: l.id, seed: 917);
      for (final cat in l.categories) {
        for (final t in cat.tiles) {
          g.select(t.id);
        }
        expect(g.submit().kind, GuessKind.correct, reason: l.id);
      }
      expect(g.status, GameStatus.won);
      expect(g.lives, 4);
    }
  });
  test('partial catalog is valid but not a passing final catalog', () {
    final one = {'pack1.json': productionFiles()['pack1.json']!};
    expect(validateCatalog(one, partial: true).ok, true);
    expect(validateCatalog(one).ok, false);
    expect(validateCatalog({}, partial: true).ok, false);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'bad schema': (p) => p['schemaVersion'] = 1,
    'wrong type': (p) => p['levels'][0]['categories'][0]['tiles'] = 42,
    'short file': (p) => (p['levels'] as List).removeLast(),
    'wrong parent': (p) => p['levels'][0]['packId'] = 'other',
    'duplicate level': (p) => p['levels'][1]['id'] = p['levels'][0]['id'],
    'duplicate category': (p) => p['levels'][0]['categories'][1]['id'] = 'g1',
    'duplicate tier': (p) =>
        p['levels'][0]['categories'][1]['difficultyTier'] = 1,
    'extra category': (p) => (p['levels'][0]['categories'] as List).add(
      p['levels'][0]['categories'][0],
    ),
    'duplicate board tile': (p) =>
        p['levels'][0]['categories'][1]['tiles'][0] = 'TOAST',
    'lowercase tile': (p) =>
        p['levels'][0]['categories'][0]['tiles'][0] = 'toast',
    'long word': (p) =>
        p['levels'][0]['categories'][0]['tiles'][0] = 'EXTRAORDINARY',
    'three words': (p) =>
        p['levels'][0]['categories'][0]['tiles'][0] = 'ONE TWO THREE',
    'short fact': (p) =>
        p['levels'][0]['categories'][0]['triviaFact'] = 'Too short.',
    'multiple sentences': (p) => p['levels'][0]['categories'][0]['triviaFact'] =
        'This sentence is deliberately long enough. Here is another.',
    'missing red herring': (p) => p['levels'][0]['redHerrings'] = [],
    'wrong red herring reference': (p) =>
        p['levels'][0]['redHerrings'][0]['tiles'] = ['MISSING'],
    'duplicate title': (p) => p['levels'][1]['categories'][0]['title'] =
        p['levels'][0]['categories'][0]['title'],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key} with an actionable path', () {
      final p =
          jsonDecode(productionFiles()['pack1.json']!) as Map<String, dynamic>;
      e.value(p);
      final v = validateCatalog({'broken.json': jsonEncode(p)}, partial: true);
      expect(v.errors, isNotEmpty);
      expect(v.errors.first, anyOf(contains('broken.json'), contains('pack1')));
    });
  }
  test('malformed JSON has a friendly error', () {
    expect(
      validateCatalog({'bad.json': '{'}, partial: true).errors.single,
      contains('malformed JSON'),
    );
  });
  test('cross-file duplicates and overlapping groups are rejected', () {
    final files = productionFiles();
    files['duplicate.json'] = files['pack1.json']!;
    final v = validateCatalog(files, dailyFile: 'daily.json');
    expect(v.errors.any((e) => e.contains('duplicate pack')), true);
    expect(v.errors.any((e) => e.contains('overlaps three')), true);
  });
  test('tile usage across three levels is rejected', () {
    final p =
        jsonDecode(productionFiles()['pack1.json']!) as Map<String, dynamic>;
    p['levels'][2]['categories'][0]['tiles'][0] = 'TOAST';
    p['levels'][3]['categories'][0]['tiles'][0] = 'TOAST';
    expect(
      validateCatalog({
        'p.json': jsonEncode(p),
      }, partial: true).errors.any((e) => e.contains('occurs in 3')),
      true,
    );
  });
  test('unrelated tile in a fact is advisory', () {
    final p =
        jsonDecode(productionFiles()['pack1.json']!) as Map<String, dynamic>;
    p['levels'][0]['categories'][0]['triviaFact'] =
        'A bagel can be cut with a KNIFE before it is toasted.';
    final v = validateCatalog({'p.json': jsonEncode(p)}, partial: true);
    expect(v.errors, isEmpty);
    expect(v.warnings, isNotEmpty);
  });
  test('candidate replacement CLI is read-only', () async {
    final before = productionFiles();
    final r = await Process.run('dart', [
      'run',
      'tool/validate_levels.dart',
      'assets/levels/pack1.json',
    ], runInShell: Platform.isWindows);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('replacement of pack1.json'));
    expect(productionFiles(), before);
  });
}
