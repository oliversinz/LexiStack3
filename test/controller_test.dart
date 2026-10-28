import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/domain/content.dart';
import 'package:lexistack/domain/daily.dart';
import 'package:lexistack/domain/game.dart';
import 'support.dart';

class DelayedStorage implements ProgressStorage {
  final gate = Completer<void>();
  final values = <String>[];
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {
    if (values.isEmpty) await gate.future;
    values.add(value);
  }
}

class FailingStorage implements ProgressStorage {
  bool fail = true;
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String s) async {
    if (fail) throw StateError('disk full');
    value = s;
  }
}

void main() {
  late Catalog catalog;
  late MemoryStorage storage;
  late AppController c;
  late DateTime now;
  setUp(() {
    catalog = productionCatalog();
    storage = MemoryStorage();
    now = DateTime(2026, 10, 27);
    c = AppController(catalog, storage, clock: () => now);
  });
  test('fresh state and independent pack unlocking', () {
    expect(c.coins, 150);
    expect(c.history, isEmpty);
    for (final p in catalog.campaign) {
      expect(c.unlocked(p.levels.first), true);
      expect(c.unlocked(p.levels[1]), false);
    }
    expect(c.openCampaign(catalog.campaign.first.levels[1]), isNull);
    final g = c.openCampaign(catalog.campaign.first.levels.first)!;
    solve(c, g);
    expect(c.unlocked(catalog.campaign.first.levels[1]), true);
    expect(c.history.length, 1);
  });
  for (final m in [0, 1, 2, 3]) {
    test('first campaign win reward and stars after $m mistakes', () {
      final g = c.openCampaign(catalog.campaign.first.levels.first)!;
      for (var i = 0; i < m; i++) {
        mistake(c, g, i);
      }
      if (m > 0) expect(c.buy(g, Booster.life), true);
      solve(c, g);
      final stars = m == 0
          ? 3
          : m <= 2
          ? 2
          : 1;
      expect(c.bestStars[g.level.id], stars);
      expect(c.coins, 150 + (m > 0 ? -60 : 0) + {3: 50, 2: 30, 1: 15}[stars]!);
      expect(c.history.single.mistakes, m);
      c.submit(g);
      c.reveal(g);
      expect(c.history.length, 1);
    });
  }
  test('replay improves best stars and grants practice only once', () async {
    final l = catalog.campaign.first.levels.first;
    var g = c.openCampaign(l)!;
    mistake(c, g, 0);
    solve(c, g);
    expect(c.coins, 180);
    expect(c.bestStars[l.id], 2);
    g = c.openCampaign(l, replay: true)!;
    solve(c, g);
    expect(c.coins, 185);
    expect(c.bestStars[l.id], 3);
    await c.flushed;
    final reloaded = AppController(catalog, storage, clock: () => now);
    await reloaded.load();
    g = reloaded.openCampaign(l, replay: true)!;
    mistake(reloaded, g, 0);
    solve(reloaded, g);
    expect(reloaded.coins, 185);
    expect(reloaded.bestStars[l.id], 3);
    expect(reloaded.history.length, 3);
  });
  test('booster rejection never spends or mutates game', () {
    final g = c.openCampaign(catalog.campaign.first.levels.first)!;
    final before = jsonEncode(g.toJson());
    expect(c.buy(g, Booster.life), false);
    expect(c.coins, 150);
    expect(jsonEncode(g.toJson()), before);
    c.coins = 29;
    expect(c.buy(g, Booster.pair), false);
    expect(jsonEncode(g.toJson()), before);
    expect(c.coins, 29);
  });
  test(
    'hints, selection, shuffle and paid effects survive exact round trip',
    () async {
      final g = c.openCampaign(catalog.campaign.first.levels.first)!;
      c.toggle(g, g.level.categories[2].tiles[3].id);
      c.buy(g, Booster.pair);
      c.buy(g, Booster.peek);
      c.shuffle(g);
      expect(c.coins, 80);
      await c.flushed;
      final loaded = AppController(catalog, storage, clock: () => now);
      await loaded.load();
      expect(loaded.toJson(), c.toJson());
      expect(loaded.coins, 80);
    },
  );
  test(
    'pending decision resumes, rescue continues same attempt, reveal finalizes once',
    () async {
      final g = c.openCampaign(catalog.campaign.first.levels.first)!;
      for (var i = 0; i < 4; i++) {
        mistake(c, g, i);
      }
      expect(c.history, isEmpty);
      await c.flushed;
      final loaded = AppController(catalog, storage, clock: () => now);
      await loaded.load();
      final restored = loaded.continueCampaign()!;
      expect(restored.status, GameStatus.lostPendingDecision);
      expect(loaded.buy(restored, Booster.life), true);
      expect(restored.lives, 1);
      mistake(loaded, restored, 4);
      expect(loaded.history, isEmpty);
      loaded.reveal(restored);
      loaded.reveal(restored);
      expect(loaded.history.length, 1);
      expect(loaded.history.single.won, false);
      expect(loaded.buy(restored, Booster.life), false);
    },
  );
  test('four-plus mistake wins populate the right statistics bucket', () {
    final g = c.openCampaign(catalog.campaign.first.levels.first)!;
    for (var i = 0; i < 4; i++) {
      mistake(c, g, i);
    }
    c.buy(g, Booster.life);
    solve(c, g);
    expect(c.distribution, [0, 0, 0, 0, 1]);
    expect(c.perfectWins, 0);
    expect(c.wins, 1);
    expect(c.bestStars[g.level.id], 1);
  });
  test('continue uses the most recently entered unfinished attempt', () {
    final a = c.openCampaign(catalog.campaign[0].levels.first)!;
    final b = c.openCampaign(catalog.campaign[1].levels.first)!;
    c.openCampaign(a.level);
    expect(c.continueCampaign(), same(a));
    final d = c.openCampaign(catalog.campaign[2].levels.first)!;
    solve(c, d);
    expect(c.continueCampaign(), same(a));
    solve(c, a);
    expect(c.continueCampaign(), same(b));
  });
  test('all campaigns won makes continue open the selector', () {
    for (final p in catalog.campaign) {
      for (final l in p.levels) {
        solve(c, c.openCampaign(l)!);
      }
    }
    expect(c.continueCampaign(), isNull);
    expect(c.history.length, 32);
  });
  test('civil days are stable across DST and leap days', () {
    expect(
      dayIndex(DateTime(2026, 3, 30)) - dayIndex(DateTime(2026, 3, 29)),
      1,
    );
    expect(
      dayIndex(DateTime(2026, 10, 26)) - dayIndex(DateTime(2026, 10, 25)),
      1,
    );
    expect(dayIndex(DateTime(2028, 3, 1)) - dayIndex(DateTime(2028, 2, 28)), 2);
    expect(dayIndex(DateTime(2026, 1, 1)), 0);
    expect(validDate('2026-02-30'), false);
  });
  test(
    'daily deterministic board, same-day resume and single reward',
    () async {
      final g = c.openDaily()!;
      final other = AppController(
        catalog,
        MemoryStorage(),
        clock: () => now,
      ).openDaily()!;
      expect(g.order, other.order);
      expect(c.openDaily(), same(g));
      solve(c, g);
      expect(c.coins, 225);
      expect(c.currentDailyStreak, 1);
      expect(c.openDaily(), same(g));
      await c.flushed;
      final loaded = AppController(catalog, storage, clock: () => now);
      await loaded.load();
      loaded.submit(loaded.openDaily()!);
      expect(loaded.coins, 225);
      expect(loaded.history.length, 1);
    },
  );
  test(
    'tomorrow discards unfinished daily and blocks old-day boosters',
    () async {
      final g = c.openDaily()!;
      c.buy(g, Booster.pair);
      now = DateTime(2026, 10, 28);
      expect(c.buy(g, Booster.peek), false);
      expect(c.coins, 120);
      expect(c.history, isEmpty);
      final next = c.openDaily()!;
      expect(next.date, '2026-10-28');
      expect(next.pairs, isEmpty);
      expect(next.attemptId, isNot(g.attemptId));
      await c.flushed;
    },
  );
  test('streak: yesterday, today loss, missed day, independent best', () {
    solve(c, c.openDaily()!);
    now = DateTime(2026, 10, 28);
    expect(c.currentDailyStreak, 1);
    solve(c, c.openDaily()!);
    expect(c.bestDailyStreak, 2);
    now = DateTime(2026, 10, 29);
    final g = c.openDaily()!;
    for (var i = 0; i < 4; i++) {
      mistake(c, g, i);
    }
    expect(c.currentDailyStreak, 2);
    c.reveal(g);
    expect(c.currentDailyStreak, 0);
    now = DateTime(2026, 11, 1);
    expect(c.currentDailyStreak, 0);
    expect(c.bestDailyStreak, 2);
    solve(c, c.openDaily()!);
    expect(c.currentDailyStreak, 1);
  });
  test('corrupt root and version fall back explicitly', () async {
    for (final raw in ['{', '[]', '{"version":999}']) {
      final loaded = AppController(catalog, MemoryStorage(raw));
      await loaded.load();
      expect(loaded.coins, 150);
      expect(loaded.history, isEmpty);
      expect(loaded.notice, isNotNull);
    }
  });
  test(
    'one corrupt session is discarded independently of valid progress',
    () async {
      final a = c.openCampaign(catalog.campaign[0].levels.first)!;
      solve(c, a);
      final b = c.openCampaign(catalog.campaign[1].levels.first)!;
      c.buy(b, Booster.pair);
      final d = c.openCampaign(catalog.campaign[2].levels.first)!;
      await c.flushed;
      final j = jsonDecode(storage.value!) as Map<String, dynamic>;
      j['campaigns'][b.level.id]['lives'] = -1;
      storage.value = jsonEncode(j);
      final loaded = AppController(catalog, storage, clock: () => now);
      await loaded.load();
      expect(loaded.coins, 170);
      expect(loaded.bestStars[a.level.id], 3);
      expect(loaded.history.length, 1);
      expect(loaded.campaigns.containsKey(d.level.id), true);
      expect(loaded.campaigns.containsKey(b.level.id), false);
      expect(loaded.notice, isNotNull);
    },
  );
  test(
    'removed content preserves historical summaries and unrelated sessions',
    () async {
      solve(c, c.openCampaign(catalog.campaign[0].levels.first)!);
      c.openCampaign(catalog.campaign[1].levels.first);
      await c.flushed;
      final smaller = Catalog(catalog.campaign.sublist(1), catalog.daily);
      final loaded = AppController(smaller, storage, clock: () => now);
      await loaded.load();
      expect(loaded.history.length, 1);
      expect(loaded.wins, 1);
      expect(loaded.coins, 200);
      expect(loaded.bestStars['pack1_lvl01'], 3);
      expect(loaded.campaigns.length, 1);
    },
  );
  test(
    'forged references, inconsistent histories and duplicate payouts are salvaged',
    () async {
      solve(c, c.openCampaign(catalog.campaign[0].levels.first)!);
      await c.flushed;
      final j = jsonDecode(storage.value!) as Map<String, dynamic>;
      (j['history'] as List).add(j['history'][0]);
      j['campaigns']['pack1_lvl01']['guesses'][0]['ids'][0] = 'unknown';
      storage.value = jsonEncode(j);
      final loaded = AppController(catalog, storage, clock: () => now);
      await loaded.load();
      expect(loaded.history.length, 1);
      expect(loaded.coins, 200);
      expect(loaded.campaigns, isEmpty);
    },
  );
  test('writes serialize and never overwrite a newer state', () async {
    final s = DelayedStorage();
    final app = AppController(catalog, s);
    app.save();
    app.coins = 77;
    app.save();
    await Future<void>.delayed(Duration.zero);
    expect(s.values, isEmpty);
    s.gate.complete();
    await app.flushed;
    expect(s.values.map((s) => jsonDecode(s)['coins']), [150, 77]);
  });
  test(
    'storage failure is visible and a subsequent successful save clears it',
    () async {
      final s = FailingStorage();
      final app = AppController(catalog, s);
      await app.save();
      expect(app.notice, contains('Could not save'));
      s.fail = false;
      await app.save();
      expect(app.notice, isNull);
      expect(s.value, isNotNull);
    },
  );
  test('reset restores the exact initial document', () async {
    solve(c, c.openDaily()!);
    c.settings(theme: 'dark', haptics: false);
    await c.reset();
    final fresh = AppController(catalog, MemoryStorage(), clock: () => now);
    expect(c.toJson(), fresh.toJson());
    expect(jsonDecode(storage.value!), fresh.toJson());
  });
}
