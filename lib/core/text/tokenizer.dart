import 'package:japanese_word_tokenizer/japanese_word_tokenizer.dart' as jp;

const String _wordRanges =
    'A-Za-z\\u00C0-\\u024F\\u0370-\\u04FF\\u1E00-\\u1EFF';
const String _characterRanges =
    '\\u3040-\\u30FF\\u3400-\\u4DBF\\u4E00-\\u9FFF\\u0E00-\\u0E7F\\u0600-\\u06FF';
const String _hangulRanges = '\\u1100-\\u11FF\\u3130-\\u318F\\uAC00-\\uD7AF';

final RegExp _tokenPattern = RegExp(
  "[$_wordRanges]+(?:['’\\-][$_wordRanges]+)*"
  "|[$_characterRanges]"
  "|[$_hangulRanges]+"
  "|\\d+(?:[.,]\\d+)*"
  "|[^\\s$_wordRanges$_characterRanges$_hangulRanges\\d]+"
  "|\\s+",
);

final RegExp _wordPattern = RegExp(
  "^(?:[$_wordRanges]+(?:['’\\-][$_wordRanges]+)*"
  "|[$_characterRanges]"
  "|[$_hangulRanges]+"
  "|\\d+(?:[.,]\\d+)*)\$",
);

final RegExp _contentPattern = RegExp(
  "[$_wordRanges$_characterRanges$_hangulRanges]",
);

bool isWordToken(String token) {
  if (token.trim().isEmpty) {
    return false;
  }
  return _wordPattern.hasMatch(token);
}

bool hasWordContent(String token) => _contentPattern.hasMatch(token);

List<String> tokenizeLine(String text) {
  if (text.isEmpty) {
    return const [];
  }
  return _tokenPattern
      .allMatches(text)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}

class TextChunk {
  const TextChunk(this.text, this.word);

  final String text;
  final String? word;
}

final Map<String, List<TextChunk>> _chunkCache = {};

List<TextChunk> _cachedChunks(String key, List<TextChunk> Function() build) {
  final cached = _chunkCache[key];
  if (cached != null) {
    return cached;
  }
  final chunks = build();
  if (_chunkCache.length > 400) {
    _chunkCache.remove(_chunkCache.keys.first);
  }
  _chunkCache[key] = chunks;
  return chunks;
}

/// Splits [text] into display chunks. Japanese uses dictionary-free
/// wakachigaki word segmentation so a tap selects a whole word instead of a
/// single character. Space-delimited languages keep the punctuation attached
/// to the preceding word for a natural reading flow.
List<TextChunk> textChunks(String text, {String language = 'en'}) {
  if (text.isEmpty) {
    return const [];
  }
  final cacheKey = '$language|$text';
  return _cachedChunks(cacheKey, () {
    if (language == 'ja') {
      final chunks = <TextChunk>[];
      for (final raw in jp.tokenize(text)) {
        if (raw.isEmpty) {
          continue;
        }
        // Keep whitespace: Japanese lyrics often separate phrases with
        // spaces, and dropping them visually glues words together.
        if (raw.trim().isEmpty) {
          chunks.add(TextChunk(raw, null));
          continue;
        }
        chunks.add(
          hasWordContent(raw)
              ? TextChunk(raw, raw.trim())
              : TextChunk(raw, null),
        );
      }
      return chunks;
    }
    final tokens = tokenizeLine(text);
    final chunks = <TextChunk>[];
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      if (isWordToken(token)) {
        var chunk = token;
        var j = i + 1;
        while (j < tokens.length && !isWordToken(tokens[j])) {
          chunk += tokens[j];
          j++;
        }
        chunks.add(TextChunk(chunk, token));
        i = j;
      } else {
        chunks.add(TextChunk(token, null));
        i++;
      }
    }
    return chunks;
  });
}
