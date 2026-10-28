import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/controller.dart';
import '../domain/content.dart';
import '../domain/game.dart';

const ink = Color(0xff252437), violet = Color(0xff5547a3);
const tierColors = [
  Color(0xfff4d777),
  Color(0xffb8d7b2),
  Color(0xffacc9ed),
  Color(0xffd1b9eb),
];
const packIcons = [
  Icons.local_cafe_outlined,
  Icons.auto_awesome_outlined,
  Icons.account_balance_outlined,
  Icons.theater_comedy_outlined,
];

enum AppPage { home, packs, board, stats, settings }

class LexiStackApp extends StatefulWidget {
  final AppController controller;
  const LexiStackApp({super.key, required this.controller});
  @override
  State<LexiStackApp> createState() => _LexiStackAppState();
}

class _LexiStackAppState extends State<LexiStackApp>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AppController get c => widget.controller;
  AppPage page = AppPage.home;
  Game? game;
  Pack? selectedPack;
  String feedback = 'Find four words with a shared connection.';
  late final AnimationController shake;
  Timer? dateTimer;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    c.addListener(_update);
    WidgetsBinding.instance.addObserver(this);
    shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    dateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDate(),
    );
  }

  void _update() {
    if (mounted) setState(() {});
  }

  void _checkDate() {
    final stale = game?.date != null && game!.date != c.today;
    c.refreshDate();
    if (stale && mounted) {
      game = null;
      _go(AppPage.home);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDate();
  }

  @override
  void dispose() {
    dateTimer?.cancel();
    shake.dispose();
    scroll.dispose();
    c.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _go(AppPage next) {
    setState(() => page = next);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void _open(Game? g) {
    if (g == null) {
      _go(AppPage.packs);
      return;
    }
    game = g;
    feedback = 'Find four words with a shared connection.';
    _go(AppPage.board);
  }

  Future<void> _haptic(String kind) async {
    if (!c.haptics) return;
    try {
      switch (kind) {
        case 'solve':
          await HapticFeedback.mediumImpact();
        case 'wrong':
          await HapticFeedback.heavyImpact();
        case 'boost':
          await HapticFeedback.lightImpact();
        default:
          await HapticFeedback.selectionClick();
      }
    } catch (_) {
      /* Unsupported platform: gameplay remains available. */
    }
  }

  void _submit(BuildContext context) {
    final r = c.submit(game!);
    setState(
      () => feedback = switch (r.kind) {
        GuessKind.correct =>
          game!.combo > 1
              ? '${game!.combo} in a row. Beautifully connected!'
              : 'Connection found!',
        GuessKind.alreadyGuessed => 'Already guessed! Try a different set.',
        GuessKind.mismatch =>
          r.isOneAway
              ? 'One Away! Swap one tile.'
              : 'Not quite. Try a new connection.',
        GuessKind.invalid => 'Select exactly four tiles.',
      },
    );
    if (r.kind == GuessKind.mismatch) {
      if (!MediaQuery.disableAnimationsOf(context)) shake.forward(from: 0);
      _haptic('wrong');
    }
    if (r.kind == GuessKind.correct) _haptic('solve');
    if (game!.finalized && scroll.hasClients) scroll.jumpTo(0);
  }

  void _boost(Booster b) {
    if (c.buy(game!, b)) {
      _haptic('boost');
      setState(
        () => feedback = switch (b) {
          Booster.pair => 'Linked tiles share a connection.',
          Booster.peek => 'A connection title has been uncovered.',
          Booster.life => 'One heart restored. Keep connecting!',
        },
      );
    }
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: violet,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xffc7baff) : violet,
          surface: dark ? const Color(0xff242334) : const Color(0xfffffdf8),
          onSurface: dark ? const Color(0xfff4f0fa) : ink,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: dark
          ? const Color(0xff191824)
          : const Color(0xfff6f3eb),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'LexiStack',
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: switch (c.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    builder: (context, child) => ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff100f1a)
          : const Color(0xffe5e0ec),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ClipRect(child: child!),
        ),
      ),
    ),
    home: Builder(
      builder: (context) => PopScope(
        canPop: page == AppPage.home,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _go(AppPage.home);
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _header(context),
                if (c.notice != null)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.notice!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Retry saving',
                            onPressed: c.save,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: switch (page) {
                      AppPage.home => _home(context),
                      AppPage.packs => _packs(context),
                      AppPage.board => _board(context),
                      AppPage.stats => _stats(context),
                      AppPage.settings => _settings(context),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        if (page != AppPage.home)
          IconButton(
            key: const Key('back'),
            tooltip: 'Back to home',
            onPressed: () => _go(AppPage.home),
            icon: const Icon(Icons.arrow_back_rounded),
          )
        else
          Padding(padding: const EdgeInsets.all(8), child: _mark()),
        Expanded(
          child: Text(
            page == AppPage.home
                ? 'lexistack'
                : switch (page) {
                    AppPage.packs => 'The collections',
                    AppPage.stats => 'Your discoveries',
                    AppPage.settings => 'Make it yours',
                    _ => 'lexistack',
                  },
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xfff4d777),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Semantics(
            label: '${c.coins} coins',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toll_rounded, size: 18, color: ink),
                const SizedBox(width: 5),
                Text(
                  '${c.coins}',
                  key: const Key('coins'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (page == AppPage.home)
          IconButton(
            key: const Key('settings'),
            tooltip: 'Settings',
            onPressed: () => _go(AppPage.settings),
            icon: const Icon(Icons.tune_rounded),
          ),
      ],
    ),
  );
  Widget _mark() => SizedBox(
    width: 30,
    height: 30,
    child: Wrap(
      spacing: 3,
      runSpacing: 3,
      children: List.generate(
        4,
        (i) => Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: tierColors[i],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
  Widget _eyebrow(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.7,
      ),
    ),
  );
  Widget _title(String text, {double size = 30}) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.8,
      height: 1.12,
    ),
  );
  Widget _card(BuildContext context, {required Widget child, Color? color}) =>
      SizedBox(
        width: double.infinity,
        child: Material(
          color: color ?? Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.14),
            ),
          ),
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      );
  Widget _home(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      _eyebrow('Sixteen words. Four discoveries.'),
      _title('A little curiosity.\nA great connection.'),
      const SizedBox(height: 12),
      const Text(
        'Find the unexpected things words have in common.',
        style: TextStyle(fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 22),
      _card(
        context,
        color: violet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.layers_outlined, color: Color(0xfff4d777)),
                SizedBox(width: 8),
                Text(
                  'THE CAMPAIGN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Make yourself\na connection.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${c.bestStars.length} of 32 stages discovered',
              style: const TextStyle(color: Color(0xffe5defa), fontSize: 13),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('continue'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xfff4d777),
                  foregroundColor: ink,
                ),
                onPressed: () => _open(c.continueCampaign()),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue Campaign'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (c.catalog.daily.levels.isNotEmpty)
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wb_sunny_outlined, color: Color(0xff977126)),
                  const SizedBox(width: 10),
                  Expanded(child: _title('The Daily Stack', size: 21)),
                  Text(
                    '${c.currentDailyStreak} day streak',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${c.today} · ${c.dailyResult == null
                    ? c.daily == null
                          ? 'A fresh perspective awaits.'
                          : 'Your puzzle is waiting.'
                    : c.dailyResult!.won
                    ? 'Connected. Nicely done!'
                    : 'Today’s discoveries are ready.'}',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('daily'),
                  onPressed: () {
                    final g = c.openDaily();
                    if (g == null) {
                      game = null;
                      _go(AppPage.board);
                    } else {
                      _open(g);
                    }
                  },
                  child: Text(
                    c.dailyResult != null
                        ? 'View daily result'
                        : c.daily != null
                        ? 'Resume Daily'
                        : 'Play Daily',
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(child: _metric('${c.wins}', 'wins')),
          Expanded(child: _metric('${c.perfectWins}', 'perfect')),
          Expanded(
            child: TextButton(
              onPressed: () => _go(AppPage.stats),
              child: const Text('All stats'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _title('Pick your curiosity', size: 21)),
          TextButton(
            key: const Key('all-packs'),
            onPressed: () {
              selectedPack = null;
              _go(AppPage.packs);
            },
            child: const Text('View all'),
          ),
        ],
      ),
      for (var i = 0; i < c.catalog.campaign.length; i++)
        _packRow(context, c.catalog.campaign[i], i),
      const SizedBox(height: 16),
      const Center(
        child: Text(
          'OFFLINE BY DESIGN · CURIOUS BY NATURE',
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );
  Widget _metric(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
  Widget _packRow(BuildContext context, Pack p, int i) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          selectedPack = p;
          _go(AppPage.packs);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tierColors[i % 4],
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(packIcons[i % 4], color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.levels.where((l) => c.bestStars.containsKey(l.id)).length} / ${p.levels.length} discovered',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _packs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      _eyebrow('Four ways to wonder'),
      _title(selectedPack?.title ?? 'Find your next\nlittle obsession.'),
      const SizedBox(height: 12),
      if (selectedPack == null) ...[
        const Text(
          'Each collection starts unlocked. Solve a stage to discover the next.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < c.catalog.campaign.length; i++)
          _packRow(context, c.catalog.campaign[i], i),
      ] else ...[
        Text(selectedPack!.description, style: const TextStyle(height: 1.5)),
        TextButton(
          onPressed: () => setState(() => selectedPack = null),
          child: const Text('All collections'),
        ),
        for (var i = 0; i < selectedPack!.levels.length; i++)
          _levelRow(context, selectedPack!.levels[i], i),
      ],
    ],
  );
  Widget _levelRow(BuildContext context, Level l, int i) {
    final open = c.unlocked(l),
        stars = c.bestStars[l.id] ?? 0,
        old = c.campaigns[l.id];
    final replay = old?.finalized == true || (old == null && stars > 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        context,
        child: Row(
          children: [
            Text(
              '${i + 1}'.padLeft(2, '0'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (stars > 0)
                    _stars(stars, size: 15)
                  else
                    Text(
                      open ? 'Ready to discover' : 'Solve stage $i first',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            if (open)
              TextButton(
                key: Key('level-${l.id}'),
                onPressed: () => _open(c.openCampaign(l, replay: replay)),
                child: Text(
                  replay
                      ? 'Replay'
                      : old != null
                      ? 'Resume'
                      : 'Play',
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.lock_outline, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _board(BuildContext context) {
    final g = game;
    if (g == null) {
      final r = c.dailyResult;
      return Column(
        children: [
          _title('Daily result'),
          const SizedBox(height: 20),
          Text(
            r == null
                ? 'Come back for a new Daily.'
                : '${r.heading}\n${r.won ? 'Completed' : 'Revealed'} · ${r.mistakes} mistakes',
          ),
          if (r != null) _share(context, r.share),
        ],
      );
    }
    if (g.finalized) return _result(context, g);
    if (g.status == GameStatus.lostPendingDecision) return _pending(context, g);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(
          g.date != null
              ? 'Daily · ${g.date}'
              : '${c.catalog.pack(g.level.packId).title} · ${c.catalog.pack(g.level.packId).levels.indexOf(g.level) + 1} / 8',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _title(g.level.title, size: 25)),
            Semantics(
              label: '${g.lives} of 4 hearts',
              excludeSemantics: true,
              child: Row(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      i < g.lives
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: Duration(milliseconds: reduce ? 0 : 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final id in g.solved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _category(g.level.category(id)),
                ),
              if (g.remaining.isNotEmpty)
                Row(
                  children: [
                    for (final cat in g.remaining)
                      Expanded(
                        child: Container(
                          key: Key('slot-${cat.id}'),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(
                            vertical: 9,
                            horizontal: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tierColors[cat.tier - 1].withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            g.peeks.contains(cat.id)
                                ? cat.title
                                : 'GROUP ${cat.tier}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: g.peeks.contains(cat.id) ? 10 : 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: shake,
          builder: (context, child) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: g.order.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
              mainAxisExtent: 62,
            ),
            itemBuilder: (context, i) {
              final id = g.order[i];
              return Transform.translate(
                offset: Offset(
                  g.selection.contains(id)
                      ? math.sin(shake.value * math.pi * 6) *
                            5 *
                            (1 - shake.value)
                      : 0,
                  0,
                ),
                child: _tile(context, g, id),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        DragTarget<String>(
          onAcceptWithDetails: (d) {
            c.drag(g, d.data);
            _haptic('select');
          },
          builder: (context, accepted, rejected) => Container(
            key: const Key('selection-tray'),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(
                alpha: accepted.isEmpty ? 0.07 : 0.2,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.selection.isEmpty
                        ? 'Tap tiles, or hold & drag to connect.'
                        : g.selection
                              .map((id) => g.level.tile(id).text)
                              .join(' · '),
                    style: const TextStyle(fontSize: 11, height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${g.selection.length}/4',
                  key: const Key('selection-count'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Semantics(
            liveRegion: true,
            child: Text(
              feedback,
              key: const Key('feedback'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ),
        Row(
          children: [
            IconButton.filledTonal(
              key: const Key('shuffle'),
              tooltip: 'Shuffle tiles, free',
              onPressed: () => c.shuffle(g),
              icon: const Icon(Icons.shuffle_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                key: const Key('deselect'),
                onPressed: g.selection.isEmpty ? null : () => c.deselect(g),
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('submit'),
                onPressed: g.canSubmit ? () => _submit(context) : null,
                child: const Text('Submit group'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _eyebrow('A little nudge'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in Booster.values)
              Expanded(child: _booster(context, g, b)),
          ],
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Game g, String id) {
    final t = g.level.tile(id), selected = g.selection.contains(id);
    final pair = g.pairs.entries.where((e) => e.value.contains(id)).firstOrNull;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surface;
    final fg = selected
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    Widget face({bool dragging = false}) => Material(
      color: color,
      borderRadius: BorderRadius.circular(13),
      elevation: selected ? 2 : 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: pair != null
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.22),
            width: pair != null ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final word in t.text.split(' '))
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        word,
                        style: TextStyle(
                          color: fg,
                          fontFamily: 'Tile',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (pair != null)
              Positioned(
                top: 2,
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, size: 11, color: fg),
                    Text(
                      '${g.level.category(pair.key).tier}',
                      style: TextStyle(
                        color: fg,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      key: Key('tile-$id'),
      label:
          '${t.text}${pair != null ? ', linked pair ${g.level.category(pair.key).tier}' : ''}',
      button: true,
      selected: selected,
      onTap: () {
        c.toggle(g, id);
        _haptic('select');
      },
      excludeSemantics: true,
      child: DragTarget<String>(
        onAcceptWithDetails: (d) {
          c.drag(g, d.data, id);
          _haptic('select');
        },
        builder: (context, accepted, rejected) => LongPressDraggable<String>(
          data: id,
          hapticFeedbackOnStart: c.haptics,
          delay: const Duration(milliseconds: 180),
          feedback: Material(
            type: MaterialType.transparency,
            child: SizedBox(width: 80, height: 62, child: face(dragging: true)),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: face()),
          child: AnimatedScale(
            scale: selected ? 0.96 : 1,
            duration: Duration(
              milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 120,
            ),
            child: InkWell(
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(13),
              onTap: () {
                c.toggle(g, id);
                _haptic('select');
              },
              child: face(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _category(Category cat) => Container(
    key: Key('solved-${cat.id}'),
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: tierColors[cat.tier - 1],
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${cat.tier}  ·  ${cat.title}',
          style: const TextStyle(
            color: ink,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          cat.tiles.map((t) => t.text).join(' · '),
          style: const TextStyle(
            color: ink,
            fontFamily: 'Tile',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          cat.fact,
          style: const TextStyle(color: ink, fontSize: 12, height: 1.35),
        ),
      ],
    ),
  );
  Widget _booster(BuildContext context, Game g, Booster b) {
    final allowed = g.canBoost(b), affordable = c.coins >= b.price;
    final title = switch (b) {
      Booster.pair => 'Pair Magnet',
      Booster.peek => 'Category Peek',
      Booster.life => 'Extra Life',
    };
    final reason = !allowed
        ? (b == Booster.life ? 'Hearts are full' : 'No eligible group')
        : !affordable
        ? 'Need ${b.price} coins'
        : 'Costs ${b.price} coins';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: '$title. $reason',
        excludeFromSemantics: true,
        child: Semantics(
          label: '$title. $reason',
          excludeSemantics: true,
          button: true,
          enabled: allowed && affordable,
          onTap: allowed && affordable ? () => _boost(b) : null,
          child: OutlinedButton(
            key: Key('boost-${b.name}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            onPressed: allowed && affordable ? () => _boost(b) : null,
            child: Column(
              children: [
                Icon(switch (b) {
                  Booster.pair => Icons.link_rounded,
                  Booster.peek => Icons.visibility_outlined,
                  Booster.life => Icons.favorite_border_rounded,
                }, size: 23),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${b.price} coins', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pending(BuildContext context, Game g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 35),
      _eyebrow('Take a breath'),
      _title('One more\nconnection?'),
      const SizedBox(height: 20),
      const Icon(Icons.favorite_border_rounded, size: 58, color: violet),
      const SizedBox(height: 20),
      Text(
        'You found ${g.solved.length} of 4 groups. Your answers are still hidden. Add a heart to keep this attempt going, or reveal the connections.',
        style: const TextStyle(fontSize: 16, height: 1.6),
      ),
      const SizedBox(height: 25),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('rescue'),
          onPressed: c.coins >= 60 ? () => _boost(Booster.life) : null,
          child: const Text('Extra Life · 60 coins'),
        ),
      ),
      if (c.coins < 60)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('You need 60 coins to add a heart.'),
        ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          key: const Key('reveal'),
          onPressed: () {
            c.reveal(g);
            if (scroll.hasClients) scroll.jumpTo(0);
          },
          child: const Text('Reveal / Accept Loss'),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Leaving this screen saves your decision for later.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
    ],
  );
  Widget _result(BuildContext context, Game g) {
    final r = c.result(g)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(
          g.date != null
              ? 'The Daily Stack · ${g.date}'
              : '${c.catalog.pack(g.level.packId).title} · complete',
        ),
        Row(
          children: [
            Expanded(
              child: _title(
                r.won ? 'Beautifully\nconnected.' : 'A new perspective.',
                size: 30,
              ),
            ),
            if (r.won)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stars(r.stars),
                  Text(
                    '+${r.reward} coins',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${g.solved.length}/4 connections · ${g.mistakes} mistakes',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        for (final cat in g.level.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _category(cat),
          ),
        const SizedBox(height: 8),
        _eyebrow('The clever misdirection'),
        for (final note in g.insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              note.note,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        _share(context, r.share),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('next'),
            onPressed: () {
              if (g.date != null || !r.won) {
                _go(AppPage.home);
              } else {
                final p = c.catalog.pack(g.level.packId),
                    i = c.catalog.pack(g.level.packId).levels.indexOf(g.level);
                if (i + 1 < p.levels.length) {
                  _open(c.openCampaign(p.levels[i + 1]));
                } else {
                  selectedPack = null;
                  _go(AppPage.packs);
                }
              }
            },
            child: Text(
              g.date == null && r.won ? 'Next discovery' : 'Back to home',
            ),
          ),
        ),
      ],
    );
  }

  Widget _stars(int stars, {double size = 25}) => Semantics(
    label: '$stars of 3 stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: const Color(0xff9b6d15),
        ),
      ),
    ),
  );

  Widget _share(BuildContext context, String text) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: const Key('share'),
      onPressed: () async {
        try {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Spoiler-free result copied.')),
            );
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Clipboard unavailable on this device.'),
              ),
            );
          }
        }
      },
      icon: const Icon(Icons.copy_rounded, size: 19),
      label: const Text('Copy spoiler-free result'),
    ),
  );
  Widget _stats(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      _eyebrow('Every connection counts'),
      _title('Your curious mind,\nin numbers.'),
      const SizedBox(height: 25),
      _card(
        context,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _metric('${c.history.length}', 'games played')),
                Expanded(
                  child: _metric(
                    c.history.isEmpty
                        ? '0%'
                        : '${(100 * c.wins / c.history.length).round()}%',
                    'win rate',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: _metric('${c.perfectWins}', 'zero-mistake wins'),
                ),
                Expanded(child: _metric('${c.wins}', 'total wins')),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _title('Mistakes in your wins', size: 20),
      const SizedBox(height: 14),
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(width: 30, child: Text(i == 4 ? '4+' : '$i')),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: LinearProgressIndicator(
                    value: c.wins == 0 ? 0 : c.distribution[i] / c.wins,
                    minHeight: 20,
                    color: violet,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${c.distribution[i]}'),
            ],
          ),
        ),
      const SizedBox(height: 16),
      _card(
        context,
        child: Row(
          children: [
            Expanded(
              child: _metric('${c.currentDailyStreak}', 'current daily streak'),
            ),
            Expanded(
              child: _metric('${c.bestDailyStreak}', 'best daily streak'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Only completed attempts count. A pending decision can still become a win.',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
    ],
  );
  Widget _settings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      _eyebrow('Your quiet corner'),
      _title('A game that\nfeels like you.'),
      const SizedBox(height: 24),
      _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in ['system', 'light', 'dark'])
                  ChoiceChip(
                    label: Text('${t[0].toUpperCase()}${t.substring(1)}'),
                    selected: c.theme == t,
                    onSelected: (_) => c.settings(theme: t),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Haptic feedback',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'A little tap for every discovery',
                style: TextStyle(fontSize: 12),
              ),
              value: c.haptics,
              onChanged: (v) => c.settings(haptics: v),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _card(
        context,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Made for offline moments',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              '32 campaign stages and 8 Daily puzzles, bundled on your device. The Daily pool repeats every eight days. Progress stays in this browser or installation.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            SizedBox(height: 10),
            Text(
              'Tap four tiles and submit. A wrong group costs a heart; “One Away!” means three belong together. Hold a tile to drag it onto another tile or the selection tray.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 25),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          key: const Key('reset'),
          onPressed: () async {
            final reset = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Start fresh?'),
                content: const Text(
                  'This removes all progress, results and settings on this device, and restores 150 coins.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Keep my progress'),
                  ),
                  FilledButton(
                    key: const Key('confirm-reset'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Reset everything'),
                  ),
                ],
              ),
            );
            if (reset == true) {
              await c.reset();
              game = null;
              selectedPack = null;
              _go(AppPage.home);
            }
          },
          child: const Text('Reset Progress to Default'),
        ),
      ),
      const SizedBox(height: 16),
      const Center(
        child: Text(
          'LEXISTACK · 1.0',
          style: TextStyle(fontSize: 10, letterSpacing: 2),
        ),
      ),
    ],
  );
}
