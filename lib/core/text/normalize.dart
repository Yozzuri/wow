String normalizeForMatch(String input) {
  final withoutBrackets = input
      .replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), ' ')
      .toLowerCase();
  final cleaned = withoutBrackets.replaceAll(
    RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
    '',
  );
  return cleaned.isEmpty
      ? input.toLowerCase().replaceAll(RegExp(r'\s+'), '')
      : cleaned;
}
