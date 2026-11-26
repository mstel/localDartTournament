String matchDisplayLabel(String? label, {required String fallback}) {
  final resolved = (label ?? fallback).trim();
  if (resolved.isEmpty) return fallback;
  if (RegExp(r'^Spiel um Platz\b').hasMatch(resolved)) {
    return resolved;
  }
  return resolved
      .replaceAll(RegExp(r'\bSpiele\b'), 'Begegnungen')
      .replaceAll(RegExp(r'\bSpiel\b'), 'Begegnung')
      .replaceAll('Spielrunde', 'Begegnungsrunde');
}
