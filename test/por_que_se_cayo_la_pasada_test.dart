import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/domain/usecases/la_pasada_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/por_que_se_cayo.dart';

/// Traducir un fallo de dispositivo a una frase con el siguiente paso dentro.
///
/// **Las dos salidas de aquí son capturas reales de un POCO F6 con HyperOS.** Las dos
/// llegaron con el mensaje de la excepción vacío, que es justo el motivo de que esto
/// exista: la traza dice dónde se rompió y nada más, y `adb install` a mano tampoco
/// dice nada.
void main() {
  group('el driver que no se puede instalar', () {
    // `AndroidOperationFailedException: ` — sí, sin texto detrás.
    const salida =
        'The stack trace was:\n'
        'maestro.android.AndroidOperationFailedException: \n'
        '    at maestro.android.AndroidDeviceConnectionModelKt.orThrowOnFailure'
        '(AndroidDeviceConnectionModel.kt:138)\n'
        '    at maestro.drivers.AndroidDriver.install(AndroidDriver.kt:1309)\n'
        '    at maestro.drivers.AndroidDriver.installMaestroDriverApp'
        '(AndroidDriver.kt:1242)\n'
        '    at maestro.drivers.AndroidDriver.installMaestroApks'
        '(AndroidDriver.kt:1273)\n';

    test('se reconoce por la pila, que es lo único que dice algo', () {
      expect(
        PorQueSeCayoLaPasada.de(salida),
        PorQueSeCayo.driverNoSeInstala,
      );
    });
  });

  group('el dispositivo que no deja tocar', () {
    const salida =
        "Tap on id: btn_go_to_login...maestro.android.DeviceCallFailedException: "
        "'tap' failed: INTERNAL - Injecting input events requires the caller "
        '(or the source of the instrumentation, if any) to have the '
        'INJECT_EVENTS permission.\n';

    test('se reconoce, y no se confunde con el del driver', () {
      // Este pasa **dentro** de un paso; el del driver, antes de cualquiera. Así
      // que no compiten.
      expect(
        PorQueSeCayoLaPasada.de(salida),
        PorQueSeCayo.sinPermisoParaTocar,
      );
    });
  });

  test('la app que no está', () {
    expect(
      PorQueSeCayoLaPasada.de('Package com.ejemplo is not installed'),
      PorQueSeCayo.appNoInstalada,
    );
  });

  test('lo que no se reconoce se queda sin frase', () {
    // No reconocer no puede ser peor que antes: se sigue enseñando la salida cruda.
    expect(PorQueSeCayoLaPasada.de('algo que nunca hemos visto'), isNull);
    expect(PorQueSeCayoLaPasada.de(''), isNull);
  });

  group('cómo se enseña', () {
    String pagina({String? diagnostico}) => LaPasadaComoHtml.escribe(
      flow: 'login',
      pasos: const [
        PasoParaPintar(texto: 'launchApp', estado: EstadoDePaso.pendiente),
      ],
      lineas: const ['maestro.android.AndroidOperationFailedException: '],
      terminados: 0,
      viva: false,
      fallo: true,
      diagnostico: diagnostico,
    );

    test('va arriba, antes de los pasos y de la salida', () {
      // Es lo primero que se busca, y compite con veinte líneas de traza que no
      // dicen nada.
      final html = pagina(diagnostico: 'Hace falta Instalar vía USB');

      expect(html, contains('class="motivo"'));
      expect(
        html.indexOf('class="motivo"') < html.indexOf('<ol>'),
        isTrue,
        reason: 'el motivo salió después de los pasos',
      );
    });

    test('sin motivo reconocido no se pinta el hueco', () {
      expect(pagina(), isNot(contains('class="motivo"')));
    });

    test('el texto se escapa como todo lo demás', () {
      expect(pagina(diagnostico: '<b>ojo</b>'), contains('&lt;b&gt;'));
    });
  });
}
