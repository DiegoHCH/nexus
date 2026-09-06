import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/ventana_de_la_consola.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/data/datasources/tunel_data_source.dart';
import 'package:nexus/features/run/domain/usecases/la_consola_de_la_app.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';

/// Quien enchufa el puerto del dispositivo con uno de esta máquina.
final tunelDataSourceProvider = Provider<TunelDataSource>(
  (ref) => const TunelDataSource(),
);

/// Quien abre la ventana de la consola.
///
/// Proveedor y no llamada directa para poder probar **que se abre y con qué
/// URL** sin abrir ninguna ventana: en una prueba no hay nadie al otro lado del
/// canal nativo, y lo que hay que comprobar es la dirección, no AppKit.
typedef AbreLaConsola =
    Future<bool> Function({required String url, String? titulo});

final abreLaConsolaProvider = Provider<AbreLaConsola>(
  (ref) =>
      ({required url, titulo}) =>
          VentanaDeLaConsola.abre(url: url, titulo: titulo),
);

final laConsolaQueSeAbreProvider = Provider<LaConsolaQueSeAbre>(
  LaConsolaQueSeAbre.new,
);

/// La consola de depuración de la app, abierta sola al correrla.
///
/// 🔴 **Era abrir el túnel a mano y luego el navegador.** La app del trabajo
/// levanta su propio servidor de depuración —rutas registradas, estado de la
/// pantalla, providers en vivo, mockeo de endpoints— y llegar a él costaba dos
/// comandos y salir de Nexus. Lo que se pidió es que **se abra sola** al correr
/// la app, en una ventana de Nexus como la de los documentos.
///
/// Aparte del controlador de corridas a propósito: aquél lleva el proceso y su
/// estado, y esto es una decisión con tres pasos —¿hay consola?, ¿en qué
/// puerto?, ¿hace falta túnel?— que se prueba sin lanzar un `flutter run`.
class LaConsolaQueSeAbre {
  LaConsolaQueSeAbre(this._ref);

  final Ref _ref;

  /// A qué corridas se les está esperando el banner.
  ///
  /// Se apunta al arrancar —lo dice la configuración elegida— y se tacha en
  /// cuanto aparece: el banner sale una vez, y pasarle una expresión regular a
  /// cada línea de un `logcat` por si acaso es trabajo por nada.
  final _esperando = <String>{};

  /// Los túneles abiertos, para poder cerrarlos.
  final _tuneles = <String, int>{};

  /// Al lanzar: ¿esta corrida trae consola?
  void alArrancar({required String deviceId, required List<String> args}) {
    if (LaConsolaDeLaApp.laEnciende(args)) {
      _esperando.add(deviceId);
    } else {
      _esperando.remove(deviceId);
    }
  }

  /// Una línea de la corrida. Si es el banner, abre el túnel y la ventana.
  Future<void> alVerLaLinea(String deviceId, String linea) async {
    if (!_esperando.contains(deviceId)) return;
    final puerto = LaConsolaDeLaApp.puertoEn(linea);
    if (puerto == null) return;
    _esperando.remove(deviceId);

    final corrida = _ref.read(corridasProvider)[deviceId];
    if (corrida == null) return;
    final registros = _ref.read(registrosProvider.notifier);

    // **El túnel solo en Android.** El simulador de iOS comparte la red de esta
    // máquina y no necesita ninguno; un iPhone físico necesitaría `iproxy`, que
    // no viene con Xcode — ahí la ventana dirá que no puede conectar, y decirlo
    // es mejor que no abrir nada sin explicar por qué.
    if (corrida.plataforma == PlataformaEmulador.android) {
      final problema = await _ref
          .read(tunelDataSourceProvider)
          .abrir(deviceId: deviceId, puerto: puerto);
      if (problema != null) {
        // 🔴 **Se dice en el registro de la corrida y no en un aviso que tapa la
        // pantalla.** El fallo típico es el puerto ocupado por el `forward`
        // huérfano de otra sesión, y eso se lee justo donde se estaba mirando.
        registros.anota(deviceId, 'consola: $problema');
        return;
      }
      _tuneles[deviceId] = puerto;
    }

    _ref.read(corridasProvider.notifier).apuntaLaConsola(deviceId, puerto);
    final url = LaConsolaDeLaApp.urlDe(puerto);
    // Queda escrito en el registro además de abrirse: la ventana se puede
    // cerrar, y entonces la dirección tiene que seguir en algún sitio.
    registros.anota(deviceId, 'consola de la app en $url');
    await _ref.read(abreLaConsolaProvider)(
      url: url,
      titulo: '${corrida.configuracion} · ${corrida.dispositivo}',
    );
  }

  /// Al terminar la corrida: el túnel se va con ella.
  ///
  /// Sin app al otro lado no lleva a ninguna parte, y un `adb forward` huérfano
  /// se queda vivo en el daemon el resto de la sesión — el siguiente arranque se
  /// encontraría el puerto ocupado por el fantasma del anterior.
  Future<void> alTerminar(String deviceId) async {
    _esperando.remove(deviceId);
    final puerto = _tuneles.remove(deviceId);
    if (puerto == null) return;
    await _ref
        .read(tunelDataSourceProvider)
        .cerrar(deviceId: deviceId, puerto: puerto);
  }
}
