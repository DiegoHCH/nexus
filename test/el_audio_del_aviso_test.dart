import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/data/datasources/gemini_tts_data_source.dart';

/// Lo que decide si un aviso se oye entero.
///
/// Las dos formas de perder frase se oyen igual y se arreglan en sitios
/// distintos: el principio se lo come el altavoz al despertar, y el final se
/// perdía al quedarse con el primer trozo de la respuesta. Aquí se prueba la
/// segunda, que es la que tiene aritmética.
void main() {
  /// PCM de 16 bits a 24 kHz, que es lo que devuelve el servicio.
  Uint8List pcm(int bytes) => Uint8List(bytes)..fillRange(0, bytes, 7);

  String comoLlega(Uint8List datos) => base64Encode(datos);

  group('lo que se saca de la respuesta', () {
    test('el atajo que documenta la API', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"output_audio": {"data": "${comoLlega(pcm(48))}"}}',
      );

      expect(dicho.salio, isTrue);
      expect(dicho.pcm, hasLength(48));
    });

    test('y si no está, los pasos', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"steps": [{"content": [{"data": "${comoLlega(pcm(32))}"}]}]}',
      );

      expect(dicho.pcm, hasLength(32));
    });

    // 🔴 El bug que esto cierra: se devolvía en el primer trozo que decodificaba,
    // así que una respuesta partida sonaba solo hasta donde acabara el primero
    // — un aviso que dice media reunión y ningún error en ninguna parte.
    test('varios trozos se juntan, no se elige el primero', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"steps": [{"content": ['
        '{"data": "${comoLlega(pcm(10))}"},'
        '{"data": "${comoLlega(pcm(20))}"}'
        ']}]}',
      );

      expect(dicho.pcm, hasLength(30));
    });

    test('y también repartidos entre varios pasos', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"steps": ['
        '{"content": [{"data": "${comoLlega(pcm(10))}"}]},'
        '{"content": [{"data": "${comoLlega(pcm(6))}"}]}'
        ']}',
      );

      expect(dicho.pcm, hasLength(16));
    });

    // El orden es el de la respuesta: al revés, la frase suena con las palabras
    // cambiadas de sitio, que es peor que cortada porque parece que funciona.
    test('el orden de los trozos se conserva', () {
      final primero = Uint8List.fromList([1, 1]);
      final segundo = Uint8List.fromList([2, 2]);
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"steps": [{"content": ['
        '{"data": "${comoLlega(primero)}"},'
        '{"data": "${comoLlega(segundo)}"}'
        ']}]}',
      );

      expect(dicho.pcm, [1, 1, 2, 2]);
    });

    test('un trozo ilegible no se lleva por delante los demás', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        '{"steps": [{"content": ['
        '{"data": "no es base64 ni de lejos !!!"},'
        '{"data": "${comoLlega(pcm(12))}"}'
        ']}]}',
      );

      expect(dicho.pcm, hasLength(12));
    });
  });

  group('cuando no hay audio', () {
    test('una respuesta sin nada se cuenta como fallo', () {
      expect(GeminiTtsDataSource.leerElAudio('{"steps": []}').salio, isFalse);
      expect(GeminiTtsDataSource.leerElAudio('{}').salio, isFalse);
    });

    test('y una ilegible también, sin reventar', () {
      expect(GeminiTtsDataSource.leerElAudio('esto no es json').salio, isFalse);
      expect(GeminiTtsDataSource.leerElAudio('[]').salio, isFalse);
    });
  });
}
