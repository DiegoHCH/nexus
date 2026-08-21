import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/pages/conversation_page.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/pages/utility_pages.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_drawer.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';

/// Lo que hay abierto en el Mac.
///
/// Es la pantalla de entrada porque **hay hasta tres conversaciones a la vez y
/// trabajan en paralelo**: entrar directo a una escondería que las otras dos están
/// avanzando, que es justo lo que un teléfono viene a resolver — mirar cómo va lo que
/// dejaste corriendo.
class ConversationsPage extends ConsumerStatefulWidget {
  const ConversationsPage({super.key});

  @override
  ConsumerState<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends ConsumerState<ConversationsPage> {
  /// El cajón se abre desde aquí y no desde un `Builder` en la cabecera: con la llave
  /// en el estado, quien abre el menú es la pantalla y la cabecera solo avisa.
  final _llave = GlobalKey<ScaffoldState>();

  void _ir(Widget pantalla) {
    // Se cierra el menú **antes** de navegar: si se deja abierto, al volver aparece
    // encima de la pantalla nueva y parece que no se hizo nada.
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final espejo = ref.watch(mirrorProvider);

    return Scaffold(
      key: _llave,
      backgroundColor: colors.void_,
      drawer: MobileDrawer(
        alAbrirNueva: () => _ir(const FoldersPage()),
        alAbrirArchivo: () => _ir(const ArchivePage()),
        alAbrirArtifacts: () => _ir(const ArtifactsPage()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              // La cabecera del sistema, con el hamburguesa. «Olvidar» se fue al
              // menú: era la única acción destructiva y estaba en la esquina de la
              // pantalla principal, a un toque de todo lo demás.
              child: MobileChrome(
                alMenu: () => _llave.currentState?.openDrawer(),
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
                    // Vacío **no siempre significa lo mismo**: puede que el Mac no
                    // tenga nada abierto, o que no se haya podido preguntar. Se
                    // dibujaban idénticos, y son dos cosas distintas.
                    ? _Vacio(
                        preguntado: ref
                            .read(mirrorProvider.notifier)
                            .preguntado,
                      )
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
  const _Vacio({required this.preguntado});

  /// Si el Mac contestó a la última petición de la lista.
  final bool preguntado;

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
            preguntado
                ? 'Nada abierto en el Mac'
                : 'No pude preguntarle al Mac',
            style: NexusTypography.body.copyWith(color: colors.mute),
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
    // **Una fila con hairline, no una tarjeta.** Una `Card` trae elevación, esquinas
    // de 12 y su propio color de superficie: tres cosas que este sistema no usa en
    // ninguna otra parte, y que hacían que esta pantalla se leyera como otra app. Las
    // demás listas del teléfono —el archivo, los artifacts, el menú— ya son filas
    // separadas por una línea de un píxel.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: InkWell(
        key: ValueKey('abrir-${conversacion.id}'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationPage(conversationId: conversacion.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
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
                      style: NexusTypography.lead.copyWith(color: colors.ink),
                    ),
                  ),
                  if (conversacion.focused)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      // Con la palabra y no con un icono de micrófono: en una fila de
                      // texto un glifo de Material es la única forma redonda de la
                      // pantalla, y encima hay que saber qué significa.
                      child: Text(
                        'ESCUCHA',
                        style: NexusTypography.label.copyWith(
                          color: colors.accent,
                        ),
                      ),
                    ),
                ],
              ),
              if (conversacion.streaming) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Un punto con halo y no una rueda girando: **el único elemento
                    // que gira en este sistema es el orbe**, y una segunda cosa
                    // girando compite con él sin decir nada más. Es la misma marca
                    // que el paso «ahora mismo» dentro de la conversación.
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 5, right: 10),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.8),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        conversacion.steps.isEmpty
                            ? 'trabajando'
                            : conversacion.steps.last.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NexusTypography.mono.copyWith(
                          color: colors.mute,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (conversacion.reply.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  conversacion.reply,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.mono.copyWith(color: colors.mute),
                ),
              ],
              if (conversacion.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  conversacion.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.mono.copyWith(color: colors.err),
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
