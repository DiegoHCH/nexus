import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/gemini_image_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/modelo_de_imagen.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';

/// Pedir una imagen escribiendo `/imagen …`.
///
/// Las dos mitades que se rompen en silencio: reconocer la petición sin
/// secuestrar texto que no lo era, y leer la respuesta de una API que la propia
/// documentación acaba de cambiar —`generateContent` quedó marcada como legacy
/// y las imágenes van por la Interactions API, que devuelve otra cosa—.
void main() {
  // 🔴 Un id mal escrito es un 404 en la cara de quien pide la imagen, y no se
  // ve hasta que alguien paga por descubrirlo. Están copiados de la
  // documentación, así que lo que se vigila es que nadie los toque de más.
  group('los modelos que se ofrecen', () {
    test('sus identificadores son los de la API', () {
      expect(ModeloDeImagen.values.map((m) => m.id), [
        'gemini-3.1-flash-image',
        'gemini-3.1-flash-lite-image',
        'gemini-2.5-flash-image',
      ]);
    });

    // Lo guardado puede ser de una versión anterior o de un modelo retirado.
    // Volver al de siempre es mejor que no dibujar.
    test('lo que no se reconoce cae en el de siempre', () {
      expect(
        ModeloDeImagen.porId('el-que-ya-no-existe'),
        ModeloDeImagen.nanoBanana2,
      );
      expect(ModeloDeImagen.porId(null), ModeloDeImagen.nanoBanana2);
      expect(
        ModeloDeImagen.porId('gemini-2.5-flash-image'),
        ModeloDeImagen.nanoBanana,
      );
    });
  });

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

    // 🔴 **Dos atajos y no uno con reglas.** La tentación era que `/imagen`
    // continuara solo cuando ya hubiera una, pero eso hace que la misma frase
    // signifique cosas distintas según lo que pasó antes — y lo que está en
    // juego es una imagen que se paga.
    test('editar es otro atajo, y no se confunde con el de crear', () {
      expect(
        LoQueSePideDibujar.loQueSeCambia('/edita ponle fondo azul'),
        'ponle fondo azul',
      );
      expect(
        LoQueSePideDibujar.loQueSeCambia('/editar más grande'),
        'más grande',
      );

      // Cada uno reconoce lo suyo y solo lo suyo.
      expect(LoQueSePideDibujar.deLaFrase('/edita ponle fondo azul'), isNull);
      expect(LoQueSePideDibujar.loQueSeCambia('/imagen un zorro'), isNull);
    });

    test('el nombre del archivo sale de lo que pediste', () {
      final nombre = LoQueSePideDibujar.nombrePara(
        'Un zorro naranja leyendo un libro, estilo plano',
        DateTime(2026, 8, 31, 9, 5, 7),
      );

      expect(nombre, '20260831-090507-un-zorro-naranja-leyendo-un.png');
    });
  });

  // 🔴 Reportado esperando delante de la pantalla: la petición se agotó a los
  // 90 s y el `TimeoutException` no lo cogía ningún `catch` — se escapaba del
  // data source, del proveedor y del controlador, y como nadie esperaba ese
  // futuro, el orbe se quedaba girando **para siempre** sin decir nada.
  //
  // Lo que se prueba es la promesa que faltaba: **de aquí siempre sale una
  // respuesta**, salga lo que salga por dentro.
  group('cuando la llamada no llega a ninguna parte', () {
    test('sin llave se dice, y no se sale a la red', () async {
      final hecha = await const GeminiImageDataSource().generar(
        llave: '',
        modelo: ModeloDeImagen.nanoBanana2.id,
        descripcion: 'lo que sea',
      );

      expect(hecha.salio, isFalse);
      expect(hecha.problema, 'falta la llave');
    });

    test('un host que no existe se cuenta, no se cuelga', () async {
      // Contra una dirección que no resuelve: el camino de fallo entero, con
      // su tope, sin depender de que haya red ni de gastar un céntimo.
      final hecha = await const GeminiImageDataSource()
          .generar(
            llave: 'la-que-sea',
            modelo: ModeloDeImagen.nanoBanana2.id,
            descripcion: 'lo que sea',
            timeout: const Duration(seconds: 5),
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw StateError('se colgó: eso es justo el fallo'),
          );

      expect(hecha.salio, isFalse);
      expect(hecha.problema, isNotNull);
    }, skip: 'sale a la red: se deja escrito para correrlo a mano');
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

    // Sin esto no hay encadenado: es lo que se manda como
    // `previous_interaction_id` para cambiar la anterior sin resubir el PNG.
    test('trae el id de la interacción, que es lo que permite editarla', () {
      final hecha = GeminiImageDataSource.leerLaImagen(
        respuestaCon({
          'id': 'int_abc123',
          'output_image': {
            'data': base64Encode([1]),
            'mime_type': 'image/png',
          },
        }),
      );

      expect(hecha.id, 'int_abc123');
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
