String normalizeForMatch(String input) {
  final withoutBrackets = input
      .replaceAll(RegExp(r'[\(（\[【].*?[\)）\]】]'), ' ')
      .toLowerCase();
  final cleaned = withoutBrackets.replaceAll(
    RegExp(
      r'[^a-z0-9\u00c0-\u024f\u0370-\u04ff\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\u0e00-\u0e7f\u0600-\u06ff]+',
    ),
    '',
  );
  return cleaned.isEmpty
      ? input.toLowerCase().replaceAll(RegExp(r'\s+'), '')
      : cleaned;
}
