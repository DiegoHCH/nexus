import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/remote/domain/event_bridge.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';

/// Engancha el estado de la app al puente de eventos.
///
/// El segundo —y último— archivo que sabe a la vez de Riverpod y del canal, y por la
/// misma razón que [AssistantSurface]: aquí vive el acoplamiento, en un sitio. El
/// puente recibe fotos y no sabe de dónde salen; esto lee providers y no sabe qué es
/// un evento numerado.
///
/// La diferencia con la costura de la pieza 2 es la dirección: allí el teléfono
/// **pregunta**, aquí la app **cuenta**. Son dos caminos y no uno con dos sentidos,
/// porque preguntar puede fallar y contestarse con un error, mientras contar no tiene
/// a quién contestarle.
class EventPublisher {
  EventPublisher({required this.ref, required this.bridge});

  final Ref ref;
  final EventBridge bridge;

  final _escuchas = <String, ProviderSubscription<AssistantHudState>>{};
  ProviderSubscription<Conversations>? _deLaLista;

  void arrancar() {
    // Con `fireImmediately`: quien acaba de conectar necesita el estado de ahora, no
    // el del próximo cambio. Sin esto, una conversación quieta no existiría para el
    // teléfono hasta que alguien la tocara.
    _deLaLista = ref.listen(
      conversationsProvider,
      (_, estado) => _sincronizar(estado),
      fireImmediately: true,
    );
  }

  void parar() {
    for (final escucha in _escuchas.values) {
      escucha.close();
    }
    _escuchas.clear();
    _deLaLista?.close();
    _deLaLista = null;
    bridge.cerrar();
  }

  /// Pone al día a qué conversaciones se escucha.
  void _sincronizar(Conversations estado) {
    final vivas = {for (final item in estado.items) item.id};

    // Las que se fueron: se dejan de escuchar **y se avisa**. Sin el aviso, el
    // teléfono se quedaría con una tarjeta de algo que ya no existe, y solo se
    // enteraría al recargar la lista a mano.
    for (final id in _escuchas.keys.toList()) {
      if (vivas.contains(id)) continue;
      _escuchas.remove(id)?.close();
      bridge.olvidar(id);
    }

    for (final id in vivas) {
      if (_escuchas.containsKey(id)) continue;
      _escuchas[id] = ref.listen(
        assistantControllerProvider(id),
        (_, hud) => bridge.observar(_mirar(id, hud)),
        fireImmediately: true,
      );
    }
  }

  /// Traduce el estado de la pantalla a lo que ve el teléfono.
  ConversationView _mirar(String id, AssistantHudState hud) {
    // La última respuesta de Nexus, terminada o en curso. El puente ya se encarga de
    // mandar solo lo que falta; lo que hace falta aquí es la respuesta **entera**,
    // porque es contra ella contra la que se resta.
    final ultima = hud.messages.lastWhere(
      (m) => m.author == ChatAuthor.nexus,
      orElse: () => const ChatMessage(author: ChatAuthor.nexus, text: ''),
    );

    return ConversationView(
      conversationId: id,
      streaming: hud.isStreaming,
      reply: ultima.text,
      steps: [
        for (final paso in hud.activity)
          RemoteStep(
            id: paso.id,
            description: paso.description,
            writes: paso.writes,
            done: paso.done,
          ),
      ],
      meter: RemoteMeter(
        model: hud.meter.model,
        contextTokens: hud.meter.contextTokens,
        // Resuelta, como en la pieza 2: el ancho depende de la variante del modelo y
        // recalcularlo en el teléfono es repetir el error que ya se cometió aquí.
        contextWindow: hud.meter.contextWindow,
      ),
      error: hud.errorMessage,
    );
  }
}
