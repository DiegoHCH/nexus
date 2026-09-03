import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/repositories/el_despacho_de_carpeta.dart';
import 'package:nexus/features/assistant/domain/usecases/a_que_carpeta_va.dart';
import 'package:nexus/features/assistant/domain/usecases/que_hacer_con_el_encargo.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El despacho de verdad: decide con [QueHacerConLoQueSeDijo] y lo lleva.
///
/// Vive en presentation porque **mover un encargo es mover la pantalla**: hay
/// que enfocar otra conversación y, si no existe, abrirla. La decisión de a
/// dónde va no está aquí — está en `domain`, pura y probada.
class ElDespachoDeCarpetaImpl implements ElDespachoDeCarpeta {
  const ElDespachoDeCarpetaImpl(this._ref);

  final Ref _ref;

  @override
  Future<LoQueQuedaPorHacer> despachar(
    String frase, {
    required String? carpetaDeAqui,
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
  }) async {
    final strings = _ref.read(stringsProvider);
    final destino = QueHacerConLoQueSeDijo.de(
      ACarpetaVaLoQueDices.de(
        frase,
        _ref.read(workspaceControllerProvider).folders,
      ),
      frase: frase,
      carpetaDeAqui: carpetaDeAqui,
      abiertas: _ref.read(conversationsProvider),
    );

    switch (destino) {
      case AtenderloAqui(:final tarea):
        return AtiendeloTu(tarea);

      case LlevarloA(:final conversacion, :final tarea):
        return _llevar(
          conversacion,
          tarea,
          loQueSeVe: loQueSeVe,
          allowWrites: allowWrites,
          attachments: attachments,
        );

      case AbrirUnaPara(:final carpeta, :final tarea):
        final abierta = await _ref
            .read(conversationsProvider.notifier)
            .open(carpeta.path);
        if (abierta == null) {
          // La lista se llenó entre la decisión y el hueco. Se dice, en vez de
          // atenderlo aquí: hacer el trabajo en la carpeta equivocada es lo que
          // todo esto viene a evitar.
          return HayQueDecir(strings.noCabeOtraConversacion(carpeta.name));
        }
        return _llevar(
          abierta,
          tarea,
          loQueSeVe: loQueSeVe,
          allowWrites: allowWrites,
          attachments: attachments,
        );

      case NoCabeOtraConversacion(:final carpeta):
        return HayQueDecir(strings.noCabeOtraConversacion(carpeta.name));

      case PreguntarPorCual(:final carpetas):
        return HayQueDecir(
          strings.variasCarpetasNombradas(
            carpetas.map((c) => c.name).join(', '),
          ),
        );
    }
  }

  /// Lleva el encargo, y **se va con él**.
  ///
  /// El foco cambia porque es la única señal de que pasó algo: sin eso, se pide
  /// en un sitio y el trabajo aparece en otro que no se está mirando.
  Future<LoQueQuedaPorHacer> _llevar(
    String conversacion,
    String tarea, {
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
  }) async {
    final conversaciones = _ref.read(conversationsProvider.notifier);
    await conversaciones.focus(conversacion);

    final carpeta =
        _ref.read(conversationsProvider).byId(conversacion)?.folderPath ?? '';
    final nombre = carpeta.split('/').last;

    // Sin tarea solo se cambia de sitio, que es exactamente lo que se pidió.
    if (tarea.trim().isEmpty) return YaSeFue(nombre);

    await _ref
        .read(assistantControllerProvider(conversacion).notifier)
        .submit(
          tarea,
          loQueSeVe: loQueSeVe,
          // 🔴 **El tope viaja con el encargo.** `allowWrites` baja lo que la
          // carpeta concede y nunca lo sube; sin reenviarlo, un teléfono en
          // solo lectura conseguía escritura nombrando otra carpeta.
          allowWrites: allowWrites,
          attachments: attachments,
        );
    return YaSeFue(nombre);
  }
}

final elDespachoDeCarpetaProvider = Provider<ElDespachoDeCarpeta>(
  ElDespachoDeCarpetaImpl.new,
);
