import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/domain/content.dart';
import 'package:lexistack/domain/game.dart';

Level fixture() => Level(
  'oracle',
  'test',
  'Oracle',
  [
    for (var i = 0; i < 4; i++)
      Category(
        'g$i',
        'Category $i',
        'A sufficiently long factual sentence for testing.',
        i + 1,
        [
          for (var j = 0; j < 4; j++)
            Tile(
              'oracle/g$i/$j',
              [
                ['MARS', 'VENUS', 'SATURN', 'JUPITER'],
                ['MERCURY', 'LEAD', 'GOLD', 'IRON'],
                ['ROSE', 'LILY', 'DAISY', 'IRIS'],
                ['RED', 'BLUE', 'GREEN', 'PINK'],
              ][i][j],
              'g$i',
              i + 1,
            ),
        ],
      ),
  ],
  [
    const RedHerring(['MERCURY'], 'Mercury is both a planet and an element.'),
  ],
);
Game fresh() => Game(fixture(), attemptId: '1', seed: 42);
GuessResult guess(Game g, List<String> words) {
  g.deselect();
  for (final word in words) {
    g.select(g.level.tiles.firstWhere((t) => t.text == word).id);
  }
  return g.submit();
}

void main() {
  test('Park–Miller golden sequence and combo reset after solving', () {
    final random = StableRandom(0);
    expect(List.generate(5, (_) => random.next(2147483647)), [
      48271,
      182605794,
      1291394886,
      1914720637,
      2078669041,
    ]);
    final g = fresh();
    guess(g, ['MARS', 'VENUS', 'SATURN', 'JUPITER']);
    expect(g.combo, 1);
    g.select('oracle/g0/0');
    expect(g.selection, isEmpty);
    guess(g, ['MERCURY', 'LEAD', 'GOLD', 'ROSE']);
    expect(g.combo, 0);
    expect(g.mistakes, 1);
  });
  test('hints exhaust eligibility and corrupt restore states are rejected', () {
    final g = fresh();
    for (var i = 0; i < 4; i++) {
      expect(g.boost(Booster.peek), true);
      expect(g.boost(Booster.pair), true);
    }
    final snapshot = g.toJson();
    expect(g.boost(Booster.peek), false);
    expect(g.boost(Booster.pair), false);
    expect(g.toJson(), snapshot);
    final corrupt = Map<String, dynamic>.from(snapshot)..['status'] = 'won';
    expect(() => Game.restore(g.level, corrupt), throwsA(isA<ContentError>()));
  });
  test('oracle instance one: exact match', () {
    final g = fresh();
    expect(
      guess(g, ['JUPITER', 'MARS', 'VENUS', 'SATURN']).kind,
      GuessKind.correct,
    );
    expect(g.solved, ['g0']);
    expect(g.order.length, 12);
    expect(g.lives, 4);
    expect(g.selection, isEmpty);
  });
  test('oracle instance two: one away, duplicate, regular mismatch', () {
    final g = fresh();
    expect(guess(g, ['MARS', 'VENUS', 'SATURN', 'MERCURY']).isOneAway, true);
    expect(g.lives, 3);
    expect(
      guess(g, ['MERCURY', 'SATURN', 'VENUS', 'MARS']).kind,
      GuessKind.alreadyGuessed,
    );
    expect(g.lives, 3);
    expect(g.guesses.length, 1);
    expect(guess(g, ['MARS', 'VENUS', 'MERCURY', 'GOLD']).isOneAway, false);
    expect(g.lives, 2);
    expect(g.guesses.length, 2);
    expect(g.solved, isEmpty);
  });
  test('selection, additive drags, cap, shuffle and invalid are harmless', () {
    final g = fresh(), other = fresh();
    expect(g.order, other.order);
    expect(g.submit().kind, GuessKind.invalid);
    g.drag(g.order[0], g.order[1]);
    g.drag(g.order[2]);
    g.select(g.order[3]);
    final selected = List.of(g.selection);
    g.select(g.order[4]);
    expect(g.selection, selected);
    g.shuffle();
    other.shuffle();
    expect(g.order, other.order);
    expect(g.selection, selected);
    expect(g.lives, 4);
    g.deselect();
    expect(g.selection, isEmpty);
  });
  test('pair targeting, peek and restored state remain deterministic', () {
    final g = fresh();
    g.select('oracle/g2/3');
    expect(g.boost(Booster.pair), true);
    expect(g.pairs['g2']!.first, 'oracle/g2/3');
    g.boost(Booster.pair);
    expect(g.pairs.containsKey('g0'), true);
    g.boost(Booster.peek);
    expect(g.peeks, {'g0'});
    expect(g.boost(Booster.life), false);
    final restored = Game.restore(g.level, g.toJson());
    expect(restored.toJson(), g.toJson());
    restored.shuffle();
    g.shuffle();
    expect(restored.order, g.order);
  });
  test('pending loss, rescue, lifetime mistakes, final reveal', () {
    final g = fresh();
    for (var i = 0; i < 4; i++) {
      g.deselect();
      for (final id in [
        'oracle/g0/0',
        'oracle/g0/1',
        'oracle/g1/0',
        'oracle/g2/$i',
      ]) {
        g.select(id);
      }
      g.submit();
    }
    expect(g.status, GameStatus.lostPendingDecision);
    expect(g.finalized, false);
    expect(g.share('test'), '');
    expect(g.boost(Booster.peek), false);
    expect(g.boost(Booster.life), true);
    expect(g.lives, 1);
    expect(g.status, GameStatus.playing);
    expect(g.stars, 1);
    guess(g, ['MARS', 'VENUS', 'LEAD', 'ROSE']);
    expect(g.status, GameStatus.lostPendingDecision);
    expect(g.reveal(), true);
    expect(g.boost(Booster.life), false);
    expect(g.reveal(), false);
    expect(Game.restore(g.level, g.toJson()).status, GameStatus.lostFinal);
  });
  test('four exact groups win; sharing keeps selection order', () {
    final g = fresh();
    for (final c in g.level.categories) {
      for (final t in c.tiles.reversed) {
        g.select(t.id);
      }
      g.submit();
    }
    expect(g.status, GameStatus.won);
    expect(g.combo, 4);
    expect(g.stars, 3);
    expect(
      g.share('Daily 2026-10-27'),
      'LexiStack · Daily 2026-10-27\n★★★ · 0 mistakes\n🟨🟨🟨🟨\n🟩🟩🟩🟩\n🟦🟦🟦🟦\n🟪🟪🟪🟪',
    );
  });
}
