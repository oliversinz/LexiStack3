import 'dart:convert';
import 'dart:io';
import 'package:lexistack/domain/content.dart';

void main(List<String> args) {
  try {
    final partial = args.contains('--partial');
    final candidates = args.where((s) => s != '--partial').toList();
    if (candidates.length > 1) {
      bad('arguments', 'use --partial or one candidate JSON path');
    }
    final manifest = object(
      jsonDecode(File('assets/levels/manifest.json').readAsStringSync()),
      'manifest',
    );
    final campaign = array(
      manifest['campaign'],
      'manifest/campaign',
    ).map((s) => string(s, 'manifest/campaign')).toList();
    final daily = manifest['daily'] == null
        ? null
        : string(manifest['daily'], 'manifest/daily');
    final names = [...campaign, ?daily];
    if (names.toSet().length != names.length) {
      bad('manifest', 'duplicate file entries');
    }
    final files = <String, String>{};
    for (final name in names) {
      if (!RegExp(r'^[a-zA-Z0-9_-]+\.json$').hasMatch(name)) {
        bad('manifest', 'invalid file name $name');
      }
      final f = File('assets/levels/$name');
      if (!f.existsSync()) bad(name, 'referenced file is missing');
      files[name] = f.readAsStringSync();
    }
    if (candidates.isNotEmpty) {
      final path = candidates.single;
      final source = File(path).readAsStringSync();
      final candidate = Pack.parse(source, path);
      String? replacement;
      for (final e in files.entries) {
        if (Pack.parse(e.value, e.key).id == candidate.id) replacement = e.key;
      }
      stdout.writeln(
        'Candidate ${replacement == null ? 'addition' : 'replacement of $replacement'}: ${candidate.id} (no files modified)',
      );
      files[replacement ?? path] = source;
    }
    final result = validateCatalog(
      files,
      partial: partial || candidates.isNotEmpty,
      dailyFile: daily,
    );
    for (final e in result.errors) {
      stderr.writeln('ERROR $e');
    }
    for (final w in result.warnings) {
      stdout.writeln('WARNING $w');
    }
    for (final p in result.packs) {
      stdout.writeln('${p.id}: ${p.title} — ${p.levels.length} levels');
    }
    stdout.writeln(
      '${partial
          ? 'PARTIAL (not a final catalog)'
          : candidates.isNotEmpty
          ? 'CANDIDATE'
          : 'FINAL'}: ${result.packs.length} files, ${result.levelCount} levels, ${result.levelCount * 4} groups, ${result.levelCount * 16} tiles; ${result.errors.length} errors, ${result.warnings.length} warnings',
    );
    if (!result.ok) exitCode = 1;
  } catch (e) {
    stderr.writeln('ERROR $e');
    exitCode = 1;
  }
}
