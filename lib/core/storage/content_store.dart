import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/content_document.dart';

class ContentStore {
  const ContentStore();

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/analysis');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String keyFor(ContentDocument document) {
    final buffer = StringBuffer()
      ..write(document.kind.name)
      ..write('|')
      ..write(document.meta.title)
      ..write('|')
      ..write(document.meta.source ?? '');
    for (final segment in document.segments) {
      buffer
        ..write('|')
        ..write(segment.startMs)
        ..write('-')
        ..write(segment.endMs)
        ..write(':')
        ..write(segment.text);
    }
    return sha1.convert(utf8.encode(buffer.toString())).toString();
  }

  Future<void> saveAnalysis(ContentDocument document) async {
    final dir = await _directory();
    final file = File('${dir.path}/${keyFor(document)}.json');
    await file.writeAsString(jsonEncode(document.toJson()));
  }

  Future<ContentDocument?> loadAnalysis(ContentDocument base) async {
    final dir = await _directory();
    final file = File('${dir.path}/${keyFor(base)}.json');
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      return ContentDocument.fromJson(
        (decoded as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }
}
