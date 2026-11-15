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

bool isWordToken(String token) {
  if (token.trim().isEmpty) {
    return false;
  }
  return _wordPattern.hasMatch(token);
}

List<String> tokenizeLine(String text) {
  if (text.isEmpty) {
    return const [];
  }
  return _tokenPattern
      .allMatches(text)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}
