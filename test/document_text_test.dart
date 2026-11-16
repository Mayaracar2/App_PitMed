import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pitmed/document_text.dart';
import 'package:pitmed/roleta_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  });

  test('TXT preserva acentos em UTF-8 e Latin-1', () async {
    for (final bytes in [
      utf8.encode('ação café'),
      latin1.encode('ação café')
    ]) {
      final texto =
          await extrairTextoDocumento(Uint8List.fromList(bytes), 'txt');
      expect(texto, 'ação café');
      expect(separarLetrasRoleta(texto),
          ['A', 'C', 'A', 'O', ' ', 'C', 'A', 'F', 'E']);
    }
  });

  test('DOCX preserva parágrafos, runs, tabelas e separadores', () async {
    final xml =
        '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        <w:p><w:r><w:t>Olá </w:t></w:r><w:r><w:t>você</w:t><w:tab/><w:t>está</w:t><w:br/><w:t>bem?</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>ação &amp; café</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
      </w:body></w:document>''';
    final arquivo = Archive()
      ..addFile(ArchiveFile(
          'word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(arquivo));
    final texto = await extrairTextoDocumento(bytes, 'DOCX');
    expect(texto, 'Olá você\testá\nbem?\nação & café');
    expect(separarLetrasRoleta(texto).join(), 'OLA VOCE ESTA BEM ACAO CAFE');
  });

  test('DOCX sem documento é rejeitado', () async {
    final bytes = Uint8List.fromList(ZipEncoder().encode(Archive()));
    await expectLater(
        extrairTextoDocumento(bytes, 'docx'), throwsFormatException);
  });

  test('PDF extrai texto de todas as páginas', () async {
    final texto = await extrairTextoDocumento(_pdfComDuasPaginas(), 'pdf');
    expect(texto, contains('Primeira palavra'));
    expect(texto, contains('Segunda palavra'));
    expect(texto.indexOf('Primeira'), lessThan(texto.indexOf('Segunda')));
    expect(
        separarLetrasRoleta(texto).join(), 'PRIMEIRA PALAVRA SEGUNDA PALAVRA');
  });

  test('Formato desconhecido é rejeitado', () async {
    await expectLater(
        extrairTextoDocumento(Uint8List(0), 'doc'), throwsFormatException);
  });
}

Uint8List _pdfComDuasPaginas() {
  final objetos = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    for (final texto in ['Primeira palavra', 'Segunda palavra'])
      _stream('BT /F1 12 Tf 30 150 Td ($texto) Tj ET'),
  ];
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objetos.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objetos[i]}\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${objetos.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write(
      'trailer\n<< /Size ${objetos.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(ascii.encode(pdf.toString()));
}

String _stream(String texto) =>
    '<< /Length ${texto.length} >>\nstream\n$texto\nendstream';
