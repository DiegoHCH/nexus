import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/emulators/data/datasources/registros_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/entities/linea_de_registro.dart';
import 'package:nexus/features/emulators/domain/usecases/los_registros_del_dispositivo.dart';

final registrosDataSourceProvider = Provider<RegistrosDataSource>(
  (ref) => const RegistrosDataSource(),
);

/// Desde qué nivel se enseña, y qué texto tiene que traer.
///
/// Uno solo para todos los dispositivos, y no uno por corrida: el filtro es una
/// preferencia de quien mira —«ahora solo quiero ver errores»— y no una
/// propiedad del teléfono. Con uno por dispositivo habría que volver a subirlo
/// en cada uno.
class FiltroDelRegistro
    extends Notifier<({NivelDeRegistro minimo, String texto})> {
  @override
  ({NivelDeRegistro minimo, String texto}) build() =>
      (minimo: NivelDeRegistro.info, texto: '');

  /// El siguiente nivel, dando la vuelta.
  ///
  /// Cuatro y no seis: `verboso` y `depuracion` en un teléfono de verdad son
  /// miles de líneas por minuto y nadie las lee a mano — para eso está el filtro
  /// de texto. Se quedan fuera del botón, no del modelo.
  static const _losQueSeOfrecen = [
    NivelDeRegistro.info,
    NivelDeRegistro.aviso,
    NivelDeRegistro.error,
    NivelDeRegistro.fatal,
  ];

  void siguienteNivel() {
    final donde = _losQueSeOfrecen.indexOf(state.minimo);
    state = (
      minimo: _losQueSeOfrecen[(donde + 1) % _losQueSeOfrecen.length],
      texto: state.texto,
    );
  }

  void buscar(String texto) => state = (minimo: state.minimo, texto: texto);
}

final filtroDelRegistroProvider =
    NotifierProvider<
      FiltroDelRegistro,
      ({NivelDeRegistro minimo, String texto})
    >(FiltroDelRegistro.new);

/// El registro del sistema de cada dispositivo que se esté escuchando.
///
/// **Se escucha a petición y no con la corrida**, que es la decisión de producto
/// aquí: un `logcat` abierto es un proceso más, un cable ocupado y batería del
/// teléfono, y la mayoría de las veces no hace falta. Se enciende cuando algo se
/// cayó, que es cuando sirve.
class ElRegistroDelSistema
    extends Notifier<Map<String, List<LineaDeRegistro>>> {
  /// Las últimas y no todas, por lo mismo que el registro de la corrida: un
  /// teléfono de verdad escribe cientos por minuto y guardarlas todas es una
  /// fuga de memoria con forma de función útil.
  static const tope = 500;

  final _escuchas = <String, StreamSubscription<LineaDeRegistro>>{};

  @override
  Map<String, List<LineaDeRegistro>> build() {
    // Las suscripciones sobreviven al proveedor si nadie las corta, y cada una
    // es un proceso vivo con el cable ocupado.
    ref.onDispose(() {
      for (final escucha in _escuchas.values) {
        unawaited(escucha.cancel());
      }
      _escuchas.clear();
    });
    return const {};
  }

  bool escuchando(String deviceId) => _escuchas.containsKey(deviceId);

  void alterna(String deviceId, PlataformaEmulador plataforma) =>
      escuchando(deviceId) ? deja(deviceId) : escucha(deviceId, plataforma);

  void escucha(String deviceId, PlataformaEmulador plataforma) {
    if (_escuchas.containsKey(deviceId)) return;
    // Se empieza en vacío y no en «no hay»: la lista existe desde que se
    // enciende, y eso es lo que permite decir «escuchando, todavía nada» en vez
    // de dejar el panel como si no se hubiera pulsado.
    state = {...state, deviceId: const []};

    _escuchas[deviceId] = ref
        .read(registrosDataSourceProvider)
        .escuchar(plataforma: plataforma, deviceId: deviceId)
        .listen(
          (linea) => _anota(deviceId, linea),
          // El error llega como una línea más, y a nivel de error: es lo que
          // hace que «no está idevicesyslog» se lea en el mismo sitio donde se
          // estaba mirando, y no en un aviso que tapa la pantalla.
          onError: (Object error) {
            _anota(
              deviceId,
              LineaDeRegistro(
                nivel: NivelDeRegistro.error,
                etiqueta: 'nexus',
                texto: '$error',
              ),
            );
            unawaited(deja(deviceId));
          },
          onDone: () => unawaited(deja(deviceId)),
        );
  }

  Future<void> deja(String deviceId) async {
    final escucha = _escuchas.remove(deviceId);
    await escucha?.cancel();
  }

  /// Lo escuchado se **conserva** al dejar de escuchar: si algo se cayó, ahí
  /// está el motivo, y borrarlo al apagar es tirar justo lo que se vino a ver.
  /// Es el mismo criterio que el registro de la corrida.
  void limpia(String deviceId) => state = {...state}..remove(deviceId);

  void _anota(String deviceId, LineaDeRegistro linea) {
    if (!ref.mounted) return;
    final juntas = [...?state[deviceId], linea];
    state = {
      ...state,
      deviceId: juntas.length > tope
          ? juntas.sublist(juntas.length - tope)
          : juntas,
    };
  }
}

final registroDelSistemaProvider =
    NotifierProvider<ElRegistroDelSistema, Map<String, List<LineaDeRegistro>>>(
      ElRegistroDelSistema.new,
    );

/// Lo que se enseña de un dispositivo: lo escuchado, pasado por el filtro.
final loQueSeVeDelRegistroProvider =
    Provider.family<List<LineaDeRegistro>, String>((ref, deviceId) {
      final filtro = ref.watch(filtroDelRegistroProvider);
      final todas = ref.watch(registroDelSistemaProvider)[deviceId];
      if (todas == null) return const [];
      return [
        for (final linea in todas)
          if (LosRegistrosDelDispositivo.pasa(
            linea,
            minimo: filtro.minimo,
            conteniendo: filtro.texto,
          ))
            linea,
      ];
    });
