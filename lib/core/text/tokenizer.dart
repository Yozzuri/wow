final RegExp _tokenPattern = RegExp(
  r"[A-Za-z]+(?:['’\-][A-Za-z]+)*|[\u4e00-\u9fff]|\d+(?:[.,]\d+)*|[^\sA-Za-z\u4e00-\u9fff\d]+|\s+",
);

bool isWordToken(String token) {
  if (token.trim().isEmpty) {
    return false;
  }
  return RegExp(
    r"^(?:[A-Za-z]+(?:['’\-][A-Za-z]+)*|[\u4e00-\u9fff]|\d+(?:[.,]\d+)*)$",
  ).hasMatch(token);
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
