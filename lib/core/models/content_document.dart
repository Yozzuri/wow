enum ContentKind { video, music }

class ContentMeta {
  const ContentMeta({
    required this.title,
    this.source,
    this.language = 'en',
    this.durationMs,
  });

  final String title;
  final String? source;
  final String language;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'title': title,
    if (source != null) 'source': source,
    'language': language,
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory ContentMeta.fromJson(Map<String, dynamic> json) => ContentMeta(
    title: json['title'] as String? ?? '',
    source: json['source'] as String?,
    language: json['language'] as String? ?? 'en',
    durationMs: json['durationMs'] as int?,
  );

  ContentMeta copyWith({
    String? title,
    String? source,
    String? language,
    int? durationMs,
  }) => ContentMeta(
    title: title ?? this.title,
    source: source ?? this.source,
    language: language ?? this.language,
    durationMs: durationMs ?? this.durationMs,
  );
}

class ContentToken {
  const ContentToken({
    required this.surface,
    this.lemma,
    this.pos,
    this.meaning,
    this.phonetic,
  });

  final String surface;
  final String? lemma;
  final String? pos;
  final String? meaning;
  final String? phonetic;

  Map<String, dynamic> toJson() => {
    'surface': surface,
    if (lemma != null) 'lemma': lemma,
    if (pos != null) 'pos': pos,
    if (meaning != null) 'meaning': meaning,
    if (phonetic != null) 'phonetic': phonetic,
  };

  factory ContentToken.fromJson(Map<String, dynamic> json) => ContentToken(
    surface: json['surface'] as String? ?? '',
    lemma: json['lemma'] as String?,
    pos: json['pos'] as String?,
    meaning: json['meaning'] as String?,
    phonetic: json['phonetic'] as String?,
  );
}

class ContentPhrase {
  const ContentPhrase({required this.text, this.meaning, this.usage});

  final String text;
  final String? meaning;
  final String? usage;

  Map<String, dynamic> toJson() => {
    'text': text,
    if (meaning != null) 'meaning': meaning,
    if (usage != null) 'usage': usage,
  };

  factory ContentPhrase.fromJson(Map<String, dynamic> json) => ContentPhrase(
    text: json['text'] as String? ?? '',
    meaning: json['meaning'] as String?,
    usage: json['usage'] as String?,
  );
}

class GrammarNote {
  const GrammarNote({required this.pattern, required this.explanation});

  final String pattern;
  final String explanation;

  Map<String, dynamic> toJson() => {
    'pattern': pattern,
    'explanation': explanation,
  };

  factory GrammarNote.fromJson(Map<String, dynamic> json) => GrammarNote(
    pattern: json['pattern'] as String? ?? '',
    explanation: json['explanation'] as String? ?? '',
  );
}

class ContentSegment {
  const ContentSegment({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.translation,
    this.tokens = const [],
    this.grammar = const [],
    this.phrases = const [],
  });

  final int index;
  final int startMs;
  final int endMs;
  final String text;
  final String? translation;
  final List<ContentToken> tokens;
  final List<GrammarNote> grammar;
  final List<ContentPhrase> phrases;

  int get durationMs => endMs - startMs;

  Map<String, dynamic> toJson() => {
    'index': index,
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
    if (translation != null) 'translation': translation,
    if (tokens.isNotEmpty) 'tokens': tokens.map((t) => t.toJson()).toList(),
    if (grammar.isNotEmpty)
      'grammar': grammar.map((g) => g.toJson()).toList(),
    if (phrases.isNotEmpty)
      'phrases': phrases.map((p) => p.toJson()).toList(),
  };

  factory ContentSegment.fromJson(Map<String, dynamic> json) => ContentSegment(
    index: json['index'] as int? ?? 0,
    startMs: json['startMs'] as int? ?? 0,
    endMs: json['endMs'] as int? ?? 0,
    text: json['text'] as String? ?? '',
    translation: json['translation'] as String?,
    tokens:
        (json['tokens'] as List?)
            ?.map((e) => ContentToken.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    grammar:
        (json['grammar'] as List?)
            ?.map((e) => GrammarNote.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    phrases:
        (json['phrases'] as List?)
            ?.map((e) => ContentPhrase.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  ContentSegment copyWith({
    String? translation,
    List<ContentToken>? tokens,
    List<GrammarNote>? grammar,
    List<ContentPhrase>? phrases,
  }) => ContentSegment(
    index: index,
    startMs: startMs,
    endMs: endMs,
    text: text,
    translation: translation ?? this.translation,
    tokens: tokens ?? this.tokens,
    grammar: grammar ?? this.grammar,
    phrases: phrases ?? this.phrases,
  );
}

class ContentDocument {
  const ContentDocument({
    required this.meta,
    required this.segments,
    this.kind = ContentKind.video,
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final ContentKind kind;
  final ContentMeta meta;
  final List<ContentSegment> segments;

  ContentSegment? segmentAt(int positionMs) {
    for (final segment in segments) {
      if (positionMs >= segment.startMs && positionMs <= segment.endMs) {
        return segment;
      }
    }
    return null;
  }

  ContentSegment? get firstSegment =>
      segments.isEmpty ? null : segments.first;

  ContentDocument withoutAnalysis() => copyWith(
    segments: segments
        .map(
          (segment) => ContentSegment(
            index: segment.index,
            startMs: segment.startMs,
            endMs: segment.endMs,
            text: segment.text,
          ),
        )
        .toList(),
  );

  bool get hasRichAnalysis => segments.any(
    (segment) =>
        (segment.translation ?? '').isNotEmpty ||
        segment.tokens.isNotEmpty ||
        segment.grammar.isNotEmpty ||
        segment.phrases.isNotEmpty,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'type': kind.name,
    'meta': meta.toJson(),
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory ContentDocument.fromJson(Map<String, dynamic> json) {
    final kindName = json['type'] as String? ?? 'video';
    return ContentDocument(
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      kind: ContentKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => ContentKind.video,
      ),
      meta: ContentMeta.fromJson(
        (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      segments:
          (json['segments'] as List?)
              ?.map(
                (e) => ContentSegment.fromJson(
                  (e as Map).cast<String, dynamic>(),
                ),
              )
              .toList() ??
          const [],
    );
  }

  ContentDocument copyWith({
    ContentMeta? meta,
    List<ContentSegment>? segments,
    ContentKind? kind,
  }) => ContentDocument(
    meta: meta ?? this.meta,
    segments: segments ?? this.segments,
    kind: kind ?? this.kind,
    schemaVersion: schemaVersion,
  );
}

String normalizeWhitespace(String input) =>
    input.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
