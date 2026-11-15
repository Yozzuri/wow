import 'package:flutter_test/flutter_test.dart';
import 'package:langlearn/core/ai/subtitle_analyzer.dart';

void main() {
  test('parses fenced JSON analysis', () {
    const raw = '''
```json
{"segments":[{"index":0,"translation":"你好","tokens":[{"surface":"Hello","lemma":"hello","pos":"int.","meaning":"你好"}],"grammar":[{"pattern":"Hello there","explanation":"问候语"}],"phrases":[{"text":"welcome to","meaning":"欢迎来到"}]}]}
```
''';
    final parsed = parseAnalysisResponse(raw);
    expect(parsed, hasLength(1));
    expect(parsed[0]!.translation, '你好');
    expect(parsed[0]!.tokens.single.lemma, 'hello');
    expect(parsed[0]!.grammar.single.pattern, 'Hello there');
    expect(parsed[0]!.phrases.single.text, 'welcome to');
  });

  test('ignores malformed entries and empty tokens', () {
    expect(
      () => parseAnalysisResponse(
        '{"segments":[{"index":"x"},{"index":2,"translation":"","tokens":[{"surface":""}],"grammar":[]}]}',
      ),
      throwsFormatException,
    );
  });

  test('throws when there is no JSON', () {
    expect(() => parseAnalysisResponse('sorry'), throwsFormatException);
  });
}
