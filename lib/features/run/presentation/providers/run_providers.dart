import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// La configuración con la que se corre cada proyecto cuando no se dice nada.
///
/// **Un mapa de proyecto a nombre, y no una preferencia global.** Con catorce
/// configuraciones —las que tiene un proyecto real de los que se miraron para
/// esto— elegir a mano en cada arranque es un peaje diario; y una sola
/// preferencia para todo sería peor que ninguna, porque pondría el flavor de un
/// repo como cabeza de otro.
///
/// Se recuerda el **nombre** y no un índice: los índices bailan en cuanto alguien
/// añade una configuración al `launch.json`, y el día que bailen estarías
/// corriendo otro entorno sin enterarte. Un nombre que ya no exista simplemente
/// no se ofrece.
///
/// Un notifier con el mapa entero en vez de una familia: la familia obligaría a
/// leer el disco una vez por proyecto y a mantener tantas entradas vivas como
/// carpetas emparejadas, para guardar una cadena por cada una.
class ConfigsPorDefecto extends Notifier<Map<String, String>> {
  static const _clave = 'run.configPorDefecto';

  @override
  Map<String, String> build() {
    _cargar();
    return const {};
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_clave);
    if (guardado == null || guardado.isEmpty) return;
    try {
      final leido = jsonDecode(guardado);
      if (leido is Map) {
        state = {for (final e in leido.entries) '${e.key}': '${e.value}'};
      }
    } on FormatException {
      // Una preferencia corrupta no puede impedir abrir el menú: se empieza de
      // cero y la próxima elección la arregla.
    }
  }

  Future<void> elegir(String proyecto, String nombre) async {
    state = {...state, proyecto: nombre};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, jsonEncode(state));
  }
}

final configsPorDefectoProvider =
    NotifierProvider<ConfigsPorDefecto, Map<String, String>>(
      ConfigsPorDefecto.new,
    );
