import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/gemini_image_data_source.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';

/// Pedir una imagen escribiendo `/imagen …`.
///
/// Las dos mitades que se rompen en silencio: reconocer la petición sin
/// secuestrar texto que no lo era, y leer la respuesta de una API que la propia
/// documentación acaba de cambiar —`generateContent` quedó marcada como legacy
/// y las imágenes van por la Interactions API, que devuelve otra cosa—.
void main() {
  group('qué cuenta como pedir una imagen', () {
    test('el prefijo con su descripción detrás', () {
      expect(
        LoQueSePideDibujar.deLaFrase('/imagen un zorro leyendo'),
        'un zorro leyendo',
      );
      expect(LoQueSePideDibujar.deLaFrase('/img un zorro'), 'un zorro');
    });

    // 🔴 Sin el espacio, `/imagenes` pediría dibujar «es»: se gastaría dinero
    // generando cualquier cosa, que es peor que no reconocer el atajo.
    test('sin espacio detrás no es el atajo', () {
      expect(LoQueSePideDibujar.deLaFrase('/imagenes de ayer'), isNull);
    });

    test('el prefijo solo, sin descripción, no dibuja nada', () {
      expect(LoQueSePideDibujar.deLaFrase('/imagen'), isNull);
      expect(LoQueSePideDibujar.deLaFrase('/imagen   '), isNull);
    });

    // Buscándolo dentro del texto, «mira el /imagen del script» se convertiría
    // en un dibujo. El atajo empieza la frase o no es.
    test('en medio de una frase no cuenta', () {
      expect(
        LoQueSePideDibujar.deLaFrase('arregla el /imagen del script'),
        isNull,
      );
    });

    test('el nombre del archivo sale de lo que pediste', () {
      final nombre = LoQueSePideDibujar.nombrePara(
        'Un zorro naranja leyendo un libro, estilo plano',
        DateTime(2026, 8, 31, 9, 5, 7),
      );

      expect(nombre, '20260831-090507-un-zorro-naranja-leyendo-un.png');
    });
  });

  group('lo que devuelve Gemini', () {
    String respuestaCon(Object? cuerpo) => jsonEncode(cuerpo);

    test('la imagen por el atajo documentado', () {
      final hecha = GeminiImageDataSource.leerLaImagen(
        respuestaCon({
          'output_image': {
            'data': base64Encode([1, 2, 3]),
            'mime_type': 'image/png',
          },
        }),
      );

      expect(hecha.salio, isTrue);
      expect(hecha.bytes, [1, 2, 3]);
      expect(hecha.mime, 'image/png');
    });

    // El atajo es una comodidad; lo que manda es la lista de pasos. Si un día
    // no viene, la imagen sigue estando y darla por perdida sería absurdo.
    test('y también recorriendo los pasos si no viene el atajo', () {
      final hecha = GeminiImageDataSource.leerLaImagen(
        respuestaCon({
          'steps': [
            {
              'content': [
                {
                  'type': 'image/png',
                  'data': base64Encode([9, 9]),
                },
              ],
            },
          ],
        }),
      );

      expect(hecha.salio, isTrue);
      expect(hecha.bytes, [9, 9]);
    });

    // El modelo puede negarse a dibujar y contestar con texto. Decir qué dijo
    // es mejor que un «no se pudo» a secas.
    test('si contesta con texto en vez de imagen, se dice qué dijo', () {
      final hecha = GeminiImageDataSource.leerLaImagen(
        respuestaCon({
          'steps': [
            {
              'content': [
                {'type': 'text', 'text': 'no puedo dibujar eso'},
              ],
            },
          ],
        }),
      );

      expect(hecha.salio, isFalse);
      expect(hecha.problema, 'no puedo dibujar eso');
    });

    test('una respuesta ilegible no revienta', () {
      final hecha = GeminiImageDataSource.leerLaImagen('esto no es json');

      expect(hecha.salio, isFalse);
      expect(hecha.problema, 'respuesta ilegible de Gemini');
    });

    // «403» no dice si falta facturación, si la llave es de otro proyecto o si
    // el modelo no está disponible, y las tres se arreglan distinto.
    test('el motivo que da la API se prefiere al código de estado', () {
      final motivo = GeminiImageDataSource.loQueSalioMal(
        respuestaCon({
          'error': {'message': 'Billing is not enabled for this project.'},
        }),
      );

      expect(motivo, 'Billing is not enabled for this project.');
    });
  });
}
