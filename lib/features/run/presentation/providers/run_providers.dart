import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/run/data/datasources/configs_data_source.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';

final configsDataSourceProvider = Provider<ConfigsDataSource>(
  (ref) => const ConfigsDataSource(),
);

/// Las configuraciones de arranque de **un** proyecto.
///
/// **Una familia con la carpeta como clave, y no una lista global.** Las
/// configuraciones pertenecen al proyecto que las declara: nombran su flavor, su
/// archivo de `--dart-define` y a veces una ruta suya. Una lista compartida
/// dejaría elegir la de un repo para correr otro, y el fallo llegaría tres
/// minutos después en forma de compilación rota.
///
/// La clave es la **carpeta de trabajo** y no la emparejada, por lo mismo que la
/// rama que se enseña en el compositor: con una raíz de varios repos, el proyecto
/// que se corre es el repo elegido y no la carpeta de arriba.
///
/// Sin `autoDispose` y sin refresco automático, a diferencia de los dispositivos:
/// un `launch.json` lo cambia una persona editando el archivo, no la máquina por
/// su cuenta. Se invalida cuando cambie de proyecto o cuando alguien lo pida.
final configsProvider =
    FutureProvider.family<List<ConfigDeArranque>, String>(
      (ref, proyecto) =>
          ref.watch(configsDataSourceProvider).deProyecto(proyecto),
    );
