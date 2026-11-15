import 'dart:convert';
import 'dart:io';

export '../language/languages.dart';

import 'package:path_provider/path_provider.dart';

class ReadingBook {
  const ReadingBook({
    required this.id,
    required this.title,
    required this.language,
    required this.content,
    required this.createdAt,
    this.preprocessed = false,
  });

  final String id;
  final String title;
  final String language;
  final String content;
  final DateTime createdAt;
  final bool preprocessed;

  int get characterCount => content.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'language': language,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'preprocessed': preprocessed,
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
    final saved = ReadingBook(
      id: id,
      title: book.title,
      language: book.language,
      content: book.content,
      createdAt: book.createdAt,
      preprocessed: book.preprocessed,
    );
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

