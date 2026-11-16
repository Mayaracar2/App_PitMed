String normalizarTextoRoleta(String texto) {
  texto = texto.trim().toUpperCase();
  const comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const semAcento = 'AAAAAEEEEIIIIOOOOOUUUUC';
  for (var i = 0; i < comAcento.length; i++) {
    texto = texto.replaceAll(comAcento[i], semAcento[i]);
  }
  return texto.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
}

// Um espaço marca a troca de palavra no fluxo de feedback da roleta.
List<String> separarLetrasRoleta(String texto) {
  final palavras = normalizarTextoRoleta(texto).split(RegExp(r'\s+'));
  final letras = <String>[];
  final letraValida = RegExp(r'[A-Z]');
  for (final palavra in palavras) {
    final letrasDaPalavra =
        palavra.split('').where(letraValida.hasMatch).toList();
    if (letrasDaPalavra.isEmpty) continue;
    if (letras.isNotEmpty) letras.add(' ');
    letras.addAll(letrasDaPalavra);
  }
  return letras;
}
