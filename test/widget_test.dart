import 'package:flutter_test/flutter_test.dart';

import 'package:wlv_panel/main.dart';

void main() {
  group('isWlvdUrl', () {
    test('aceita o domínio canônico e subdomínios', () {
      expect(isWlvdUrl('https://worldlabourvalues.org'), isTrue);
      expect(isWlvdUrl('https://panel.worldlabourvalues.org'), isTrue);
      expect(isWlvdUrl('https://www.worldlabourvalues.org'), isTrue);
      expect(isWlvdUrl('https://worldlabourvalues.org/?tab=map'), isTrue);
    });

    test('rejeita domínios externos', () {
      expect(isWlvdUrl('https://github.com/rodrigofranklin/wlvpanel'), isFalse);
      expect(isWlvdUrl('https://labcidades.ufes.br'), isFalse);
      expect(isWlvdUrl('https://example.org'), isFalse);
    });

    test('rejeita URLs inválidas', () {
      expect(isWlvdUrl('not a url'), isFalse);
      expect(isWlvdUrl(''), isFalse);
    });
  });
}
