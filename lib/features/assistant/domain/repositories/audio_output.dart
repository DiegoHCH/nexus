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

  /// Tira lo que quede sin sonar.
  Future<void> discard();

  /// Cuánto queda por sonar de lo ya encolado.
  ///
  /// Hace falta porque el servicio de voz entrega la respuesta más rápido que
  /// en tiempo real: cuando dejan de llegar trozos, el altavoz todavía tiene
  /// frases enteras pendientes. Quien decida cerrar la sesión tiene que
  /// preguntar esto antes, o cortará a media palabra.
  Future<Duration> pending();

  Future<void> stop();
}
