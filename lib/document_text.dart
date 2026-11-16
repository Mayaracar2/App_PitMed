import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

Future<String> extrairTextoDocumento(Uint8List bytes, String extensao) async {
  switch (extensao.toLowerCase()) {
    case 'txt':
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    case 'pdf':
      await pdfrxFlutterInitialize();
      final documento = await PdfDocument.openData(bytes);
      try {
        final paginas = <String>[];
        for (final pagina in documento.pages) {
          final texto = await pagina.loadText();
          if (texto != null) paginas.add(texto.fullText);
        }
        return paginas.join('\n');
      } finally {
        await documento.dispose();
      }
    case 'docx':
      final arquivo = ZipDecoder().decodeBytes(bytes);
      final conteudo = arquivo.findFile('word/document.xml');
      if (conteudo == null) {
        throw const FormatException('Arquivo DOCX inválido.');
      }
      final documento = XmlDocument.parse(utf8.decode(conteudo.content));
      const namespace =
          'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
      final paragrafos = <String>[];
      for (final paragrafo
          in documento.findAllElements('p', namespaceUri: namespace)) {
        final texto = StringBuffer();
        for (final elemento in paragrafo.descendants.whereType<XmlElement>()) {
          if (elemento.namespaceUri != namespace) continue;
          switch (elemento.name.local) {
            case 't':
              texto.write(elemento.innerText);
              break;
            case 'tab':
              texto.write('\t');
              break;
            case 'br':
            case 'cr':
              texto.write('\n');
              break;
          }
        }
        paragrafos.add(texto.toString());
      }
      return paragrafos.join('\n');
    default:
      throw const FormatException('Formato de arquivo não suportado.');
  }
}
