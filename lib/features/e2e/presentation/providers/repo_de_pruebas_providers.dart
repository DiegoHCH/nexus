import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/repo_de_pruebas_data_source.dart';
import '../../domain/entities/cuenta_de_pruebas.dart';
import '../../domain/usecases/donde_vive_el_repo_de_pruebas.dart';
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
  static const _key = 'pruebas.cuentas';

  late final Future<void> cargadas;

  @override
  List<CuentaDePruebas> build() {
    cargadas = _cargar().catchError((Object _) {});
    return const [];
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_key);
    if (crudo == null || crudo.isEmpty) return;
    state = LasCuentasDePrueba.deJson(jsonDecode(crudo));
  }

  Future<void> _guardar(List<CuentaDePruebas> cuentas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(LasCuentasDePrueba.aJson(cuentas)));
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
    NotifierProvider<CuentasDePrueba, List<CuentaDePruebas>>(
      CuentasDePrueba.new,
    );

/// El clon, listo para usar. **Es lo que hace que la conexión sea automática**:
/// quien pida esto se encuentra el repo clonado y al día sin haber hecho nada.
final clonDelRepoProvider = FutureProvider<ResultadoDeSync>((ref) async {
  final slugs = ref.watch(slugDelRepoDePruebasProvider.notifier);
  await slugs.cargada;
  final soporte = await getApplicationSupportDirectory();
  return ref
      .watch(repoDePruebasDataSourceProvider)
      .asegurar(soporte: soporte.path, slug: ref.watch(slugDelRepoDePruebasProvider));
});

/// Los flows del repo, como rutas relativas. Vacío mientras no haya clon.
final flowsDelRepoProvider = FutureProvider<List<String>>((ref) async {
  final sync = await ref.watch(clonDelRepoProvider.future);
  final clon = sync.clon;
  if (clon == null) return const [];
  return ref.watch(repoDePruebasDataSourceProvider).flows(clon);
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

final cuentaDelFlowProvider = FutureProvider.family<QueCuentaLeToca, String>((
  ref,
  ruta,
) async {
  await ref.watch(cuentasDePruebaProvider.notifier).cargadas;
  final cuentas = ref.watch(cuentasDePruebaProvider);
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
      : ref
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
