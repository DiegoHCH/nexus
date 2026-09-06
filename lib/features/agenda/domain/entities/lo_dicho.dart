import 'dart:typed_data';

/// Lo que devolvió pedir que digan una frase: el audio, o el motivo.
class LoDicho {
  const LoDicho.ok(this.pcm) : problema = null;
  const LoDicho.fallo(this.problema) : pcm = null;

  /// PCM de 16 bits, mono, 24 kHz — **exactamente lo que come el motor de
  /// audio**, que documenta esa frecuencia como no negociable. No hay
  /// conversión de por medio y por eso esto suena sin tocar nada nativo.
  final Uint8List? pcm;
  final String? problema;

  bool get salio => pcm != null;
}
