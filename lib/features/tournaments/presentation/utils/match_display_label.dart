String matchDisplayLabel(String? label, {required String fallback}) {
  return (label ?? fallback)
      .replaceAll(RegExp(r'\bSpiele\b'), 'Begegnungen')
      .replaceAll(RegExp(r'\bSpiel\b'), 'Begegnung')
      .replaceAll('Spielrunde', 'Begegnungsrunde');
}
