import 'dart:typed_data';

/// El altavoz, visto desde el dominio: se le encolan trozos de PCM y suenan
/// seguidos.
///
/// Existe [discard] porque una conversación por voz se interrumpe: cuando el
/// usuario habla encima, lo que queda por sonar deja de ser válido y hay que
/// tirarlo, no esperar a que termine.
abstract class AudioOutput {
  /// Prepara el dispositivo. Idempotente: llamarlo dos veces no rearranca nada.
  Future<void> start();

  /// Encola PCM de 16 bits mono. No bloquea: suena cuando le toque.
  void enqueue(Uint8List pcm);

  /// Tira lo que quede sin sonar. Lo ya entregado al sistema termina de
  /// sonar igual, así que el corte nunca es instantáneo del todo.
  Future<void> discard();

  Future<void> stop();
}
