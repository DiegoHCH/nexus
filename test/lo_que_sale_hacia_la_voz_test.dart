import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_sale_hacia_la_voz.dart';

/// El techo de lo que cruza hacia Google.
///
/// La contra que el informe de valor marcó como bloqueante decía que el audio y
/// lo que Claude leyó del repo viajan al servicio de voz. Eso no se puede
/// evitar mientras sea Gemini quien narra; lo que sí se podía evitar es que
/// **no tuviera techo**, que era el estado real: salía la respuesta entera, del
/// tamaño que fuera.

void main() {
  String largo(int caracteres) => 'a' * caracteres;

  group('cuándo se recorta', () {
    test('lo que cabe no se toca', () {
      const corta = 'son tres archivos y ninguno falla';
      expect(LoQueSaleHaciaLaVoz.sobra(corta), isFalse);
      expect(LoQueSaleHaciaLaVoz.recortar(corta), corta);
    });

    test('justo en el tope todavía cabe', () {
      final justa = largo(LoQueSaleHaciaLaVoz.maxCaracteres);
      expect(LoQueSaleHaciaLaVoz.sobra(justa), isFalse);
      expect(LoQueSaleHaciaLaVoz.recortar(justa), justa);
    });

    test('uno más ya no', () {
      expect(
        LoQueSaleHaciaLaVoz.sobra(largo(LoQueSaleHaciaLaVoz.maxCaracteres + 1)),
        isTrue,
      );
    });
  });

  group('por dónde se corta', () {
    test('se queda el principio, que es donde va la conclusión', () {
      final respuesta =
          'Fallan dos pruebas.\n${'el detalle largo y aburrido\n' * 500}';
      final salida = LoQueSaleHaciaLaVoz.recortar(respuesta);

      expect(salida, startsWith('Fallan dos pruebas.'));
    });

    test('por un salto de línea, no a mitad de palabra', () {
      final respuesta = '${'una linea entera de texto\n' * 400}fin';
      final salida = LoQueSaleHaciaLaVoz.recortar(respuesta);
      final cuerpo = salida.substring(
        0,
        salida.length - LoQueSaleHaciaLaVoz.aviso.length,
      );

      expect(cuerpo, endsWith('texto'));
    });

    // Sin salto de línea cerca hay que conformarse con menos, pero nunca con
    // partir una palabra: eso se narra fatal y es lo único que se oye del corte.
    test('sin saltos, por un punto o al menos por un espacio', () {
      final respuesta = 'palabra ' * 900;
      final salida = LoQueSaleHaciaLaVoz.recortar(respuesta);
      final cuerpo = salida.substring(
        0,
        salida.length - LoQueSaleHaciaLaVoz.aviso.length,
      );

      expect(cuerpo, endsWith('palabra'));
    });

    // El caso feo: un solo churro sin un hueco donde cortar. Se corta a pelo,
    // porque devolverlo entero sería no tener tope.
    test('un texto sin un solo hueco se corta igual', () {
      final salida = LoQueSaleHaciaLaVoz.recortar(largo(20000));

      expect(
        salida.length,
        LoQueSaleHaciaLaVoz.maxCaracteres + LoQueSaleHaciaLaVoz.aviso.length,
      );
    });
  });

  group('lo que se le dice al modelo', () {
    test('el aviso viaja dentro de lo recortado', () {
      final salida = LoQueSaleHaciaLaVoz.recortar(largo(20000));
      expect(salida, endsWith(LoQueSaleHaciaLaVoz.aviso));
    });

    // Las tres cosas que el aviso tiene que conseguir, y por qué: que no narre
    // un trozo como si fuera todo, que diga dónde está el resto, y que no
    // rellene el final por su cuenta — que es lo que hace un modelo al que le
    // llega una frase a medias.
    test('dice que hay más, dónde, y que no se lo invente', () {
      final aviso = LoQueSaleHaciaLaVoz.aviso.toLowerCase();
      expect(aviso, contains('pantalla'));
      expect(aviso, contains('inventes'));
    });
  });

  // La pantalla de salidas dice qué sale por cada puerta, y desde hoy también
  // cuánto. Si el tope cambia y la frase no, la pantalla miente sobre el único
  // número que alguien va a apuntar en una reunión de seguridad.
  test('la pantalla de salidas cuenta el mismo tope que se aplica', () {
    final miles = LoQueSaleHaciaLaVoz.maxCaracteres ~/ 1000;
    expect(const NexusStringsEs().exitGeminiWhat, contains('$miles.000'));
    expect(const NexusStringsEn().exitGeminiWhat, contains('$miles,000'));
  });

  // De forma, y por lo que costó decidirlo: recortar en el origen —al devolver
  // el encargo— habría sido una línea en vez de dos, y habría escondido en el
  // Mac algo que el Mac sí puede enseñar. La pantalla ve la respuesta entera;
  // lo que se recorta es solo lo que cruza la frontera.
  test('el recorte vive en los dos sitios por donde sale, no en el origen', () {
    final fuente = File(
      'lib/features/assistant/domain/usecases/hold_voice_conversation.dart',
    ).readAsStringSync();

    final devuelve = fuente.substring(
      fuente.indexOf("return answer.isEmpty"),
      fuente.indexOf("return answer.isEmpty") + 200,
    );
    expect(
      devuelve,
      isNot(contains('LoQueSaleHaciaLaVoz')),
      reason:
          'recortado en el origen, la pantalla perdería lo que sí puede ver',
    );

    expect(
      'loQueCabe('.allMatches(fuente).length,
      3,
      reason:
          'la declaración y las dos salidas: el resultado de la herramienta y '
          'la corrección. Si aparece una salida nueva sin pasar por aquí, esto '
          'se entera',
    );
  });
}
