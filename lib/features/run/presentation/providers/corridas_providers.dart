import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/data/datasources/corrida_viva.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/estado_de_la_corrida.dart';

/// Lo que está corriendo, por dispositivo.
///
/// **Un mapa y no una sola corrida**, porque tener la app en dos sitios a la vez
/// es el caso que se quiere: ver el mismo cambio en Android y en iOS sin lanzar
/// dos veces. Lo que no se puede es dos de la misma plataforma — ver
/// [loQueBloquea].
class CorridasController extends Notifier<Map<String, Corrida>> {
  final _vivas = <String, CorridaViva>{};

  /// El progreso llega con ids que se solapan, así que cada corrida lleva su
  /// mapa. Fuera del estado a propósito: es contabilidad del protocolo y no algo
  /// que la pantalla tenga que mirar.
  final _progresos = <String, Map<String, ProgresoDelDaemon>>{};

  @override
  Map<String, Corrida> build() => const {};

  /// Lanza la app. `null` si arrancó; el motivo si no.
  Future<String?> correr({
    required String proyecto,
    required String configuracion,
    required List<String> args,
    required String deviceId,
    required String dispositivo,
    required PlataformaEmulador plataforma,
  }) async {
    if (state.containsKey(deviceId)) {
      return 'Ya está corriendo en ese dispositivo';
    }

    // **Se corta aquí y no al fallar la compilación.** Dos corridas de la misma
    // plataforma comparten el directorio de build y se pisan; enterarse por el
    // error de Gradle cuesta tres minutos y no apunta a su causa.
    if (loQueBloquea(state.values, plataforma) case final otra?) {
      return 'Ya hay una corrida de ${plataforma.name} en ${otra.dispositivo}';
    }

    final flutter = await HerramientaExterna.donde(
      'flutter',
      candidatos: HerramientaExterna.candidatosDeFlutter(
        Platform.environment['HOME'] ?? '',
      ),
    );
    if (flutter == null) return 'No se encontró Flutter';

    state = {
      ...state,
      deviceId: Corrida(
        deviceId: deviceId,
        dispositivo: dispositivo,
        proyecto: proyecto,
        configuracion: configuracion,
        plataforma: plataforma,
      ),
    };

    final viva = await CorridaViva.arrancar(
      flutter: flutter,
      proyecto: proyecto,
      deviceId: deviceId,
      args: args,
      onEvento: (evento) => _aplica(deviceId, evento),
      onRegistro: (linea) =>
          ref.read(registrosProvider.notifier).anota(deviceId, linea),
      onFin: (motivo) => _termina(deviceId, motivo),
    );

    if (viva == null) {
      _termina(deviceId, 'No se pudo lanzar flutter run');
      return 'No se pudo lanzar flutter run';
    }
    _vivas[deviceId] = viva;
    return null;
  }

  /// Recargar. Sin [deviceId] va a **todas** las corridas, que es el sentido de
  /// tener la app en dos sitios: ver el mismo cambio en los dos.
  ///
  /// El resultado es por dispositivo porque una recarga puede fallar en uno y no
  /// en otro, y un «falló» a secas no diría dónde.
  Future<Map<String, ({bool ok, String? error})>> recargar({
    String? deviceId,
    bool completa = false,
  }) async {
    final destinos = deviceId == null
        ? _vivas.keys.toList()
        : [if (_vivas.containsKey(deviceId)) deviceId];

    final resultados = <String, ({bool ok, String? error})>{};
    for (final id in destinos) {
      resultados[id] = await _vivas[id]!.recargar(completa: completa);
    }
    return resultados;
  }

  /// Parar una corrida.
  Future<String?> parar(String deviceId) async {
    final viva = _vivas[deviceId];
    if (viva == null) return null;

    _cambia(deviceId, (c) => c.copyWith(estado: EstadoDeCorrida.parando));
    final r = await viva.parar();
    return r.error;
  }

  void _aplica(String deviceId, EventoDelDaemon evento) {
    final actual = state[deviceId];
    if (actual == null) return;

    final resultado = aplicaEvento(
      actual,
      _progresos[deviceId] ?? const {},
      evento,
    );
    if (resultado.termino) {
      _termina(deviceId, null);
      return;
    }
    _progresos[deviceId] = resultado.progresos;
    state = {...state, deviceId: resultado.corrida};
  }

  void _cambia(String deviceId, Corrida Function(Corrida) como) {
    final actual = state[deviceId];
    if (actual == null) return;
    state = {...state, deviceId: como(actual)};
  }

  void _termina(String deviceId, String? motivo) {
    // El registro **no** se borra aquí: si algo se cayó, ahí está el motivo, y
    // tirarlo justo al caerse es quitarle la prueba a quien va a mirarla.
    _vivas.remove(deviceId);
    _progresos.remove(deviceId);
    if (motivo != null) {
      // Se deja el motivo a la vista quitando la corrida: la fila desaparece y el
      // error queda donde se lea. Guardar una corrida muerta en el mapa haría que
      // el bloqueo de plataforma siguiera contándola.
      _ultimoError = motivo;
    }
    state = {...state}..remove(deviceId);
  }

  String? _ultimoError;

  /// El último motivo por el que se cayó algo, para poder decirlo una vez.
  String? tomaElUltimoError() {
    final motivo = _ultimoError;
    _ultimoError = null;
    return motivo;
  }
}

/// Lo que ha impreso cada corrida: el compilador, Gradle, la app.
///
/// **Estado observable y no una lista dentro del controlador**, que es lo que
/// era: así no se podía enseñar, porque nadie se enteraba de que llegó una línea.
/// Aparte de [corridasProvider] a propósito — una línea de registro no cambia el
/// estado de la corrida, y meterla ahí obligaría a reconstruir la fila entera
/// por cada línea de Gradle.
class RegistrosController extends Notifier<Map<String, List<String>>> {
  /// Las últimas y no todas. Un `flutter run` de un proyecto grande escupe miles,
  /// y guardarlas todas es una fuga de memoria con forma de función útil. Lo que
  /// se lee cuando algo falla son las de abajo.
  static const tope = 200;

  @override
  Map<String, List<String>> build() => const {};

  void anota(String deviceId, String linea) {
    // Gradle imprime bloques con saltos dentro: se parten para que el panel
    // enseñe líneas y no párrafos.
    final nuevas = [
      for (final l in linea.split('\n'))
        if (l.trim().isNotEmpty) l.trimRight(),
    ];
    if (nuevas.isEmpty) return;

    final actual = state[deviceId] ?? const <String>[];
    final juntas = [...actual, ...nuevas];
    state = {
      ...state,
      deviceId: juntas.length > tope
          ? juntas.sublist(juntas.length - tope)
          : juntas,
    };
  }

  void limpia(String deviceId) => state = {...state}..remove(deviceId);
}

final registrosProvider =
    NotifierProvider<RegistrosController, Map<String, List<String>>>(
      RegistrosController.new,
    );

final corridasProvider =
    NotifierProvider<CorridasController, Map<String, Corrida>>(
      CorridasController.new,
    );
