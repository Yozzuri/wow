import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class AiChunkCache {
  const AiChunkCache();

  static const Duration _ttl = Duration(days: 30);

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/ai_cache/chunks');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String keyFor(String namespace, String language, String payload) {
    return sha1
        .convert(utf8.encode('$namespace|$language|$payload'))
        .toString();
  }

  Future<String?> read(String key) async {
    final dir = await _directory();
    final file = File('${dir.path}/$key.txt');
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    if (DateTime.now().difference(stat.modified) > _ttl) {
      return null;
    }
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    final dir = await _directory();
    final file = File('${dir.path}/$key.txt');
    await file.writeAsString(value);
  }

  Future<void> clear() async {
    final dir = await _directory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> totalBytes() async {
    final dir = await _directory();
    if (!await dir.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}

Future<void> runWithConcurrency<T>(
  List<T> items,
  int limit,
  Future<void> Function(T item, int index) task,
) async {
  if (items.isEmpty) {
    return;
  }
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next;
      if (index >= items.length) {
        return;
      }
      next++;
      await task(items[index], index);
    }
  }

  await Future.wait(
    List.generate(limit.clamp(1, items.length), (_) => worker()),
  );
}
