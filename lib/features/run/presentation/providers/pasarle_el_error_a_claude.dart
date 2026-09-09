import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/presentation/providers/el_despacho_de_carpeta_impl.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_se_le_pasa.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';

/// Le pasa a Claude el último error de una corrida.
///
/// 🔴 **Cierra el círculo que estaba medio construido.** Nexus ya oye los
/// errores del framework y ya sabe llevar encargos a la carpeta de un proyecto;
/// lo que no había era el paso de uno a otro. El puente entre correr y encargar
/// iba en un solo sentido —al terminar un encargo, la app se recarga— y al
/// revés nada: la app se rompía, lo veías, y arreglarlo pasaba por copiar el
/// bloque a mano.
///
/// **Va al proyecto de la corrida y no a la conversación de delante**, que es
/// la mitad del valor: el error es de ese repo, y llevarlo a la pestaña que
/// tuvieras abierta sería pedirle a Claude que arregle un archivo que no puede
/// ver.
///
/// Devuelve `false` si no había ningún error en el registro — no debería pasar,
/// porque el botón solo existe cuando la corrida cuenta alguno, pero el
/// registro tiene tope de líneas y el error podría haberse ido por arriba.
final pasarleElErrorAClaudeProvider =
    Provider<Future<bool> Function(Corrida corrida)>(
      (ref) => (corrida) async {
        final lineas =
            ref.read(registrosProvider)[corrida.deviceId] ?? const [];
        final bloque = ElErrorQueSeLePasa.deLasLineas(lineas);
        if (bloque == null) return false;

        final strings = ref.read(stringsProvider);
        await ref
            .read(elDespachoDeCarpetaProvider)
            .aEstaCarpeta(
              corrida.proyecto,
              tarea: ElErrorQueSeLePasa.elEncargo(
                peticion: strings.elErrorDeLaApp(
                  corrida.configuracion,
                  corrida.dispositivo,
                ),
                bloque: bloque,
              ),
              // En la conversación se ve una línea y no la traza entera: lo que se
              // pidió se lee de un vistazo, y el bloque ya está en el encargo.
              loQueSeVe: strings.elErrorDeLaAppEnCorto,
            );
        return true;
      },
    );
