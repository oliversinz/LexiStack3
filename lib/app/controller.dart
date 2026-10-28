import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/content.dart';
import '../domain/daily.dart';
import '../domain/game.dart';

abstract interface class ProgressStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class LocalStorage implements ProgressStorage {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  @override
  Future<String?> read() => prefs.getString('lexistack.progress.v1');
  @override
  Future<void> write(String value) =>
      prefs.setString('lexistack.progress.v1', value);
}

class MemoryStorage implements ProgressStorage {
  String? value;
  MemoryStorage([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class ResultRecord {
  final String id, levelId, heading, share;
  final String? date;
  final bool won;
  final int mistakes, stars, reward;
  const ResultRecord(
    this.id,
    this.levelId,
    this.heading,
    this.share,
    this.date,
    this.won,
    this.mistakes,
    this.stars,
    this.reward,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'level': levelId,
    'heading': heading,
    'share': share,
    'date': date,
    'won': won,
    'mistakes': mistakes,
    'stars': stars,
    'reward': reward,
  };
  static ResultRecord parse(Object? raw) {
    final j = object(raw, 'result');
    final date = j['date'];
    if (date != null && (date is! String || !validDate(date))) {
      bad('result', 'invalid date');
    }
    if (j['won'] is! bool) bad('result', 'invalid outcome');
    final won = j['won'] as bool,
        mistakes = integer(j['mistakes'], 'mistakes', 0, 1000000);
    final stars = integer(j['stars'], 'stars', 0, 3);
    if (stars !=
        (won
            ? mistakes == 0
                  ? 3
                  : mistakes <= 2
                  ? 2
                  : 1
            : 0)) {
      bad('result', 'inconsistent stars');
    }
    return ResultRecord(
      string(j['id'], 'id'),
      string(j['level'], 'level'),
      string(j['heading'], 'heading'),
      string(j['share'], 'share'),
      date as String?,
      won,
      mistakes,
      stars,
      integer(j['reward'], 'reward', 0, 75),
    );
  }
}

class AppController extends ChangeNotifier {
  final Catalog catalog;
  final ProgressStorage storage;
  final Clock clock;
  int coins = 150, sequence = 0;
  String theme = 'system';
  bool haptics = true;
  String? notice, lastCampaign;
  final Map<String, int> bestStars = {};
  final Set<String> practicePaid = {};
  final List<ResultRecord> history = [];
  final Map<String, Game> campaigns = {};
  Game? daily;
  Future<void> _writes = Future.value();
  AppController(this.catalog, this.storage, {Clock? clock})
    : clock = clock ?? DateTime.now;
  static Future<Catalog> loadCatalog() async {
    final m = object(
      jsonDecode(await rootBundle.loadString('assets/levels/manifest.json')),
      'manifest',
    );
    final packs = <Pack>[];
    for (final file in array(m['campaign'], 'manifest')) {
      packs.add(
        Pack.parse(
          await rootBundle.loadString('assets/levels/$file'),
          file as String,
        ),
      );
    }
    final dailyFile = string(m['daily'], 'manifest/daily');
    return Catalog(
      packs,
      Pack.parse(
        await rootBundle.loadString('assets/levels/$dailyFile'),
        dailyFile,
      ),
    );
  }

  String get today => civilDate(clock());
  void _salvage(void Function() work) {
    try {
      work();
    } catch (_) {
      notice =
          'Some saved progress could not be recovered. Valid progress was kept.';
    }
  }

  Future<void> load() async {
    String? raw;
    try {
      raw = await storage.read();
    } catch (_) {
      notice =
          'Storage could not be read. Progress is temporary until saving succeeds.';
      notifyListeners();
      return;
    }
    if (raw == null) return;
    try {
      final j = object(jsonDecode(raw), 'progress');
      if (j['version'] != 1) bad('progress', 'unsupported version');
      _salvage(() => coins = integer(j['coins'], 'coins', 0, 1000000000));
      _salvage(
        () => sequence = integer(j['sequence'], 'sequence', 0, 1000000000),
      );
      _salvage(() {
        if (!['system', 'light', 'dark'].contains(j['theme'])) {
          bad('theme', 'unknown');
        }
        theme = j['theme'] as String;
      });
      _salvage(() {
        if (j['haptics'] is! bool) bad('haptics', 'invalid');
        haptics = j['haptics'] as bool;
      });
      _salvage(() {
        for (final e in object(j['bestStars'], 'stars').entries) {
          _salvage(() => bestStars[e.key] = integer(e.value, 'stars', 1, 3));
        }
      });
      _salvage(() {
        for (final e in array(j['practicePaid'], 'practice')) {
          _salvage(() => practicePaid.add(string(e, 'practice')));
        }
      });
      final ids = <String>{}, dates = <String>{};
      _salvage(() {
        for (final e in array(j['history'], 'history')) {
          _salvage(() {
            final r = ResultRecord.parse(e);
            if (!ids.add(r.id) || (r.date != null && !dates.add(r.date!))) {
              bad('history', 'duplicate payout/result');
            }
            history.add(r);
            final n = int.tryParse(r.id.replaceFirst('attempt_', ''));
            if (n != null && n > sequence) sequence = n;
            if (r.won &&
                r.date == null &&
                (bestStars[r.levelId] ?? 0) < r.stars) {
              bestStars[r.levelId] = r.stars;
            }
            if (r.reward == 5 && r.date == null) practicePaid.add(r.levelId);
          });
        }
      });
      _salvage(() {
        for (final e in object(j['campaigns'], 'campaigns').entries) {
          _salvage(() {
            final l = catalog.find(e.key);
            if (l == null || l.packId == catalog.daily.id) {
              bad(e.key, 'missing campaign content');
            }
            final g = Game.restore(l, e.value);
            if (g.date != null ||
                g.finalized != history.any((r) => r.id == g.attemptId)) {
              bad(e.key, 'inconsistent result');
            }
            if (campaigns.values.any((v) => v.attemptId == g.attemptId)) {
              bad(e.key, 'duplicate attempt');
            }
            campaigns[e.key] = g;
          });
        }
      });
      if (j['daily'] != null) {
        _salvage(() {
          final d = object(j['daily'], 'daily');
          if (d['date'] != today) return;
          final l = catalog.find(string(d['level'], 'daily level'));
          if (l == null ||
              l.packId != catalog.daily.id ||
              l.id != dailyLevel.id) {
            bad('daily', 'missing or changed content');
          }
          final g = Game.restore(l, d);
          if (g.finalized !=
              history.any((r) => r.date == today && r.id == g.attemptId)) {
            bad('daily', 'inconsistent outcome');
          }
          daily = g;
        });
      }
      for (final g in [...campaigns.values, ?daily]) {
        final n = int.tryParse(g.attemptId.replaceFirst('attempt_', ''));
        if (n != null && n > sequence) sequence = n;
      }
      if (j['lastCampaign'] is String) {
        lastCampaign = j['lastCampaign'] as String;
      }
    } catch (_) {
      notice =
          'Saved progress was unreadable or from another version. Fresh defaults were restored.';
    }
    refreshDate(notify: false);
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'coins': coins,
    'sequence': sequence,
    'theme': theme,
    'haptics': haptics,
    'bestStars': bestStars,
    'practicePaid': practicePaid.toList(),
    'history': history.map((r) => r.toJson()).toList(),
    'campaigns': campaigns.map((k, v) => MapEntry(k, v.toJson())),
    'daily': daily?.toJson(),
    'lastCampaign': lastCampaign,
  };
  Future<void> save() {
    final snapshot = jsonEncode(toJson());
    _writes = _writes.then((_) async {
      try {
        await storage.write(snapshot);
        if (notice?.startsWith('Could not save') ?? false) {
          notice = null;
          notifyListeners();
        }
      } catch (_) {
        notice =
            'Could not save progress on this device. Keep the game open and try again.';
        notifyListeners();
      }
    });
    return _writes;
  }

  Future<void> get flushed => _writes;
  void changed() {
    notifyListeners();
    save();
  }

  bool unlocked(Level l) {
    final p = catalog.pack(l.packId);
    final i = p.levels.indexOf(l);
    return i == 0 || bestStars.containsKey(p.levels[i - 1].id);
  }

  Game? openCampaign(Level l, {bool replay = false}) {
    if (!unlocked(l) || l.packId == catalog.daily.id) return null;
    var g = campaigns[l.id];
    if (g == null || (replay && g.finalized)) {
      sequence++;
      g = Game(
        l,
        attemptId: 'attempt_$sequence',
        seed: stableSeed('${l.id}/$sequence'),
      );
      campaigns[l.id] = g;
    }
    campaigns.remove(l.id);
    campaigns[l.id] = g;
    lastCampaign = l.id;
    changed();
    return g;
  }

  Game? continueCampaign() {
    final recent = campaigns[lastCampaign];
    if (recent != null && !recent.finalized) return recent;
    // Insertion order reflects initial entry; the last-entered unfinished game
    // is explicitly tracked, including when a different level was finalized.
    final unfinished = campaigns.values.where((g) => !g.finalized).toList();
    if (unfinished.isNotEmpty) return unfinished.last;
    for (final p in catalog.campaign) {
      for (final l in p.levels) {
        if (!bestStars.containsKey(l.id) && unlocked(l)) return openCampaign(l);
      }
    }
    return null;
  }

  Level get dailyLevel =>
      catalog.daily.levels[dayIndex(clock()) % catalog.daily.levels.length];
  ResultRecord? get dailyResult {
    for (final r in history) {
      if (r.date == today) return r;
    }
    return null;
  }

  Game? openDaily() {
    refreshDate(notify: false);
    if (daily != null) return daily;
    if (dailyResult != null) return null;
    sequence++;
    daily = Game(
      dailyLevel,
      attemptId: 'attempt_$sequence',
      seed: stableSeed('daily/$today'),
      date: today,
    );
    changed();
    return daily;
  }

  void refreshDate({bool notify = true}) {
    if (daily != null && daily!.date != today) {
      daily = null;
      if (notify) changed();
    }
  }

  bool _current(Game g) {
    if (g.date != null && g.date != today) {
      refreshDate();
      return false;
    }
    return g.date == null
        ? identical(campaigns[g.level.id], g)
        : identical(daily, g);
  }

  void toggle(Game g, String id) {
    if (!_current(g)) return;
    g.toggle(id);
    changed();
  }

  void drag(Game g, String from, [String? to]) {
    if (!_current(g)) return;
    g.drag(from, to);
    changed();
  }

  void deselect(Game g) {
    if (!_current(g)) return;
    g.deselect();
    changed();
  }

  void shuffle(Game g) {
    if (!_current(g)) return;
    g.shuffle();
    changed();
  }

  GuessResult submit(Game g) {
    if (!_current(g)) return const GuessResult(GuessKind.invalid);
    final r = g.submit();
    if (g.finalized) _settle(g);
    changed();
    return r;
  }

  bool buy(Game g, Booster b) {
    if (!_current(g) || coins < b.price || !g.canBoost(b)) return false;
    if (!g.boost(b)) return false;
    coins -= b.price;
    changed();
    return true;
  }

  bool reveal(Game g) {
    if (!_current(g) || !g.reveal()) return false;
    _settle(g);
    changed();
    return true;
  }

  String heading(Game g) => g.date != null
      ? 'Daily ${g.date}'
      : '${catalog.pack(g.level.packId).title} #${catalog.pack(g.level.packId).levels.indexOf(g.level) + 1}';
  ResultRecord? result(Game g) {
    for (final r in history) {
      if (r.id == g.attemptId) return r;
    }
    return null;
  }

  void _settle(Game g) {
    if (!g.finalized ||
        result(g) != null ||
        (g.date != null && history.any((r) => r.date == g.date))) {
      return;
    }
    var reward = 0;
    if (g.status == GameStatus.won) {
      final starReward = {3: 50, 2: 30, 1: 15}[g.stars]!;
      if (g.date != null) {
        reward = starReward + 25;
      } else {
        if (!bestStars.containsKey(g.level.id)) {
          reward = starReward;
        } else if (practicePaid.add(g.level.id)) {
          reward = 5;
        }
        if ((bestStars[g.level.id] ?? 0) < g.stars) {
          bestStars[g.level.id] = g.stars;
        }
      }
    }
    coins += reward;
    history.add(
      ResultRecord(
        g.attemptId,
        g.level.id,
        heading(g),
        g.share(heading(g)),
        g.date,
        g.status == GameStatus.won,
        g.mistakes,
        g.status == GameStatus.won ? g.stars : 0,
        reward,
      ),
    );
  }

  int get wins => history.where((r) => r.won).length;
  int get perfectWins => history.where((r) => r.won && r.mistakes == 0).length;
  List<int> get distribution => List.generate(
    5,
    (i) => history
        .where((r) => r.won && (r.mistakes >= 4 ? 4 : r.mistakes) == i)
        .length,
  );
  int get currentDailyStreak {
    if (dailyResult?.won == false) return 0;
    final dates = history
        .where((r) => r.date != null && r.won)
        .map((r) => r.date!)
        .toSet();
    var d = civilUtc(clock());
    if (!dates.contains(civilDate(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (dates.contains(civilDate(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get bestDailyStreak {
    final dates =
        history
            .where((r) => r.date != null && r.won)
            .map((r) => r.date!)
            .toSet()
            .toList()
          ..sort();
    var best = 0, run = 0;
    DateTime? previous;
    for (final s in dates) {
      final d = DateTime.parse('${s}T00:00:00Z');
      run = previous != null && d.difference(previous).inDays == 1
          ? run + 1
          : 1;
      if (run > best) best = run;
      previous = d;
    }
    return best;
  }

  void settings({String? theme, bool? haptics}) {
    if (theme != null) this.theme = theme;
    if (haptics != null) this.haptics = haptics;
    changed();
  }

  Future<void> reset() async {
    coins = 150;
    sequence = 0;
    theme = 'system';
    haptics = true;
    notice = null;
    lastCampaign = null;
    bestStars.clear();
    practicePaid.clear();
    history.clear();
    campaigns.clear();
    daily = null;
    notifyListeners();
    await save();
  }
}
