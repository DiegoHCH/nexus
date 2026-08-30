import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/repositories/el_parte_del_dia.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/history/domain/usecases/el_parte_de_ayer.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/history/presentation/providers/slack_providers.dart';

/// El material del parte, montado en el encargo que lo redacta.
///
/// **Aquí y en un solo sitio** porque lo piden dos caminos —el botón del menú y
/// la voz— y son el mismo parte: si cada uno montara el suyo, el día elegido o
/// el filtro del proyecto acabarían separándose sin que nadie lo notara hasta
/// leer dos dailies distintos del mismo día.
///
/// Devuelve `null` si no hay ningún día anterior con trabajo.
Future<String?> laInstruccionDelParte(Ref ref) async {
  final todas = await ref.read(localConversationStoreProvider).listAll();
  return ElParteDeAyer.instruccion(
    todas,
    hoy: DateTime.now(),
    // **Solo el proyecto que va a ese Slack.** Sin esto, lo de los proyectos
    // personales —o de otro repo del trabajo— acabaría en ese daily.
    soloDelProyecto: ref.read(slackControllerProvider).proyecto,
  );
}

/// El puerto [ElParteDelDia], atado a la conversación que está hablando.
///
/// Vive en el cableado y no en el dominio porque necesita el `Ref` y el
/// controlador de **esa** conversación: el parte tiene que quedar en la ventana
/// donde se pidió, no en cualquiera.
class ElParteDesdeLaVoz implements ElParteDelDia {
  const ElParteDesdeLaVoz(this._ref, this._conversationId);

  final Ref _ref;
  final String _conversationId;

  @override
  Future<String?> instruccion() => laInstruccionDelParte(_ref);

  @override
  void yaEstaEscrito(String parte) => _ref
      .read(assistantControllerProvider(_conversationId).notifier)
      .dejarElParte(parte);
}

/// Por conversación, como la propia sesión de voz: el parte se deja donde se
/// pidió.
final elParteDelDiaProvider = Provider.family<ElParteDelDia, String>(
  ElParteDesdeLaVoz.new,
);
