class ReadingLanguage {
  const ReadingLanguage({
    required this.code,
    required this.label,
    required this.usesSpaces,
  });

  final String code;
  final String label;
  final bool usesSpaces;
}

const readingLanguages = <ReadingLanguage>[
  ReadingLanguage(code: 'en', label: '英语', usesSpaces: true),
  ReadingLanguage(code: 'ja', label: '日语', usesSpaces: false),
  ReadingLanguage(code: 'zh', label: '中文', usesSpaces: false),
  ReadingLanguage(code: 'ko', label: '韩语', usesSpaces: true),
  ReadingLanguage(code: 'es', label: '西班牙语', usesSpaces: true),
  ReadingLanguage(code: 'fr', label: '法语', usesSpaces: true),
  ReadingLanguage(code: 'de', label: '德语', usesSpaces: true),
  ReadingLanguage(code: 'ru', label: '俄语', usesSpaces: true),
  ReadingLanguage(code: 'th', label: '泰语', usesSpaces: false),
  ReadingLanguage(code: 'ar', label: '阿拉伯语', usesSpaces: true),
  ReadingLanguage(code: 'other', label: '其他', usesSpaces: true),
];

ReadingLanguage readingLanguageFor(String code) => readingLanguages
    .firstWhere((language) => language.code == code, orElse: () => readingLanguages.last);

bool languageUsesSpaces(String code) => readingLanguageFor(code).usesSpaces;

int _count(String text, RegExp pattern) => pattern.allMatches(text).length;

/// Lightweight script-based language detection used to preselect a language
/// for imported subtitles, lyrics and books.
String detectLanguage(String text) {
  if (text.trim().isEmpty) {
    return 'en';
  }
  final kana = _count(text, RegExp(r'[\u3040-\u30FF]'));
  final hangul = _count(text, RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]'));
  final cjk = _count(text, RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]'));
  final cyrillic = _count(text, RegExp(r'[\u0400-\u04FF]'));
  final thai = _count(text, RegExp(r'[\u0E00-\u0E7F]'));
  final arabic = _count(text, RegExp(r'[\u0600-\u06FF]'));
  final latin = _count(text, RegExp(r'[A-Za-z\u00C0-\u024F]'));
  final total = kana + hangul + cjk + cyrillic + thai + arabic + latin;
  if (total == 0) {
    return 'en';
  }
  if (kana > 0) {
    return 'ja';
  }
  if (hangul > 0 && hangul >= latin * 0.2) {
    return 'ko';
  }
  if (cjk > 0 && cjk >= latin * 1.5) {
    return 'zh';
  }
  if (thai > 0 && thai >= latin * 0.2) {
    return 'th';
  }
  if (cyrillic > 0 && cyrillic >= latin * 0.5) {
    return 'ru';
  }
  if (arabic > 0 && arabic >= latin * 0.5) {
    return 'ar';
  }
  if (RegExp(r'[ñ¿¡]', caseSensitive: false).hasMatch(text)) {
    return 'es';
  }
  if (RegExp(r'[ßäöü]', caseSensitive: false).hasMatch(text)) {
    return 'de';
  }
  if (RegExp(r'[çàèùœ]', caseSensitive: false).hasMatch(text)) {
    return 'fr';
  }
  return 'en';
}
