# LexiStack

A fully offline Flutter word-and-trivia game for Android, with a responsive web build. Find four groups of four tiles before using four hearts. A guess with three matching tiles gets **One Away!**; repeating a wrong set costs nothing. Hold a tile to drag it onto another tile or the selection tray.

Four independently unlocked collections contain **32 campaign stages**. A separate **eight-board Daily pool repeats every eight days**, selected by your local calendar date. Win all four connections to reveal their facts and the board's deliberate misdirection.

## Play and rewards

- Start with 150 coins. Pair Magnet costs 30, Category Peek 40, and Extra Life 60.
- Zero mistakes earns three stars; one or two earns two; three or more earns one. Restoring hearts never removes mistakes.
- First campaign wins pay 50/30/15 coins. Only the first replay win of each stage pays five practice coins.
- A Daily win pays its star reward plus 25, once per date. Final Daily losses cannot be replayed that day.
- At zero hearts, answers remain hidden until you explicitly accept the loss. You can leave and resume this decision, or buy a heart.
- Results copy a spoiler-free emoji grid to the clipboard. There is no audio, advertising, account, billing or runtime network service.

## Windows development

Install Flutter stable with Dart 3.10 or newer, Android Studio's SDK and an accepted Android license set. This project was verified using Flutter 3.47.8 and Dart 3.13.7. Visual Studio's **Desktop development with C++** workload is needed only for a Windows native build.

```powershell
flutter doctor -v
flutter pub get
flutter run -d emulator-5554
# Or use the installed Chrome browser:
flutter run -d chrome

dart run tool/validate_levels.dart
dart analyze
flutter test
flutter build web
flutter build apk --debug

# With a running Android emulator (resets this app's emulator progress):
flutter test integration_test/smoke_test.dart -d emulator-5554

# Only with the Visual Studio C++ toolchain:
flutter build windows
```

The APK is `build/app/outputs/flutter-apk/app-debug.apk`. It is a debug-signed development build, not a store release. Serve `build/web` from an HTTP server; service workers require HTTPS or localhost. All renderer resources are bundled locally by `web/flutter_bootstrap.js`. `web/offline.js` caches the app, puzzles, fonts and CanvasKit for repeat visits; clearing site data, private browsing or browser eviction can remove that cache. Bump its cache version when publishing changed assets. Nothing is published by a build command.

## Code and recovery

- `lib/domain/`: Flutter-free content/schema validation, rules, and civil-date functions. Fisher–Yates shuffling uses Park–Miller with multiplier 48271 and modulus 2147483647; all products remain exact below JavaScript's 53-bit integer limit.
- `lib/app/controller.dart`: a `ChangeNotifier`, an injectable clock, and a small storage interface. `shared_preferences` is the only runtime package beyond Flutter; tests use deterministic memory storage.
- `lib/ui/app.dart`: native Flutter screens, touch drag targets, reduced-motion support, optional haptics, and a centered 460-pixel desktop frame. Roboto and Roboto Condensed are bundled with their Apache license in `assets/fonts/`.
- One versioned JSON document holds the balance, settings, best stars, capped practice rewards, historical result summaries and attempts. Writes queue in order; failed writes show a retry notice. Invalid individual sessions are discarded independently, and historical summaries survive removed content. An unreadable root or unsupported version restores defaults with a notice.
- Daily selection uses UTC calendar arithmetic on the local date, so DST cannot shift its index. Old unfinished daily boards expire without entering statistics. Final results settle only once.

Progress is local to the browser profile or app installation. Clearing storage or uninstalling can remove it. Settings provides a confirmed reset to exactly 150 coins and empty progress.

## Content and candidate packs

Production assets are `assets/levels/manifest.json`, four campaign JSON files and `daily.json`, each containing eight complete levels. Use an existing pack as the schema example. Preserve stable IDs when editing existing content. New packs need a unique pack ID, globally unique level IDs and category titles, one category of each tier per board, four uppercase tiles per category, a factual 40–160 character sentence per group, and a plausible red-herring note referring to real board tiles.

AI-generated content is a candidate, not automatically production-ready. Check each group literally fits, challenge alternative partitions, verify facts, and replace weak or ambiguous clues. Titles are unique across the catalog; a tile may occur in at most two different levels; groups cannot share three tiles. Tiles have one or two words, each no longer than ten letters.

```powershell
# During construction: checks every listed file without requiring the final catalog.
dart run tool/validate_levels.dart --partial

# Validate a candidate without changing production assets:
dart run tool/validate_levels.dart C:\puzzles\candidate.json

# Require four or more campaign packs and a separate Daily pool:
dart run tool/validate_levels.dart
```

A candidate with an existing pack ID is checked as a replacement; a new ID is checked as an addition against the installed catalog. Missing referenced files always fail. Future packs may contain eight or more levels; the initial release is constrained by tests to exactly five files and forty levels. Advisory warnings flag facts that mention unrelated board tiles. Structural checks cannot prove semantic uniqueness: this catalog received an editorial self-audit, not an independent playtest. Difficulty is editorial and has not been calibrated with players. Selected fact checks used primary sources such as [NASA's Titan facts](https://science.nasa.gov/saturn/moons/titan/facts/) and [English Heritage's Stonehenge sources](https://www.english-heritage.org.uk/visit/places/stonehenge/history-and-stories/history/sources/).

## Verification artifacts

`flutter test` includes domain, validator, controller, recovery and actual-app workflows with a fixed clock. It tests 360×640 and 390×844 mobile layouts, 1.3× text scaling, dark mode and a 1280×800 desktop frame. The Android integration test exercises native touch/drag, hints, SharedPreferences reload and the actual clipboard.

`flutter test test/screenshots_test.dart` explicitly loads the bundled fonts, captures six real widget states into `docs/screenshots/`, and renders the app's four-tile launcher mark. Screenshots include home, four selected tiles, two solved groups, a victory result, stage selection, and desktop framing. They are source-controlled; builds, APKs, local browser artifacts and tool caches are ignored.

Verified on Windows on 2026-10-28:

| Check | Actual outcome |
| --- | --- |
| `flutter pub get` | Exit 0 |
| Strict validator | Exit 0; 5 files, 40 levels, 160 groups, 640 tile positions; zero errors and warnings |
| `dart analyze` | Exit 0; no issues |
| `flutter test` | Exit 0; 73 passing tests, including screenshot capture |
| `flutter build web` | Exit 0 |
| `flutter build apk --debug` | Exit 0 |
| Android integration | Exit 0; one passing smoke test on Pixel 10 / Android 16 emulator |
| Android offline process restart | Coin balance, selection and paid pair retained with Wi-Fi and mobile data disabled |
| Chrome web smoke | No external resource requests; offline reload retained board order and selection; no console errors |
| PRNG comparison | Dart VM and compiled JavaScript produced identical initial board and three subsequent shuffles |
| Screenshots | All six captured and visually inspected; all production tile words remain at least 11 pixels at 360-pixel width |
| Windows native build | Not run: Visual Studio C++ toolchain is absent |

Build tools emit a nonfatal unused-Cupertino-font tree-shaker advisory and Java 25 native-access warnings; the app uses Material icons and both builds succeed. No physical Android device or independent editorial playtest was used.
