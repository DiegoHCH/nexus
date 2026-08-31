import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/data/datasources/gemini_tts_data_source.dart';

/// La voz del aviso, que es una llamada suelta y no una sesión.
///
/// Aquí nadie está mirando la pantalla: si esto falla en silencio, el fallo es
/// que el aviso no suena y no queda rastro de por qué. Por eso lo que se prueba
/// es sobre todo que **siempre haya una respuesta**.
void main() {
  String json(Object? cuerpo) => jsonEncode(cuerpo);

  group('lo que devuelve', () {
    test('el audio por el atajo documentado', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        json({
          'output_audio': {
            'data': base64Encode([1, 2, 3]),
          },
        }),
      );

      expect(dicho.salio, isTrue);
      expect(dicho.pcm, [1, 2, 3]);
    });

    test('y recorriendo los pasos si el atajo no viene', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        json({
          'steps': [
            {
              'content': [
                {
                  'data': base64Encode([7, 7]),
                },
              ],
            },
          ],
        }),
      );

      expect(dicho.pcm, [7, 7]);
    });

    test('sin audio se dice, no se devuelve vacío', () {
      final dicho = GeminiTtsDataSource.leerElAudio(
        json({'steps': <Object>[]}),
      );

      expect(dicho.salio, isFalse);
      expect(dicho.problema, 'no devolvió audio');
    });

    test('una respuesta ilegible no revienta', () {
      expect(
        GeminiTtsDataSource.leerElAudio('esto no es json').problema,
        'respuesta ilegible',
      );
    });

    // Un código a secas no distingue una llave de otro proyecto de una voz que
    // no existe, y esas dos se arreglan distinto.
    test('el motivo de la API se prefiere al código de estado', () {
      expect(
        GeminiTtsDataSource.loQueSalioMal(
          json({
            'error': {'message': 'Requested voice is not available.'},
          }),
        ),
        'Requested voice is not available.',
      );
    });
  });

  group('lo que ni siquiera sale a la red', () {
    test('sin llave se dice', () async {
      final dicho = await const GeminiTtsDataSource().decir(
        llave: '',
        frase: 'lo que sea',
        voz: 'Charon',
      );

      expect(dicho.problema, 'falta la llave');
    });

    // Un aviso vacío sería una llamada pagada para no decir nada.
    test('sin frase tampoco', () async {
      final dicho = await const GeminiTtsDataSource().decir(
        llave: 'la-que-sea',
        frase: '   ',
        voz: 'Charon',
      );

      expect(dicho.problema, 'no hay nada que decir');
    });
  });

  // El motor de audio documenta 24 kHz como no negociable, y es exactamente lo
  // que sirve este modelo. Si un día deja de coincidir, el aviso sonaría a otra
  // velocidad — así que el modelo queda fijado aquí.
  test('el modelo es el que sirve PCM a 24 kHz', () {
    expect(GeminiTtsDataSource.modelo, 'gemini-2.5-flash-preview-tts');
  });
}
