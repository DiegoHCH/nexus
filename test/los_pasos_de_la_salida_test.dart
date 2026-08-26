import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';

/// Los pasos leídos de la salida de Maestro.
///
/// **El texto de estas pruebas es una captura real**, con los trozos tal como
/// llegaron —medidos con marcas de tiempo— y no una imitación. Lo que se estaba
/// perdiendo era justo lo que una imitación bien formada no habría reproducido: el
/// anuncio del paso llega sin salto de línea, y el resultado viene pegado al
/// anuncio del siguiente.
void main() {
  group('un paso en curso', () {
    test('el anuncio sin salto de línea ya es un paso corriendo', () {
      // 29.76s  b'Launch app "com.global66.cards.ci"...'
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Running on Medium_Phone_API_36.1\n'
        ' > Flow welcome_to_login\n'
        'Launch app "com.global66.cards.ci"...',
      );

      expect(pasos.length, 1);
      expect(pasos.single.texto, 'Launch app "com.global66.cards.ci"');
      expect(pasos.single.estado, EstadoDePaso.enCurso);
    });

    test('el resultado y el anuncio del siguiente llegan pegados', () {
      // 44.94s  b' COMPLETED\nAssert that id: btn_go_to_register is visible...'
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Launch app "com.ejemplo"... COMPLETED\n'
        'Assert that id: btn_go_to_register is visible...',
      );

      expect(pasos.map((p) => p.estado), [
        EstadoDePaso.hecho,
        EstadoDePaso.enCurso,
      ]);
      expect(pasos.last.texto, 'Assert that id: btn_go_to_register is visible');
    });
  });

  group('lo que no es un paso', () {
    test('la cabecera no cuenta', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Running on Medium_Phone_API_36.1\n > Flow welcome_to_login\n',
      );
      expect(pasos, isEmpty);
    });

    test('«Waiting for flows to complete...» acaba en tres puntos y no es un paso', () {
      // Es la trampa de este parseo: tiene la misma forma que el anuncio de un
      // paso, así que sin la lista se pintaría como uno.
      final pasos = PasosDeUnaPrueba.deLaSalida('Waiting for flows to complete...');
      expect(pasos, isEmpty);
    });

    test('el resumen del final tampoco', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(
        '[Passed] welcome_to_login (20s)\n\n1/1 Flow Passed in 20s\n',
      );
      expect(pasos, isEmpty);
    });
  });

  group('cómo acabó', () {
    test('un paso que falla se marca fallado', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Tap on id: btn_go_to_login... FAILED\n',
      );
      expect(pasos.single.estado, EstadoDePaso.fallado);
      expect(pasos.single.texto, 'Tap on id: btn_go_to_login');
    });

    test('una corrida entera, en orden', () {
      // La captura completa de la corrida de hoy.
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Running on Medium_Phone_API_36.1\n'
        ' > Flow welcome_to_login\n'
        'Launch app "com.global66.cards.ci"... COMPLETED\n'
        'Assert that id: btn_go_to_register is visible... COMPLETED\n'
        'Assert that id: btn_go_to_login is visible... COMPLETED\n'
        'Tap on id: btn_go_to_login... COMPLETED\n'
        'Assert that id: textfield_login_email is visible... COMPLETED\n'
        'Assert that id: textfield_login_password is visible... COMPLETED\n'
        'Assert that id: btn_link_to_restore_password is visible... COMPLETED\n'
        'Take screenshot login_form... COMPLETED\n',
      );

      expect(pasos.length, 8);
      expect(pasos.every((p) => p.estado == EstadoDePaso.hecho), isTrue);
      expect(pasos.first.texto, 'Launch app "com.global66.cards.ci"');
      expect(pasos.last.texto, 'Take screenshot login_form');
    });
  });

  group('las dos fuentes juntas', () {
    final delFlow = [
      PasoDelFlow(linea: 3, texto: '- launchApp'.substring(2)),
      PasoDelFlow(linea: 4, texto: 'extendedWaitUntil:', detalle: ['    visible:']),
      PasoDelFlow(linea: 7, texto: 'tapOn:', detalle: ['    id: "btn"']),
    ];

    test('lo corrido en prosa, lo que falta como está escrito', () {
      final pasos = PasosDeUnaPrueba.paraPintar(
        salida: 'Launch app "com.ejemplo"... COMPLETED\n',
        delFlow: delFlow,
      );

      expect(pasos.length, 3);
      // El ejecutado, con la frase de Maestro y no con el YAML.
      expect(pasos[0].texto, 'Launch app "com.ejemplo"');
      expect(pasos[0].estado, EstadoDePaso.hecho);
      // Lo que falta, tal como está en el archivo, con su detalle.
      expect(pasos[1].texto, 'extendedWaitUntil:');
      expect(pasos[1].estado, EstadoDePaso.pendiente);
      expect(pasos[1].detalle, ['    visible:']);
    });

    test('sin salida todavía, todo pendiente y del archivo', () {
      final pasos = PasosDeUnaPrueba.paraPintar(salida: '', delFlow: delFlow);
      expect(pasos.length, 3);
      expect(pasos.every((p) => p.estado == EstadoDePaso.pendiente), isTrue);
    });

    test('si lo ejecutado pasa del archivo, manda la salida y no se degrada', () {
      // El caso que antes devolvía `null` y obligaba a enseñar la salida cruda: un
      // `runFlow` o un bucle ejecutan más pasos de los que tiene el archivo.
      final pasos = PasosDeUnaPrueba.paraPintar(
        salida: [
          for (var i = 0; i < 5; i++) 'Tap on id: fila_$i... COMPLETED',
        ].join('\n'),
        delFlow: delFlow,
      );

      expect(pasos.length, 5, reason: 'se quedó con los del archivo');
      expect(pasos.every((p) => p.estado == EstadoDePaso.hecho), isTrue);
    });
  });
}
