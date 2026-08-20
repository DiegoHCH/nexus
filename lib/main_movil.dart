import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/theme_preference.dart';
import 'package:nexus/core/i18n/strings_scope.dart';

/// El punto de entrada del teléfono.
///
/// **Un segundo `main` y no un `main.dart` que se bifurque**, y es una decisión con
/// motivo: la app de escritorio arranca atajos globales, el marco de la ventana en
/// AppKit, el autoactualizado de Sparkle y la presencia en la barra de menús. Nada
/// de eso existe en un teléfono, y un `main` con ramas los arrastraría a la
/// compilación de Android igualmente — con un `MissingPluginException` esperando en
/// cada uno.
///
/// Lo que sí se comparte es todo lo que no toca el sistema: el tema, los textos, el
/// orbe y —desde la 4.1— el protocolo y la costura del canal. Eso es exactamente lo
/// que se compró eligiendo Flutter (ficha `lo7`), y por eso el móvil no es un
/// proyecto aparte: es otro `-t` del mismo.
///
/// Se corre con `flutter run -t lib/main_movil.dart`.
void main() {
  runApp(const ProviderScope(child: NexusMovil()));
}

class NexusMovil extends ConsumerWidget {
  const NexusMovil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final acento = ref.watch(accentControllerProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // El mismo tema que el escritorio, con el mismo ajuste de contraste por
      // brillo. En un teléfono importa más: se usa al sol.
      theme: NexusTheme.light(accent: acento.forBrightness(Brightness.light)),
      darkTheme: NexusTheme.dark(accent: acento.forBrightness(Brightness.dark)),
      themeMode: ref.watch(themeControllerProvider).mode,
      locale: locale,
      supportedLocales: NexusStrings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Por encima del Navigator y no envolviendo `home`, por lo mismo que en el
      // escritorio: una ruta nueva se construye fuera del hijo de `home`, y con el
      // scope ahí abajo la segunda pantalla revienta por falta de textos.
      builder: (context, child) =>
          StringsScope(strings: NexusStrings.of(locale), child: child!),
      home: const _SinEmparejar(),
    );
  }
}

/// Lo que hay antes de emparejar.
///
/// Es una pantalla de verdad y no un hueco: el teléfono va a nacer así siempre —sin
/// URL ni token— y esa es la primera cosa que alguien ve. Emparejar es la pieza
/// siguiente; esto ya dice qué falta.
class _SinEmparejar extends StatelessWidget {
  const _SinEmparejar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // El mismo orbe del escritorio, con la misma matemática. En el
                // teléfono va más pequeño —180 y no 320— porque la pantalla es
                // vertical y tiene que quedar sitio para la conversación.
                const SizedBox(
                  width: 180,
                  height: 180,
                  child: NexusOrb(
                    state: NexusOrbState.sleep,
                    showHorizon: false,
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Nexus',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.ink,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'sin emparejar',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.mute),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
