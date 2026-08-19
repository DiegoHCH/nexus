import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// El reloj, inyectable: el tope de «no preguntes otra vez tan pronto» **es**
/// temporal, y probarlo con el reloj de verdad significaría esperar un cuarto de
/// hora.
final relojProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// La versión que corre, leída del paquete y no escrita a mano.
///
/// A mano se queda desfasada en cuanto alguien publique sin tocar la constante, y
/// entonces mentiría en la dirección peor: diciendo que estás al día.
final currentVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Si esta copia puede reemplazarse a sí misma.
///
/// Se consulta antes de ofrecer nada, y de ahí sale el aviso de «arrástrala a
/// Aplicaciones» en vez de una descarga que iba a fallar al final.
final installabilityProvider = FutureProvider<Installability>(
  (ref) => UpdatesChannel.installability(),
);

/// Lo que se sabe: si hay versión nueva, y por dónde va el proceso.
@immutable
class UpdatesState {
  const UpdatesState({this.notice, this.stage = const UpdateIdle()});

  /// Para la fila del menú de la barra y para Ajustes › Ayuda: qué corre y qué
  /// hay publicado. `null` mientras no se sabe ni lo uno.
  final ReleaseCheck? notice;

  /// Por dónde va la actualización, para la modal.
  final UpdateStage stage;

  UpdatesState copyWith({ReleaseCheck? notice, UpdateStage? stage}) =>
      UpdatesState(notice: notice ?? this.notice, stage: stage ?? this.stage);
}

/// El actualizador, visto desde Dart.
///
/// **Ya no pregunta a GitHub por su cuenta.** Antes esto sondeaba la API de
/// releases y solo sabía avisar con un enlace; ahora el motor es Sparkle y esta
/// clase es quien traduce lo que cuenta en algo que la interfaz pueda pintar. Dos
/// mecanismos preguntando lo mismo era la alternativa, y habrían acabado
/// discrepando: el aviso diciendo una versión y la modal ofreciendo otra.
///
/// La cadencia también se mudó: vive en el `Info.plist` —cada dos horas— porque
/// es Sparkle quien lleva el reloj. Aquí solo queda el tope de al volver a la
/// ventana, que es nuestro y sigue siendo útil.
class UpdatesController extends Notifier<UpdatesState> {
  /// Al volver a la ventana se pregunta como mucho con este hueco. Sin el tope,
  /// cambiar de app y volver diez veces son diez comprobaciones.
  static const alVolver = Duration(minutes: 15);

  DateTime? _ultima;
  StreamSubscription<UpdateEvent>? _escucha;

  @override
  UpdatesState build() {
    UpdatesChannel.listen();
    _escucha = UpdatesChannel.events.listen(aplicar);
    ref.onDispose(() => unawaited(_escucha?.cancel()));
    unawaited(_leerVersion());
    return const UpdatesState();
  }

  Future<void> _leerVersion() async {
    final actual = await ref.read(currentVersionProvider.future);
    state = state.copyWith(notice: ReleaseCheck(current: actual));
  }

  /// Se llama al volver a la ventana. Respeta el hueco y no saca cartel: si no
  /// hay nada, esto tiene que ser invisible.
  Future<void> alRegresar() async {
    final ahora = ref.read(relojProvider)();
    final ultima = _ultima;
    if (ultima != null && ahora.difference(ultima) < alVolver) return;
    _ultima = ahora;
    await UpdatesChannel.check();
  }

  /// La que pide una persona desde Ajustes: esta **sí** contesta «estás al día».
  Future<void> comprobarAhora() async {
    _ultima = ref.read(relojProvider)();
    state = state.copyWith(stage: const UpdateChecking());
    await UpdatesChannel.check(manual: true);
  }

  Future<void> instalar() => UpdatesChannel.answer(UpdateChoice.install);

  /// Quitar el aviso de en medio: «más tarde» y la cruz son lo mismo, así que es
  /// un solo método. Dos nombres para la misma acción es de donde salen las dos
  /// que acaban divergiendo.
  ///
  /// Vuelve a reposo **en el acto** en vez de esperar a que el actualizador
  /// confirme el cierre: el botón tiene que responder al pulsarlo.
  ///
  /// Y deja el aviso puesto: `notice` sigue diciendo que hay una versión nueva, y
  /// de eso vive el punto rojo. Descartar es «ahora no», no «no me lo digas».
  Future<void> descartar() async {
    state = state.copyWith(stage: const UpdateIdle());
    await UpdatesChannel.answer(UpdateChoice.later);
  }

  /// Si queda algo por instalar que ya se sabe. De aquí sale el punto rojo.
  bool get pendiente => state.notice?.isNewer ?? false;

  /// Saltarse **esta** versión: no volverá a ofrecerse, la siguiente sí.
  Future<void> saltar() async {
    state = state.copyWith(stage: const UpdateIdle());
    await UpdatesChannel.answer(UpdateChoice.skip);
  }

  Future<void> cancelar() async {
    state = state.copyWith(stage: const UpdateIdle());
    await UpdatesChannel.cancel();
  }

  /// Traduce un aviso del actualizador a estado.
  ///
  /// Público para poder probarlo sin canal nativo: lo que importa comprobar es
  /// esta traducción, no que un `MethodChannel` entregue mensajes.
  @visibleForTesting
  void aplicar(UpdateEvent evento) {
    final corriendo = state.notice?.current ?? '';

    switch (evento.name) {
      case 'checking':
        state = state.copyWith(stage: const UpdateChecking());

      case 'found':
        final version = evento.get<String>('version') ?? '';
        state = UpdatesState(
          notice: ReleaseCheck(current: corriendo, latest: version),
          stage: UpdateFound(
            version: version,
            notes: evento.get<String>('notes'),
            bytes: evento.get<int>('bytes'),
            alreadyDownloaded: evento.get<bool>('downloaded') ?? false,
          ),
        );

      case 'notes':
        // Las notas pueden llegar después que el aviso, si viajan aparte del
        // feed. Se pegan a lo que ya hay en vez de reemplazar la fase, que
        // borraría la versión de la modal a mitad.
        if (state.stage case final UpdateFound encontrada) {
          state = state.copyWith(
            stage: UpdateFound(
              version: encontrada.version,
              notes: evento.get<String>('notes') ?? encontrada.notes,
              bytes: encontrada.bytes,
              alreadyDownloaded: encontrada.alreadyDownloaded,
            ),
          );
        }

      case 'none':
        state = UpdatesState(
          // `latest` igual a la que corre, que es lo que significa estar al día.
          // Dejarlo en `null` diría «no se pudo preguntar», que es otra cosa.
          notice: ReleaseCheck(current: corriendo, latest: corriendo),
          stage: const UpdateUpToDate(),
        );

      case 'downloading':
        state = state.copyWith(
          stage: UpdateDownloading(
            received: evento.get<int>('received') ?? 0,
            total: evento.get<int>('total'),
          ),
        );

      case 'extracting':
        state = state.copyWith(
          stage: UpdateExtracting(progress: evento.get<double>('progress') ?? 0),
        );

      case 'ready':
        state = state.copyWith(stage: const UpdateReady());

      case 'installing':
        state = state.copyWith(stage: const UpdateInstalling());

      case 'installed':
        // Solo se ve si el relanzado no ocurrió; si ocurrió, este proceso ya no
        // existe para verlo.
        state = state.copyWith(stage: const UpdateIdle());

      case 'failed':
        state = state.copyWith(
          stage: UpdateFailed(evento.get<String>('message') ?? ''),
        );

      case 'closed':
        state = state.copyWith(stage: const UpdateIdle());
    }

    debugPrint('actualizaciones · ${evento.name} → ${state.stage.runtimeType}');
  }
}

final updatesControllerProvider =
    NotifierProvider<UpdatesController, UpdatesState>(UpdatesController.new);
