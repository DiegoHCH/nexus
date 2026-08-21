import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/pages/conversation_page.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/link_badge.dart';

/// Lo que hay abierto en el Mac.
///
/// Es la pantalla de entrada porque **hay hasta tres conversaciones a la vez y
/// trabajan en paralelo**: entrar directo a una escondería que las otras dos están
/// avanzando, que es justo lo que un teléfono viene a resolver — mirar cómo va lo que
/// dejaste corriendo.
class ConversationsPage extends ConsumerWidget {
  const ConversationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final espejo = ref.watch(mirrorProvider);

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const LinkBadge(),
                  TextButton(
                    key: const ValueKey('olvidar'),
                    onPressed: () =>
                        ref.read(pairingControllerProvider.notifier).olvidar(),
                    child: Text(
                      'Olvidar',
                      style: TextStyle(color: colors.mute),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                // Tirar hacia abajo vuelve a pedir la lista. Existe porque el móvil
                // pasa ratos en segundo plano y volver no siempre trae un evento:
                // sin esto la única forma de refrescar sería reconectar.
                onRefresh: () => ref.read(mirrorProvider.notifier).refrescar(),
                color: colors.accent,
                backgroundColor: colors.deep,
                child: espejo.vacio
                    ? const _Vacio()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: espejo.visibles.length,
                        itemBuilder: (context, i) =>
                            _Tarjeta(conversacion: espejo.visibles[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Una lista vacía **no es un error**: es un Mac sin conversaciones abiertas, y
    // eso pasa a diario. Se dibuja como un estado y no como un fallo — y con
    // scroll, para que el tirón de refrescar siga funcionando.
    return ListView(
      children: [
        const SizedBox(height: 80),
        const SizedBox(
          height: 140,
          child: NexusOrb(state: NexusOrbState.sleep, showHorizon: false),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            'Nada abierto en el Mac',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.mute),
          ),
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.conversacion});

  final MirroredConversation conversacion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = Theme.of(context).textTheme;

    return Card(
      color: colors.deep,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: ValueKey('abrir-${conversacion.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationPage(conversationId: conversacion.id),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // La ruta, que es lo que un humano reconoce. Se enseña el
                      // final y no el principio: `/Users/…/proyectos/api` se
                      // distingue por la cola, no por la cabeza.
                      _cola(conversacion.nombre),
                      overflow: TextOverflow.ellipsis,
                      style: texto.bodyLarge?.copyWith(color: colors.ink),
                    ),
                  ),
                  if (conversacion.focused)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.mic, size: 15, color: colors.accent),
                    ),
                ],
              ),
              if (conversacion.streaming) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      conversacion.steps.isEmpty
                          ? 'trabajando'
                          : conversacion.steps.last.text,
                      style: texto.bodySmall?.copyWith(color: colors.mute),
                    ),
                  ],
                ),
              ] else if (conversacion.reply.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  conversacion.reply,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: texto.bodySmall?.copyWith(color: colors.mute),
                ),
              ],
              if (conversacion.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  conversacion.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: texto.bodySmall?.copyWith(color: colors.err),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Los dos últimos tramos de la ruta. Con una pantalla estrecha, el principio de
  /// una ruta absoluta es lo que todas tienen en común y lo último es lo que las
  /// distingue.
  static String _cola(String ruta) {
    final tramos = ruta.split('/').where((t) => t.isNotEmpty).toList();
    if (tramos.length <= 2) return ruta;
    return '…/${tramos.sublist(tramos.length - 2).join('/')}';
  }
}
