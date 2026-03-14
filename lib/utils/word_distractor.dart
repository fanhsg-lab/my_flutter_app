import 'dart:math' as math;

/// Generates phonetically plausible misspellings of a word.
/// Each of the 3 distractors uses a DIFFERENT category of mutation so the
/// user cannot reverse-engineer the correct answer by spotting a shared pattern.
class WordDistractorGenerator {
  WordDistractorGenerator._();

  static final _rng = math.Random();

  // ────────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────────

  /// Returns [count] misspelled variants of [word] for the given [language].
  /// Each variant uses a structurally different kind of error.
  static List<String> generate(String word, String language, {int count = 3}) {
    if (word.trim().isEmpty) return List.filled(count, '${word}x');

    // Multi-word phrase → mutate the longest word, rebuild phrase
    if (word.contains(' ')) {
      final words = word.split(' ');
      final target = words.reduce((a, b) => a.length >= b.length ? a : b);
      final variants = generate(target, language, count: count);
      return variants.map((v) => word.replaceFirst(target, v)).toList();
    }

    final rules = language == 'es' ? _esRules : _enRules;

    // Collect rules that actually change the word, grouped by category
    final byCategory = <String, List<_Rule>>{};
    for (final rule in rules) {
      try {
        final result = rule.apply(word);
        if (result != word && result.isNotEmpty) {
          byCategory.putIfAbsent(rule.category, () => []).add(rule);
        }
      } catch (_) {}
    }

    // Shuffle category order so we get variety across different words
    final cats = byCategory.keys.toList()..shuffle(_rng);
    final results = <String>[];

    // Pick ONE rule from each DIFFERENT category
    for (final cat in cats) {
      if (results.length >= count) break;
      final catRules = List.of(byCategory[cat]!)..shuffle(_rng);
      for (final rule in catRules) {
        final s = rule.apply(word);
        if (s != word && !results.contains(s)) {
          results.add(s);
          break;
        }
      }
    }

    // If same-category rules can fill remaining slots, use them
    if (results.length < count) {
      final all = byCategory.values.expand((r) => r).toList()..shuffle(_rng);
      for (final rule in all) {
        if (results.length >= count) break;
        final s = rule.apply(word);
        if (s != word && !results.contains(s)) results.add(s);
      }
    }

    // Vowel-substitution fallback
    int vi = 0;
    while (results.length < count && vi < 30) {
      final s = _vowelVariant(word, vi++);
      if (s != word && !results.contains(s)) results.add(s);
    }

    // Absolute last resort
    while (results.length < count) {
      results.add(word + word[word.length - 1]);
    }

    return results;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  static String _vowelVariant(String word, int index) {
    const subs = {'a': 'e', 'e': 'i', 'i': 'o', 'o': 'u', 'u': 'a'};
    int vi = 0;
    for (int i = 0; i < word.length; i++) {
      final c = word[i].toLowerCase();
      if (subs.containsKey(c)) {
        if (vi == index % 5) {
          return word.substring(0, i) + subs[c]! + word.substring(i + 1);
        }
        vi++;
      }
    }
    return word.length > 1 ? word.substring(0, word.length - 1) : '${word}x';
  }

  /// Replace first occurrence of [from] (case-insensitive) with [to].
  static String _rep(String word, String from, String to) {
    final idx = word.toLowerCase().indexOf(from.toLowerCase());
    if (idx == -1) return word;
    return word.substring(0, idx) + to + word.substring(idx + from.length);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Spanish Rules
  // ────────────────────────────────────────────────────────────────────────────
  static final List<_Rule> _esRules = [
    // ── b / v confusion ──────────────────────────────────────────────────────
    _Rule('bv', (w) => _rep(w, 'b', 'v')),
    _Rule('bv', (w) => _rep(w, 'v', 'b')),

    // ── z / s / c confusion ──────────────────────────────────────────────────
    _Rule('zs', (w) => _rep(w, 'z', 's')),
    _Rule('zs', (w) => _rep(w, 'z', 'c')),
    _Rule('zs', (w) {
      final t = _rep(w, 'ce', 'se');
      return t != w ? t : _rep(w, 'ci', 'si');
    }),
    _Rule('zs', (w) => _rep(w, 's', 'z')),

    // ── ll / y confusion ─────────────────────────────────────────────────────
    _Rule('lly', (w) => _rep(w, 'll', 'y')),
    _Rule('lly', (w) => _rep(w, 'y', 'll')),

    // ── silent h (add or remove) ─────────────────────────────────────────────
    // Only add 'h' when word starts with a vowel (realistic Spanish error)
    _Rule('h', (w) {
      const vowels = 'aeiouáéíóú';
      if (w.isEmpty || !vowels.contains(w[0].toLowerCase())) return w;
      return 'h${w[0].toLowerCase()}${w.substring(1)}';
    }),
    // Remove leading 'h'
    _Rule('h', (w) => w.isNotEmpty && w[0].toLowerCase() == 'h' ? w.substring(1) : w),

    // ── nasal consonant confusion (mp/mb ↔ np/nb) ────────────────────────────
    _Rule('nasal', (w) => _rep(w, 'mp', 'np')),
    _Rule('nasal', (w) => _rep(w, 'mb', 'nb')),
    _Rule('nasal', (w) => _rep(w, 'np', 'mp')),
    _Rule('nasal', (w) => _rep(w, 'nb', 'mb')),
    // Isolated n/m swap (only if no compound rule fired)
    _Rule('nasal', (w) {
      // skip trivial single-char words
      if (w.length < 4) return w;
      return _rep(w, 'n', 'm');
    }),
    _Rule('nasal', (w) {
      if (w.length < 4) return w;
      return _rep(w, 'm', 'n');
    }),

    // ── g / j confusion (before e, i) ────────────────────────────────────────
    _Rule('gj', (w) {
      final t = _rep(w, 'ge', 'je');
      return t != w ? t : _rep(w, 'gi', 'ji');
    }),
    _Rule('gj', (w) {
      final t = _rep(w, 'je', 'ge');
      return t != w ? t : _rep(w, 'ji', 'gi');
    }),
    _Rule('gj', (w) => _rep(w, 'x', 'j')),  // México → Méjico
    _Rule('gj', (w) => _rep(w, 'j', 'x')),

    // ── r / rr confusion ─────────────────────────────────────────────────────
    _Rule('rr', (w) => _rep(w, 'rr', 'r')),
    _Rule('rr', (w) {
      // Insert an extra 'r' after a vowel-r sequence (pero → perro)
      final re = RegExp(r'(?<=[aeiouáéíóúü])r(?=[aeiouáéíóúü])');
      final m = re.firstMatch(w);
      if (m == null) return w;
      return '${w.substring(0, m.start)}rr${w.substring(m.end)}';
    }),

    // ── qu / c / k confusion ─────────────────────────────────────────────────
    _Rule('qu', (w) => _rep(w, 'qu', 'cu')),
    _Rule('qu', (w) => _rep(w, 'qu', 'k')),
    _Rule('qu', (w) => _rep(w, 'c', 'qu')),

    // ── vowel substitution (last resort) ─────────────────────────────────────
    _Rule('vowel', (w) => _rep(w, 'e', 'i')),
    _Rule('vowel', (w) => _rep(w, 'i', 'e')),
    _Rule('vowel', (w) => _rep(w, 'o', 'u')),
    _Rule('vowel', (w) => _rep(w, 'u', 'o')),
    _Rule('vowel', (w) => _rep(w, 'a', 'e')),
  ];

  // ────────────────────────────────────────────────────────────────────────────
  // English Rules
  // ────────────────────────────────────────────────────────────────────────────
  static final List<_Rule> _enRules = [
    // ── suffix confusions ─────────────────────────────────────────────────────
    _Rule('suffix', (w) => _rep(w, 'tion', 'sion')),
    _Rule('suffix', (w) => _rep(w, 'sion', 'tion')),
    _Rule('suffix', (w) => _rep(w, 'ance', 'ence')),
    _Rule('suffix', (w) => _rep(w, 'ence', 'ance')),
    _Rule('suffix', (w) => _rep(w, 'able', 'ible')),
    _Rule('suffix', (w) => _rep(w, 'ible', 'able')),
    _Rule('suffix', (w) => w.endsWith('er') && w.length > 4 ? '${w.substring(0, w.length - 2)}or' : w),
    _Rule('suffix', (w) => w.endsWith('or') && w.length > 4 ? '${w.substring(0, w.length - 2)}er' : w),
    _Rule('suffix', (w) => w.endsWith('ly') && w.length > 4 ? '${w.substring(0, w.length - 2)}ley' : w),
    _Rule('suffix', (w) => w.endsWith('ing') && w.length > 5 ? '${w.substring(0, w.length - 3)}eng' : w),
    _Rule('suffix', (w) => w.endsWith('ed') && w.length > 4 ? '${w.substring(0, w.length - 2)}id' : w),
    _Rule('suffix', (w) => w.endsWith('ness') ? '${w.substring(0, w.length - 4)}niss' : w),
    _Rule('suffix', (w) => w.endsWith('ment') ? '${w.substring(0, w.length - 4)}mant' : w),
    _Rule('suffix', (w) => w.endsWith('ful') ? '${w.substring(0, w.length - 3)}full' : w),

    // ── ph / f confusion ──────────────────────────────────────────────────────
    _Rule('ph', (w) => _rep(w, 'ph', 'f')),
    _Rule('ph', (w) => _rep(w, 'f', 'ph')),

    // ── ie / ei confusion ─────────────────────────────────────────────────────
    _Rule('ie', (w) => _rep(w, 'ie', 'ei')),
    _Rule('ie', (w) => _rep(w, 'ei', 'ie')),

    // ── double / single consonant ─────────────────────────────────────────────
    _Rule('double', (w) {
      for (int i = 0; i < w.length - 1; i++) {
        if (w[i].toLowerCase() == w[i + 1].toLowerCase()) {
          return '${w.substring(0, i)}${w.substring(i + 1)}';
        }
      }
      return w;
    }),
    _Rule('double', (w) {
      const consonants = 'bcdfghjklmnpqrstvwxyz';
      const vowels = 'aeiou';
      for (int i = 1; i < w.length - 1; i++) {
        if (consonants.contains(w[i].toLowerCase()) &&
            vowels.contains(w[i - 1].toLowerCase())) {
          return '${w.substring(0, i + 1)}${w[i]}${w.substring(i + 1)}';
        }
      }
      return w;
    }),

    // ── silent / extra letters ────────────────────────────────────────────────
    _Rule('silent', (w) => w.endsWith('e') && w.length > 3 ? w.substring(0, w.length - 1) : w),
    _Rule('silent', (w) => !w.endsWith('e') && w.length > 2 ? '${w}e' : w),
    _Rule('silent', (w) {
      final t = _rep(w, 'kn', 'n');
      return t != w ? t : _rep(w, 'wr', 'r');
    }),

    // ── gh spellings ──────────────────────────────────────────────────────────
    _Rule('gh', (w) {
      final t = _rep(w, 'ght', 'gt');
      return t != w ? t : _rep(w, 'gh', 'g');
    }),
    _Rule('gh', (w) => _rep(w, 'ough', 'uff')),
    _Rule('gh', (w) => _rep(w, 'ough', 'ow')),

    // ── c / k / ck confusion ─────────────────────────────────────────────────
    _Rule('ck', (w) => _rep(w, 'ck', 'k')),
    _Rule('ck', (w) => _rep(w, 'ck', 'c')),
    _Rule('ck', (w) {
      // Replace terminal 'c' before e/i with 'ck'
      final t = _rep(w, 'ce', 'cke');
      return t != w ? t : _rep(w, 'ci', 'cki');
    }),

    // ── vowel digraph confusion ───────────────────────────────────────────────
    _Rule('vowel', (w) => _rep(w, 'ea', 'ee')),
    _Rule('vowel', (w) => _rep(w, 'ee', 'ea')),
    _Rule('vowel', (w) => _rep(w, 'oo', 'ou')),
    _Rule('vowel', (w) => _rep(w, 'ou', 'ow')),
    _Rule('vowel', (w) => _rep(w, 'ow', 'ou')),
    _Rule('vowel', (w) => _rep(w, 'ai', 'ay')),
    _Rule('vowel', (w) => _rep(w, 'ay', 'ai')),
    _Rule('vowel', (w) => _rep(w, 'a', 'e')),
    _Rule('vowel', (w) => _rep(w, 'e', 'a')),
    _Rule('vowel', (w) => _rep(w, 'i', 'y')),
    _Rule('vowel', (w) => _rep(w, 'y', 'i')),
  ];
}

class _Rule {
  final String category;
  final String Function(String) _fn;

  _Rule(this.category, this._fn);

  String apply(String word) {
    try {
      return _fn(word);
    } catch (_) {
      return word;
    }
  }
}
