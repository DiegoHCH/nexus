import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/stats/presentation/widgets/stats_section.dart';
import 'package:nexus/features/superpowers/presentation/widgets/superpowers_section.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/appearance_section.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/help_section.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/history_section.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/language_section.dart';
import 'package:nexus/features/remote/presentation/pages/mobile_section.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/permissions_section.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/voice_section.dart';

/// Ajustes (D05 del mockup). De sus cuatro secciones solo vive «Permisos»:
/// las otras tres se listan apagadas, como en el propio mockup, porque
/// pertenecen a fases que aún no existen y fingirlas sería peor que dejarlas
/// a la vista.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  /// Se abre desde cuatro sitios —el botón de la barra, el de «empareja una
  /// carpeta», ⌘, y el menú de macOS—, y algunos pueden coincidir en la misma
  /// pulsación. Apilar dos ajustes deja al usuario cerrando la misma pantalla
  /// dos veces, así que el segundo no hace nada.
  static bool _isOpen = false;

  static Future<void> open(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// «Móvil» sigue apagada: pertenece a una fase que no existe, y fingirla
  /// sería peor que dejarla a la vista como lo que es. Donde estaba «Modelo»
  /// ahora hay estadísticas: el modelo se elige por carpeta desde la barra
  /// —le12—, así que esa sección se quedó sin contenido antes de tenerlo.
  /// Las secciones vivas, en el orden en que se leen. Son claves, no textos:
  /// el nombre visible sale del diccionario.
  ///
  /// Sale de `values` y **no de una lista escrita a mano**: esa lista ya se
  /// olvidó dos veces —el Historial primero y los Superpoderes después—, y el
  /// resultado es siempre el mismo, una sección que existe, se pinta bien y no
  /// tiene forma de abrirse. Con el orden de declaración como orden del menú,
  /// añadir una al enum basta para que aparezca.
  _Section _section = _Section.permissions;

  @override
  void initState() {
    super.initState();
    // Se relee al abrir Ajustes, no una vez por arranque: crear o borrar un
    // perfil pasa fuera de la app, y con la lista cacheada seguía ofreciendo
    // una cuenta que ya no existía.
    //
    // Después del primer fotograma y no aquí mismo: invalidar durante la
    // construcción del árbol marca el scope como sucio en mitad de su propio
    // build, y Flutter lo corta con «setState() called during build» — la
    // pantalla entera en rojo al abrir Ajustes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(claudeProfilesProvider);
    });
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsTopBar(onClose: () => Navigator.of(context).maybePop()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(64, 56, 64, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final section in _Section.values)
                            _SectionLink(
                              // Con nombre propio: «VOZ» aparece dos veces en
                              // esta pantalla —el enlace de la izquierda y la
                              // modalidad de una carpeta— y sin una llave no
                              // hay forma de decir cuál se pulsa.
                              key: ValueKey('seccion-${section.name}'),
                              label: section.title(context.strings),
                              active: _section == section,
                              onTap: () => setState(() => _section = section),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 96),
                    Expanded(
                      child: SizedBox(
                        width: 600,
                        child: switch (_section) {
                          _Section.voice => const VoiceSection(),
                          _Section.permissions => const PermissionsSection(),
                          _Section.mobile => const MobileSection(),
                          _Section.history => const HistorySection(),
                          _Section.stats => const StatsSection(),
                          _Section.superpowers => const SuperpowersSection(),
                          _Section.appearance => const AppearanceSection(),
                          _Section.language => const LanguageSection(),
                          _Section.help => const HelpSection(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionLink extends StatelessWidget {
  const _SectionLink({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // El relleno **dentro** del InkWell y no fuera: por fuera, la mitad de
    // abajo de cada enlace era hueco muerto que no respondía al clic. Lo
    // destapó la prueba que abre la pantalla, y el ratón lo sufría igual.
    //
    // Y ancho completo, no el del texto: la columna mide 200 y el área que
    // respondía era del ancho de cada palabra —«VOZ» daba tres letras de blanco
    // útil—, así que apuntar a la pestaña corta fallaba más que las largas. Ahora
    // todas valen lo mismo y no queda hueco muerto entre una y la siguiente.
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: NexusSpacing.s3,
            horizontal: NexusSpacing.s2,
          ),
          child: Text(
            label.toUpperCase(),
            style: NexusTypography.label.copyWith(
              color: active ? colors.accent : colors.faint,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTopBar extends ConsumerWidget {
  const _SettingsTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s6,
        vertical: NexusSpacing.s5,
      ),
      child: Row(
        children: [
          // Un solo `Flexible` para el rótulo entero, y **sin `Spacer`**: con un
          // `Flexible` por texto, cada uno se llevaba su parte del reparto —flex 1
          // por defecto— y el hueco quedaba dividido en tres, así que «Cerrar» se
          // plantaba a media pantalla en vez de en el borde. Ahora el rótulo se
          // queda todo el sobrante y empuja el botón a la derecha, y en una
          // ventana estrecha sigue encogiendo con puntos suspensivos, que es para
          // lo que estaba puesto.
          // `Expanded` y no `Flexible`: el segundo deja al hijo quedarse pequeño,
          // así que el rótulo medía lo que su texto y «Cerrar» se pegaba a él —a
          // 825 px del borde, medido—. Con restricciones ajustadas el rótulo ocupa
          // todo el sobrante y empuja el botón al borde.
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    context.strings.brand,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.data.copyWith(
                      color: colors.mute,
                      letterSpacing: 4.2,
                    ),
                  ),
                ),
                const SizedBox(width: NexusSpacing.s5),
                Flexible(
                  child: Text(
                    context.strings.settings,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.label.copyWith(
                      color: colors.faint,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.s5),
          // El interruptor de permisos ya no vive aquí.
          //
          // Es del espacio de trabajo entero, así que en la cabecera salía en
          // **todas** las secciones sin nada que lo explicase — al lado de la voz
          // o del idioma no dice de qué habla. Se cambia donde tiene contexto: en
          // la sección de Permisos, con su título y su explicación, y en la
          // pantalla principal, junto a la caja de escribir, que es donde importa
          // saber si Claude puede editar antes de pedirle algo.
          OutlinedButton(
            onPressed: onClose,
            child: Text(context.strings.closeEsc),
          ),
        ],
      ),
    );
  }
}

/// Las secciones de Ajustes, como claves. El nombre visible sale del
/// diccionario: aquí solo se decide cuáles hay y en qué orden.
enum _Section {
  voice,
  permissions,
  mobile,
  history,
  stats,
  superpowers,
  appearance,
  language,
  help;

  String title(NexusStrings strings) => switch (this) {
    _Section.voice => strings.sectionVoice,
    _Section.permissions => strings.sectionPermissions,
    _Section.mobile => strings.sectionMobile,
    _Section.history => strings.sectionHistory,
    _Section.stats => strings.sectionStats,
    _Section.superpowers => strings.sectionSuperpowers,
    _Section.appearance => strings.sectionAppearance,
    _Section.language => strings.sectionLanguage,
    _Section.help => strings.sectionHelp,
  };
}
