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

  group('un paso que revienta', () {
    /// La salida de una corrida real en un móvil físico, tal como llegó. El `tap`
    /// murió por permisos de MIUI y **Maestro no imprimió ningún estado**: le pegó la
    /// excepción al anuncio, en la misma línea.
    const deVerdad =
        'Running on 36c56d94\n'
        ' > Flow welcome_to_login\n'
        'Launch app "com.global66.cards.ci"... COMPLETED\n'
        'Assert that id: btn_go_to_register is visible... COMPLETED\n'
        'Assert that id: btn_go_to_login is visible... COMPLETED\n'
        "Tap on id: btn_go_to_login...maestro.android.DeviceCallFailedException: "
        "'tap' failed: INTERNAL - Injecting input events requires the caller "
        '(or the source of the instrumentation, if any) to have the '
        'INJECT_EVENTS permission.\n'
        '  error-type=java.lang.SecurityException\n'
        '    at maestro.android.AndroidDeviceConnectionModelKt.orThrow'
        '(AndroidDeviceConnectionModel.kt:79)\n';

    test('se marca fallado, no se descarta', () {
      // Antes esta línea no acababa en `COMPLETED`, `FAILED` ni `...`, así que se
      // tiraba entera: el paso que había fallado salía sin marca y los siguientes se
      // caían al texto del archivo. La etiqueta decía «Error» y la lista no decía
      // dónde.
      final pasos = PasosDeUnaPrueba.deLaSalida(deVerdad);

      expect(pasos.length, 4);
      expect(pasos[3].texto, 'Tap on id: btn_go_to_login');
      expect(pasos[3].estado, EstadoDePaso.fallado);
    });

    test('el motivo se enseña con el paso', () {
      // Es lo único que se busca cuando algo se rompe.
      final pasos = PasosDeUnaPrueba.deLaSalida(deVerdad);

      expect(pasos[3].detalle.single, contains('INJECT_EVENTS'));
    });

    test('los tres anteriores siguen en verde', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(deVerdad);
      expect(
        pasos.take(3).every((p) => p.estado == EstadoDePaso.hecho),
        isTrue,
      );
    });

    test('la traza no se cuela como pasos sueltos', () {
      // `error-type=…` y los `at maestro.…` no llevan tres puntos, así que no pasan
      // el filtro. Siguen estando en la salida cruda, que es donde se leen.
      final pasos = PasosDeUnaPrueba.deLaSalida(deVerdad);
      expect(pasos.where((p) => p.texto.startsWith('at ')), isEmpty);
      expect(pasos.where((p) => p.texto.contains('error-type')), isEmpty);
    });

    test('lo que falta del archivo se sigue enseñando detrás', () {
      final pasos = PasosDeUnaPrueba.paraPintar(
        salida: deVerdad,
        delFlow: [
          for (var i = 0; i < 8; i++) PasoDelFlow(linea: i + 3, texto: 'paso $i'),
        ],
      );

      expect(pasos.length, 8);
      expect(pasos[3].estado, EstadoDePaso.fallado);
      expect(pasos[4].estado, EstadoDePaso.pendiente);
    });
  });

  group('un flujo anidado', () {
    /// Captura real de la corrida del login: un `runFlow` condicional se imprime en
    /// tres tramos —anuncio, pasos de dentro indentados, y **otra vez el mismo
    /// `runFlow`** con su resultado—.
    const conRunFlow =
        'Running on 36c56d94\n'
        ' > Flow login\n'
        'Press Enter key... COMPLETED\n'
        'Assert that (Optional) id: input.pin is visible... COMPLETED\n'
        'Run flow when id: input.pin is visible...\n'
        '  Tap on id: btn.pin_keypad_1... COMPLETED\n'
        '  Tap on id: btn.pin_keypad_2... COMPLETED\n'
        'Run flow when id: input.pin is visible... COMPLETED\n';

    test('el anuncio y su cierre son el mismo paso, no dos', () {
      // Lo que se veía: el anuncio girando para siempre —nunca recibe estado en su
      // propia línea— y su cierre como una fila más. Con dos flujos anidados,
      // **tres indicadores a la vez** y la ventana leyéndose como colgada teniendo
      // la corrida acabada.
      final pasos = PasosDeUnaPrueba.deLaSalida(conRunFlow);

      expect(
        pasos.where((p) => p.texto.startsWith('Run flow')).length,
        1,
        reason: 'el runFlow salió dos veces',
      );
      expect(pasos.length, 5);
    });

    test('y ese paso queda hecho, no en curso', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(conRunFlow);
      final flujo = pasos.firstWhere((p) => p.texto.startsWith('Run flow'));

      expect(flujo.estado, EstadoDePaso.hecho);
      expect(
        pasos.where((p) => p.estado == EstadoDePaso.enCurso),
        isEmpty,
        reason: 'quedó algo girando con la corrida acabada',
      );
    });

    test('mientras corre, el anuncio sí es el paso en curso', () {
      // Sin su cierre todavía: ahí sí es lo que está pasando.
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Run flow when id: input.pin is visible...\n'
        '  Tap on id: btn.pin_keypad_1... COMPLETED\n',
      );

      expect(pasos.first.estado, EstadoDePaso.enCurso);
      expect(pasos.length, 2);
    });

    test('dos pasos idénticos seguidos no se confunden entre sí', () {
      // Un PIN con dígitos repetidos toca la misma tecla dos veces. No colisionan
      // porque solo se busca entre los que están en curso, y uno acabado no casa.
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Tap on id: btn.pin_keypad_1... COMPLETED\n'
        'Tap on id: btn.pin_keypad_1... COMPLETED\n',
      );

      expect(pasos.length, 2);
      expect(pasos.every((p) => p.estado == EstadoDePaso.hecho), isTrue);
    });

    test('el paso que revienta dentro de un flujo también cierra su anuncio', () {
      final pasos = PasosDeUnaPrueba.deLaSalida(
        'Run flow when id: input.pin is visible...\n'
        '  Tap on id: btn... COMPLETED\n'
        "Run flow when id: input.pin is visible...maestro.MaestroException: algo\n",
      );

      final flujo = pasos.firstWhere((p) => p.texto.startsWith('Run flow'));
      expect(flujo.estado, EstadoDePaso.fallado);
      expect(pasos.length, 2);
    });
  });
}
