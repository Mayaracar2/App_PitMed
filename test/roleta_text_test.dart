import 'package:flutter_test/flutter_test.dart';
import 'package:pitmed/roleta_text.dart';

void main() {
  test('Separa letras e mantém uma troca entre palavras e parágrafos', () {
    expect(separarLetrasRoleta('Olá!\r\n\r\n  café.\t ação'),
        ['O', 'L', 'A', ' ', 'C', 'A', 'F', 'E', ' ', 'A', 'C', 'A', 'O']);
  });

  test('Ignora pontuação, números e acentos Unicode combinados', () {
    expect(
        separarLetrasRoleta('123 ... ac\u0327a\u0303o!'), ['A', 'C', 'A', 'O']);
    expect(separarLetrasRoleta('123 ...'), isEmpty);
  });
}
