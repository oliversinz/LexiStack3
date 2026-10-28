import 'content.dart';

enum GameStatus { playing, won, lostPendingDecision, lostFinal }
enum GuessKind { invalid, alreadyGuessed, correct, mismatch }
enum Booster { pair, peek, life }
extension BoosterPrice on Booster { int get price => switch (this) { Booster.pair => 30, Booster.peek => 40, Booster.life => 60 }; }
class GuessResult {
  final GuessKind kind;
  final bool isOneAway;
  const GuessResult(this.kind, {this.isOneAway = false});
}
class Guess {
  final List<String> ids;
  final List<int> tiers;
  final bool correct;
  Guess(this.ids, this.tiers, this.correct);
  Map<String, dynamic> toJson() => {'ids': ids, 'tiers': tiers, 'correct': correct};
}

/// Park–Miller (48271, 2^31−1). Products stay below 2^53, making integer
/// arithmetic exact on JavaScript and VM. Fisher–Yates uses only this state.
class StableRandom {
  int state;
  StableRandom(int seed) : state = seed % 2147483646 + 1;
  int next(int max) { state = (state * 48271) % 2147483647; return state % max; }
}
int stableSeed(String text) => text.codeUnits.fold(7, (v,c) => (v * 31 + c) % 2147483646);

class Game {
  final Level level;
  final String attemptId;
  final String? date;
  final StableRandom random;
  GameStatus status = GameStatus.playing;
  int lives = 4, mistakes = 0, combo = 0, rescues = 0;
  final List<String> order = [], selection = [], solved = [];
  final List<Guess> guesses = [];
  final Set<String> wrongSets = {}, peeks = {};
  final Map<String, List<String>> pairs = {};
  Game(this.level, {required this.attemptId, required int seed, this.date}) : random = StableRandom(seed) {
    order.addAll(level.tiles.map((t) => t.id)); shuffle();
  }
  bool get active => status == GameStatus.playing;
  bool get finalized => status == GameStatus.won || status == GameStatus.lostFinal;
  bool get canSubmit => active && selection.length == 4;
  int get stars => mistakes == 0 ? 3 : mistakes <= 2 ? 2 : 1;
  bool selectable(String id) => active && order.contains(id);
  void select(String id) { if (selectable(id) && !selection.contains(id) && selection.length < 4) selection.add(id); }
  void toggle(String id) { if (!selectable(id)) return; if (!selection.remove(id)) select(id); }
  void drag(String from, [String? to]) { select(from); if (to != null) select(to); }
  void deselect() { if (active) selection.clear(); }
  void shuffle() {
    if (!active) return;
    for (var i = order.length - 1; i > 0; i--) {
      final j = random.next(i + 1), tmp = order[i]; order[i] = order[j]; order[j] = tmp;
    }
  }
  static String signature(Iterable<String> ids) => (ids.toList()..sort()).join('|');
  GuessResult submit() {
    if (!canSubmit) return const GuessResult(GuessKind.invalid);
    final key = signature(selection);
    if (wrongSets.contains(key)) return const GuessResult(GuessKind.alreadyGuessed);
    final counts = <String, int>{};
    for (final id in selection) { final c = level.tile(id).categoryId; counts[c] = (counts[c] ?? 0) + 1; }
    final correct = counts.length == 1;
    guesses.add(Guess(List.of(selection), selection.map((id) => level.tile(id).tier).toList(), correct));
    if (correct) {
      solved.add(counts.keys.single); order.removeWhere(selection.contains);
      selection.clear(); combo++;
      if (solved.length == 4) status = GameStatus.won;
      return const GuessResult(GuessKind.correct);
    }
    wrongSets.add(key); lives--; mistakes++; combo = 0;
    if (lives == 0) status = GameStatus.lostPendingDecision;
    return GuessResult(GuessKind.mismatch, isOneAway: counts.containsValue(3));
  }
  List<Category> get remaining => level.categories.where((c) => !solved.contains(c.id)).toList();
  bool canBoost(Booster b) => switch (b) {
    Booster.life => !finalized && lives < 4,
    Booster.pair => active && remaining.any((c) => !pairs.containsKey(c.id)),
    Booster.peek => active && remaining.any((c) => !peeks.contains(c.id)),
  };
  bool boost(Booster b) {
    if (!canBoost(b)) return false;
    switch (b) {
      case Booster.life: lives++; rescues++; status = GameStatus.playing;
      case Booster.peek: peeks.add(remaining.firstWhere((c) => !peeks.contains(c.id)).id);
      case Booster.pair:
        final preferred = selection.isEmpty ? null : level.tile(selection.last).categoryId;
        final c = preferred != null && !pairs.containsKey(preferred) ? level.category(preferred) : remaining.firstWhere((c) => !pairs.containsKey(c.id));
        final first = c.id == preferred ? selection.last : c.tiles.first.id;
        pairs[c.id] = [first, c.tiles.firstWhere((t) => t.id != first).id];
    }
    return true;
  }
  bool reveal() {
    if (status != GameStatus.lostPendingDecision) return false;
    status = GameStatus.lostFinal; return true;
  }
  List<RedHerring> get insights {
    final wrong = guesses.where((g) => !g.correct).expand((g) => g.ids).map((id) => level.tile(id).text).toSet();
    final notes = List.of(level.redHerrings);
    notes.sort((a,b) => (b.tiles.any(wrong.contains) ? 1 : 0).compareTo(a.tiles.any(wrong.contains) ? 1 : 0));
    return notes;
  }
  String share(String heading) {
    if (!finalized) return '';
    const squares = ['', '🟨', '🟩', '🟦', '🟪'];
    final rating = status == GameStatus.won ? '${'★' * stars}${'☆' * (3-stars)}' : '${solved.length}/4 groups';
    return 'LexiStack · $heading\n$rating · $mistakes mistakes${guesses.isEmpty ? '' : '\n'}${guesses.map((g) => g.tiers.map((t) => squares[t]).join()).join('\n')}';
  }
  Map<String, dynamic> toJson() => {
    'level': level.id, 'attempt': attemptId, 'date': date, 'random': random.state,
    'status': status.name, 'lives': lives, 'mistakes': mistakes, 'combo': combo,
    'rescues': rescues, 'order': order, 'selection': selection, 'solved': solved,
    'guesses': guesses.map((g) => g.toJson()).toList(), 'peeks': peeks.toList(), 'pairs': pairs,
  };
  static Game restore(Level level, Object? value) {
    final j = object(value, level.id);
    if (j['level'] != level.id) bad(level.id, 'attempt references another level');
    final g = Game(level, attemptId: string(j['attempt'], 'attempt'), seed: 1, date: j['date'] == null ? null : string(j['date'], 'date'));
    List<String> strings(Object? v) => array(v, 'attempt').map((e) => string(e, 'attempt')).toList();
    g.random.state = integer(j['random'], 'random', 1, 2147483646);
    g.lives = integer(j['lives'], 'lives', 0, 4);
    g.mistakes = integer(j['mistakes'], 'mistakes', 0, 1000000);
    g.rescues = integer(j['rescues'], 'rescues', 0, g.mistakes);
    g.combo = integer(j['combo'], 'combo', 0, 4);
    g.status = GameStatus.values.firstWhere((s) => s.name == j['status']);
    g.order..clear()..addAll(strings(j['order']));
    g.selection.addAll(strings(j['selection'])); g.solved.addAll(strings(j['solved'])); g.peeks.addAll(strings(j['peeks']));
    final known = level.tiles.map((t) => t.id).toSet(), cats = level.categories.map((c) => c.id).toSet();
    final historySolved = <String>[];
    var wrong = 0, combo = 0;
    for (final raw in array(j['guesses'], 'guesses')) {
      final r = object(raw, 'guess'); final ids = strings(r['ids']);
      if (ids.length != 4 || ids.toSet().length != 4 || !known.containsAll(ids) || ids.any((id) => historySolved.contains(level.tile(id).categoryId))) bad('guess', 'invalid tiles');
      final tiers = array(r['tiers'], 'tiers').map((t) => integer(t, 'tier', 1, 4)).toList();
      if (tiers.join() != ids.map((id) => level.tile(id).tier).join()) bad('guess', 'wrong tiers');
      final correct = ids.map((id) => level.tile(id).categoryId).toSet().length == 1;
      if (r['correct'] != correct) bad('guess', 'wrong correctness');
      if (correct) { historySolved.add(level.tile(ids.first).categoryId); combo++; }
      else { wrong++; combo = 0; if (!g.wrongSets.add(signature(ids))) bad('guess', 'duplicate wrong guess'); }
      g.guesses.add(Guess(ids, tiers, correct));
    }
    if (historySolved.join('|') != g.solved.join('|') || wrong != g.mistakes || combo != g.combo || g.lives != 4 + g.rescues - wrong) bad('attempt', 'inconsistent history');
    final expected = level.tiles.where((t) => !g.solved.contains(t.categoryId)).map((t) => t.id).toSet();
    if (g.order.toSet().length != g.order.length || g.order.length != expected.length || !expected.containsAll(g.order) || g.selection.length > 4 || g.selection.toSet().length != g.selection.length || !expected.containsAll(g.selection)) bad('attempt', 'invalid board or selection');
    if (!cats.containsAll(g.peeks)) bad('peeks', 'unknown category');
    for (final e in object(j['pairs'], 'pairs').entries) {
      final pair = strings(e.value);
      if (!cats.contains(e.key) || pair.length != 2 || pair.toSet().length != 2 || !known.containsAll(pair) || pair.any((id) => level.tile(id).categoryId != e.key)) bad('pairs', 'invalid pair');
      g.pairs[e.key] = pair;
    }
    if ((g.status == GameStatus.won) != (g.solved.length == 4) || (g.active && g.lives == 0) || ((g.status == GameStatus.lostFinal || g.status == GameStatus.lostPendingDecision) && g.lives != 0)) bad('attempt', 'invalid result state');
    return g;
  }
}
