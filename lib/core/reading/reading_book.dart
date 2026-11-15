import 'dart:convert';
import 'dart:io';

export '../language/languages.dart';

import 'package:path_provider/path_provider.dart';

class ReadingChapter {
  const ReadingChapter({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final int start;
  final int end;

  Map<String, dynamic> toJson() => {
    'title': title,
    'start': start,
    'end': end,
  };

  factory ReadingChapter.fromJson(Map<String, dynamic> json) => ReadingChapter(
    title: json['title'] as String? ?? '',
    start: json['start'] as int? ?? 0,
    end: json['end'] as int? ?? 0,
  );
}

class ReadingBook {
  const ReadingBook({
    required this.id,
    required this.title,
    required this.language,
    required this.content,
    required this.createdAt,
    this.preprocessed = false,
    this.chapters = const [],
    this.translationTarget = 'zh',
    this.sourceFiles = const [],
  });

  final String id;
  final String title;
  final String language;
  final String content;
  final DateTime createdAt;
  final bool preprocessed;
  final List<ReadingChapter> chapters;
  final String translationTarget;
  final List<String> sourceFiles;

  int get characterCount => content.length;

  List<ReadingChapter> get effectiveChapters {
    if (chapters.isNotEmpty) {
      return chapters;
    }
    return [ReadingChapter(title: title, start: 0, end: content.length)];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'language': language,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'preprocessed': preprocessed,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'translationTarget': translationTarget,
    'sourceFiles': sourceFiles,
  };

  factory ReadingBook.fromJson(Map<String, dynamic> json) => ReadingBook(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '未命名读物',
    language: json['language'] as String? ?? 'en',
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now(),
    preprocessed: json['preprocessed'] as bool? ?? false,
    chapters:
        (json['chapters'] as List?)
            ?.whereType<Map>()
            .map((e) => ReadingChapter.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [],
    translationTarget: json['translationTarget'] as String? ?? 'zh',
    sourceFiles:
        (json['sourceFiles'] as List?)?.whereType<String>().toList() ??
        const [],
  );

  ReadingBook copyWith({
    String? id,
    String? title,
    String? language,
    String? content,
    bool? preprocessed,
    List<ReadingChapter>? chapters,
    String? translationTarget,
    List<String>? sourceFiles,
  }) => ReadingBook(
    id: id ?? this.id,
    title: title ?? this.title,
    language: language ?? this.language,
    content: content ?? this.content,
    createdAt: createdAt,
    preprocessed: preprocessed ?? this.preprocessed,
    chapters: chapters ?? this.chapters,
    translationTarget: translationTarget ?? this.translationTarget,
    sourceFiles: sourceFiles ?? this.sourceFiles,
  );
}

class ReadingStore {
  const ReadingStore();

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/reading');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<ReadingBook> save(ReadingBook book) async {
    final dir = await _directory();
    final id = book.id.isEmpty
        ? 'book_${DateTime.now().millisecondsSinceEpoch}'
        : book.id;
    final saved = book.copyWith(id: id);
    final file = File('${dir.path}/$id.json');
    await file.writeAsString(jsonEncode(saved.toJson()));
    return saved;
  }

  Future<List<ReadingBook>> list() async {
    final dir = await _directory();
    final books = <ReadingBook>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        books.add(ReadingBook.fromJson((json as Map).cast<String, dynamic>()));
      } catch (_) {
        // Ignore broken reading files.
      }
    }
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  }

  Future<void> delete(ReadingBook book) async {
    final dir = await _directory();
    final file = File('${dir.path}/${book.id}.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
