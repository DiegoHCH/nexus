import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/usecases/el_espejo_del_iphone.dart';

final emuladoresDataSourceProvider = Provider<EmuladoresDataSource>(
  (ref) => const EmuladoresDataSource(),
);

/// Los emuladores de la máquina y su estado.
///
/// **Sin `autoDispose`, y eso es el arreglo de un fallo reportado**: con él, cada
/// vez que se salía de la sección y se volvía la lista desaparecía para cargarse
/// otra vez, y son ~1,2 s de pantalla vacía cada visita. Guardando el valor, al
/// volver está puesto **al instante** y el refresco pasa por detrás.
///
/// Que se guarde no significa que se crea: la sección pide un refresco cada vez
/// que se abre. Lo que cambia es que mientras llega se enseña lo último que se
/// supo en vez de nada — el estado viejo de un emulador es una aproximación
/// razonable de un segundo; una pantalla en blanco no es aproximación de nada.
///
/// El intento anterior fue `autoDispose`, y venía de arreglar lo contrario: un
/// `FutureProvider` normal calcula una vez y no vuelve a preguntar, así que
/// arrancar un emulador por fuera dejaba la lista mintiendo para siempre. Las dos
/// cosas se arreglan juntas guardando el valor **y** refrescando al abrir; con
/// una sola de las dos se elige entre mentir o parpadear.
final emuladoresProvider =
    FutureProvider<({List<Emulador> emuladores, String? error})>(
      (ref) => ref.watch(emuladoresDataSourceProvider).listar(),
    );

/// Los teléfonos de verdad enchufados.
///
/// **Aparte y no en el mismo provider, porque cuesta seis veces más**: son ~7 s
/// de `flutter devices --machine` contra ~1,2 s de todo lo demás. Juntos hacían
/// esperar por un iPhone a quien venía a arrancar un emulador.
///
/// Aquí también se guarda el valor: al volver a la sección los teléfonos siguen
/// puestos, y solo la primera visita de la sesión los ve aparecer con retraso.
final dispositivosProvider = FutureProvider<List<DispositivoConectado>>(
  (ref) => ref.watch(emuladoresDataSourceProvider).listarDispositivos(),
);

/// Si se puede ofrecer ver la pantalla: **hace falta scrcpy instalado**.
///
/// Es opcional a propósito. Un botón que solo puede fallar es peor que no tenerlo,
/// así que sin el binario no se pinta — el mismo criterio que con Maestro.
final hayEspejoProvider = Provider<bool>(
  (ref) => ref.watch(emuladoresDataSourceProvider).hayEspejo(),
);

/// Si a *este* dispositivo se le puede ver la pantalla.
///
/// **Solo móviles físicos Android**, y las dos condiciones son por motivos
/// distintos: un emulador ya tiene su propia ventana, así que duplicarla no aporta
/// nada; y scrcpy no habla con iOS, así que en un iPhone el botón solo podría
/// fallar.
///
/// Vive aquí y no en cada pantalla porque lo preguntan dos paneles, y ya me ha
/// pasado hoy que un criterio calculado en dos sitios se separa en cuanto uno cambia.
final sePuedeVerLaPantallaProvider = Provider.family<bool, String>((ref, id) {
  if (!ref.watch(hayEspejoProvider)) return false;
  return ref
      .watch(dispositivosProvider)
      .value
      ?.any((d) => d.id == id && d.plataforma == PlataformaEmulador.android) ??
      false;
});

/// Cómo se puede ver *este* dispositivo, si es un iPhone físico.
///
/// Vacío para cualquier otra cosa. Y **esto no se ofrece en el panel de pruebas**:
/// Maestro no maneja un iPhone físico, solo simuladores, así que un espejo de iOS
/// sirve para mirar y no para probar.
final comoVerElIphoneProvider = Provider.family<List<ComoVerElIphone>, String>((
  ref,
  id,
) {
  final esIphone =
      ref
          .watch(dispositivosProvider)
          .value
          ?.any((d) => d.id == id && d.plataforma == PlataformaEmulador.ios) ??
      false;
  if (!esIphone) return const [];
  return ref.watch(emuladoresDataSourceProvider).comoVerElIphone();
});
