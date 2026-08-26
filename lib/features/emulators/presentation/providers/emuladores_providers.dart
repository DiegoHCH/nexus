import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';

final emuladoresDataSourceProvider = Provider<EmuladoresDataSource>(
  (ref) => const EmuladoresDataSource(),
);

/// Lo que hay en la máquina ahora mismo.
///
/// **`autoDispose`, y esa palabra es el arreglo de un fallo visto en vivo.** Sin
/// ella un `FutureProvider` calcula una vez y guarda el resultado mientras viva
/// el `ProviderScope`, o sea toda la sesión de la app: se abría Ajustes con los
/// emuladores apagados, se arrancaba uno **por fuera**, y la sección seguía
/// diciendo «Arrancar» con el punto gris. Lo reportado fue «está arriba el
/// emulador y no está el punto en verde», que no se parece a un problema de
/// caché.
///
/// Con `autoDispose` el estado se tira al cerrar la sección y se vuelve a
/// preguntar al abrirla, que es lo que la pantalla promete: lo que hay **ahora**.
/// Es el mismo criterio que ya usa `McpPermissions` para leer el archivo en cada
/// encargo en vez de cachearlo — un servidor instalado con la app abierta tiene
/// que entrar en el siguiente sin pedir un reinicio que nadie adivina.
///
/// Cuesta un `flutter emulators`, un `flutter devices` y un par de `adb`. Se
/// paga: la alternativa es una lista que miente.
final emuladoresProvider =
    FutureProvider.autoDispose<
      ({
        List<Emulador> emuladores,
        List<DispositivoConectado> dispositivos,
        String? error,
      })
    >((ref) => ref.watch(emuladoresDataSourceProvider).listar());
