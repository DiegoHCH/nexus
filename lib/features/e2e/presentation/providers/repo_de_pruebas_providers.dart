import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/repo_de_pruebas_data_source.dart';
import '../../domain/entities/cuenta_de_pruebas.dart';
import '../../domain/usecases/donde_vive_el_repo_de_pruebas.dart';
import '../../domain/usecases/como_se_agrupan_los_flows.dart';
import '../../domain/usecases/el_arbol_de_un_flow.dart';
import '../../domain/usecases/las_cuentas_de_prueba.dart';
import '../../domain/usecases/las_variables_del_proyecto.dart';

final repoDePruebasDataSourceProvider = Provider<RepoDePruebasDataSource>(
  (ref) => const RepoDePruebasDataSource(),
);

/// Qué repo de pruebas se usa. Se guarda para poder cambiarlo sin tocar código:
/// hoy es el de `front-mobile-b2c`, mañana puede haber otro para otra app.
class SlugDelRepoDePruebas extends Notifier<String> {
  static const _key = 'pruebas.repo.slug';

  late final Future<void> cargada;

  @override
  String build() {
    cargada = _cargar().catchError((Object _) {});
    return DondeViveElRepoDePruebas.slugPorDefecto;
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_key);
    if (guardado != null && guardado.trim().isNotEmpty) state = guardado.trim();
  }

  Future<void> elegir(String slug) async {
    final limpio = slug.trim();
    // Un slug sin barra no es un repo de GitHub y clonarlo falla con un error que
    // no se entiende. Se rechaza aquí, donde se puede decir por qué.
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(limpio)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, limpio);
    state = limpio;
    // Cambiar de repo sí obliga a volver a clonar. Se invalida aquí, a mano,
    // porque `clonDelRepoProvider` dejó de observar este valor a propósito.
    ref.invalidate(clonDelRepoProvider);
  }
}

final slugDelRepoDePruebasProvider =
    NotifierProvider<SlugDelRepoDePruebas, String>(SlugDelRepoDePruebas.new);

/// Las cuentas de prueba configuradas, en orden. **La primera es la de por
/// defecto**: se lleva los flows sin tag y los `acct-any`.
///
/// 🔴 Guardadas en las preferencias de la app y **nunca dentro del clon**. Llevan
/// contraseñas y PINs; el clon es de donde se empuja.
class CuentasDePrueba extends Notifier<List<CuentaDePruebas>> {
  CuentasDePrueba(this.proyecto);

  /// El repo al que pertenecen. Es la ruta, no el nombre: dos proyectos pueden
  /// llamarse igual y compartir cuentas sería justo el fallo que esto evita.
  final String proyecto;

  /// La clave vieja, de cuando las cuentas eran globales. Ver [_cargar].
  static const _keyVieja = 'pruebas.cuentas';

  static String _keyDe(String proyecto) => 'pruebas.cuentas.$proyecto';

  late final Future<void> cargadas;

  @override
  List<CuentaDePruebas> build() {
    cargadas = _cargar(proyecto).catchError((Object _) {});
    return const [];
  }

  /// 🔴 **Las cuentas cuelgan del proyecto.** Una cuenta de `front-mobile-b2c` no
  /// sirve para otro repo: son credenciales de una app concreta, y ofrecerlas en
  /// otro sitio invita a correr una prueba con la cuenta de otra cosa — que no da
  /// un error, da un rojo que parece una regresión.
  ///
  /// **Adopción de las globales, una sola vez.** Las que se guardaron cuando esto
  /// no tenía alcance viven en [_keyVieja]. Se las queda el primer proyecto que
  /// pregunte y la clave vieja se borra: copiarlas a todos las repartiría por
  /// proyectos que no son suyos, y tirarlas obligaría a reescribir credenciales
  /// que alguien ya tecleó.
  Future<void> _cargar(String proyecto) async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_keyDe(proyecto));
    if (crudo != null && crudo.isNotEmpty) {
      state = LasCuentasDePrueba.deJson(jsonDecode(crudo));
      return;
    }
    final heredado = prefs.getString(_keyVieja);
    if (heredado == null || heredado.isEmpty) return;
    await prefs.setString(_keyDe(proyecto), heredado);
    await prefs.remove(_keyVieja);
    state = LasCuentasDePrueba.deJson(jsonDecode(heredado));
  }

  Future<void> _guardar(List<CuentaDePruebas> cuentas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyDe(proyecto),
      jsonEncode(LasCuentasDePrueba.aJson(cuentas)),
    );
    state = cuentas;
  }

  /// Añade o reemplaza por clave. Reemplazar y no duplicar porque la clave es la
  /// identidad: dos `pe` romperían el reparto en silencio.
  Future<void> guardar(CuentaDePruebas cuenta) async {
    final i = state.indexWhere((c) => c.clave == cuenta.clave);
    final cuentas = [...state];
    if (i < 0) {
      cuentas.add(cuenta);
    } else {
      cuentas[i] = cuenta;
    }
    await _guardar(cuentas);
  }

  Future<void> borrar(String clave) async =>
      _guardar([...state.where((c) => c.clave != clave)]);

  /// Mueve una cuenta al principio, o sea: la hace la de por defecto.
  Future<void> hacerPorDefecto(String clave) async {
    final cuenta = state.where((c) => c.clave == clave).firstOrNull;
    if (cuenta == null) return;
    await _guardar([cuenta, ...state.where((c) => c.clave != clave)]);
  }
}

final cuentasDePruebaProvider =
    NotifierProvider.family<CuentasDePrueba, List<CuentaDePruebas>, String>(
      CuentasDePrueba.new,
    );

/// El clon, listo para usar. **Es lo que hace que la conexión sea automática**:
/// quien pida esto se encuentra el repo clonado y al día sin haber hecho nada.
///
/// 🔴 **El slug se lee con `read` y no con `watch`, y eso es el arreglo de un
/// cuelgue.** Con `watch`, este provider dependía del valor: el notifier arranca
/// con el de por defecto, `_cargar()` lo cambia al guardado, y eso disparaba
/// `asegurar()` **una segunda vez** en cada arranque — otro `git fetch` y otro
/// `reset --hard`—. Y cada recálculo invalida los 57 `flowDelRepo` y los 57
/// `cuentaDelFlow`, o sea las 300 lecturas de archivo otra vez. El coste no era
/// el doble: era el doble de todo lo que cuelga de él.
///
/// La reactividad no se pierde: [SlugDelRepoDePruebas.elegir] invalida esto a
/// mano cuando alguien cambia el repo de verdad, que es la única vez que hay que
/// volver a clonar.
final clonDelRepoProvider = FutureProvider<ResultadoDeSync>((ref) async {
  final slugs = ref.watch(slugDelRepoDePruebasProvider.notifier);
  await slugs.cargada;
  final soporte = await getApplicationSupportDirectory();
  return ref
      .read(repoDePruebasDataSourceProvider)
      .asegurar(soporte: soporte.path, slug: ref.read(slugDelRepoDePruebasProvider));
});

/// Los flows del repo, como rutas relativas. Vacío mientras no haya clon.
final flowsDelRepoProvider = FutureProvider<List<String>>((ref) async {
  final sync = await ref.watch(clonDelRepoProvider.future);
  final clon = sync.clon;
  if (clon == null) return const [];
  return ref.watch(repoDePruebasDataSourceProvider).flows(clon);
});

/// Las rutas que **otros** flows incluyen con `runFlow`: las piezas.
///
/// Cuesta una lectura por flow, una sola vez —57 hoy—, y es lo que permite sacar
/// de la lista de pruebas siete cosas que no se lanzan sueltas. Por uso y no por
/// carpeta: ver [ComoSeAgrupanLosFlows].
final piezasDelRepoProvider = FutureProvider<Set<String>>((ref) async {
  final sync = await ref.watch(clonDelRepoProvider.future);
  final clon = sync.clon;
  if (clon == null) return const {};

  final ds = ref.watch(repoDePruebasDataSourceProvider);
  final referencias = <String, List<String>>{};
  for (final ruta in await ref.watch(flowsDelRepoProvider.future)) {
    final contenido = await ds.leer(clon: clon, ruta: ruta);
    if (contenido != null) {
      referencias[ruta] = ElArbolDeUnFlow.referencias(contenido);
    }
  }
  return ComoSeAgrupanLosFlows.piezasDe(referenciasPorFlow: referencias);
});

/// El contenido de un flow del repo.
final flowDelRepoProvider = FutureProvider.family<String?, String>((
  ref,
  ruta,
) async {
  final sync = await ref.watch(clonDelRepoProvider.future);
  final clon = sync.clon;
  if (clon == null) return null;
  return ref.watch(repoDePruebasDataSourceProvider).leer(clon: clon, ruta: ruta);
});

/// Con qué cuenta hay que correr un flow, y qué falta si no se puede decidir.
class QueCuentaLeToca {
  const QueCuentaLeToca({
    this.cuenta,
    this.sinCubrir = const {},
    this.faltan = const [],
  });

  final CuentaDePruebas? cuenta;

  /// Las claves de cuenta que el flow pide y ninguna configurada cubre.
  final Set<String> sinCubrir;

  /// 🔴 Las variables que el flow **y sus subflows** nombran y la cuenta no
  /// tiene. Solo los nombres, nunca los valores.
  ///
  /// Sin esto, una que falte se convierte en el fallo desconcertante que
  /// `LasVariablesDelProyecto.faltan` ya describe: Maestro recibe el literal
  /// `${APP_ID}`, intenta lanzar una app con ese nombre y contesta que no está
  /// instalada. Un mensaje correcto sobre un síntoma equivocado, y el dev se va a
  /// mirar el dispositivo. Medido el 2026-08-27, con esa variable exacta.
  final List<String> faltan;

  /// Si se puede lanzar. Una variable que falta no es un aviso: es la pasada
  /// perdida y quince minutos buscando en el sitio que no era.
  bool get sePuede => cuenta != null && faltan.isEmpty;

  /// Por qué no se puede correr, o `null` si sí se puede.
  String? get porQueNo {
    if (cuenta == null) {
      if (sinCubrir.isNotEmpty) {
        final claves = (sinCubrir.toList()..sort()).join(', ');
        return 'Este flow pide la cuenta «$claves» y no tienes ninguna con esa etiqueta.';
      }
      return 'No hay ninguna cuenta de prueba configurada.';
    }
    if (faltan.isNotEmpty) {
      return 'A la cuenta «${cuenta!.clave}» le faltan: ${faltan.join(', ')}.';
    }
    return null;
  }
}

/// Qué flow, y con las cuentas de qué proyecto. Los flows del repo compartido son
/// las pruebas del proyecto emparejado, así que corren con **sus** cuentas y no
/// con unas propias: configurar las credenciales de b2c dos veces —una para sus
/// pruebas locales y otra para las del repo— es la clase de duplicado que acaba
/// con las dos copias distintas.
typedef FlowDeProyecto = ({String proyecto, String ruta});

final cuentaDelFlowProvider =
    FutureProvider.family<QueCuentaLeToca, FlowDeProyecto>((ref, cual) async {
  final (:proyecto, :ruta) = cual;
  await ref.watch(cuentasDePruebaProvider(proyecto).notifier).cargadas;
  final cuentas = ref.watch(cuentasDePruebaProvider(proyecto));
  final contenido = await ref.watch(flowDelRepoProvider(ruta).future);
  if (contenido == null) return const QueCuentaLeToca();

  // Las etiquetas salen del flow **propio** —las de un subflow no son suyas—,
  // pero las variables salen del árbol entero, que es donde viven.
  final cuenta = LasCuentasDePrueba.paraElFlow(
    contenido: contenido,
    cuentas: cuentas,
  );
  final sync = await ref.watch(clonDelRepoProvider.future);
  final arbol = sync.clon == null
      ? contenido
      : await ref
            .watch(repoDePruebasDataSourceProvider)
            .arbolDe(clon: sync.clon!, ruta: ruta);

  return QueCuentaLeToca(
    cuenta: cuenta,
    sinCubrir: LasCuentasDePrueba.sinCubrir(contenido: contenido, cuentas: cuentas),
    faltan: cuenta == null
        ? const []
        : LasVariablesDelProyecto.faltan(
            yaml: arbol,
            tiene: cuenta.variables.entries
                .where((e) => e.value.isNotEmpty)
                .map((e) => e.key)
                .toSet(),
          ),
  );
});
