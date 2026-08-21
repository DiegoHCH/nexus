import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/pages/connecting_page.dart';
import 'package:nexus/features/remote/presentation/pages/conversations_page.dart';
import 'package:nexus/features/remote/presentation/pages/scan_page.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
Future<void> main() async {
  // **Antes de tocar un canal de plataforma.** `PackageInfo` habla con el sistema, y
  // pedirlo antes de esto lanza «Binding has not yet been initialized» — que en el
  // teléfono se ve como una pantalla negra y nada más. Lo llama `runApp`, pero aquí
  // hay trabajo *antes* de `runApp`, así que hay que llamarlo a mano.
  //
  // No lo vio ninguna de las 648 pruebas: el arnés de pruebas inicializa su propio
  // binding, así que este `main` no se ejecuta nunca ahí. Lo destapó arrancar la app.
  WidgetsFlutterBinding.ensureInitialized();

  // La versión de verdad, para el saludo. Se lee aquí y se inyecta: el enlace no
  // tiene por qué saber leer el paquete de la app, y así las pruebas anuncian la
  // versión que quieran.
  final info = await PackageInfo.fromPlatform();
  runApp(
    ProviderScope(
      overrides: [appVersionProvider.overrideWithValue(info.version)],
      child: const NexusMovil(),
    ),
  );
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
      home: const _Arranque(),
    );
  }
}

/// Decide qué se ve: emparejar, o el Mac al otro lado.
///
/// La decisión vive **arriba** y no dentro de cada pantalla: si cada una preguntara
/// si hay emparejamiento, desemparejar dejaría la de dentro en pie hasta que alguien
/// navegara.
class _Arranque extends ConsumerWidget {
  const _Arranque();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pareja = ref.watch(pairingControllerProvider);

    return switch (pareja) {
      // Mientras se lee el llavero. Corto, pero existe: sin esto se vería un
      // pestañeo de la pantalla de emparejar en cada arranque **ya emparejado**.
      AsyncLoading() => const _Esperando(),
      // Sin emparejar se entra por el **escáner**, y escribirlo a mano está a un
      // toque desde ahí. No al revés: el QR es el camino cómodo y teclear 43
      // caracteres es la salida, no la puerta.
      AsyncError() => const ScanPage(),
      AsyncData(value: null) => const ScanPage(),
      // Emparejado: directo a la lista. La portada con el orbe cumplió su función
      // —demostrar que la app arranca compartiendo el diseño— y ahora sería un toque
      // de más antes de ver lo que importa.
      AsyncData(value: Pairing()) => const _Conectado(),
    };
  }
}

/// Emparejado: se conecta y se enseña la lista.
class _Conectado extends ConsumerWidget {
  const _Conectado();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Leerlo es lo que dispara conectar, y vive en un provider porque conectar
    // sobrevive a navegar: morir al entrar en una conversación desconectaría justo
    // al abrirla.
    ref.watch(autoConnectProvider);
    // Y esto es lo que hace que el teléfono se pinte con el color del Mac. Se lee
    // aquí, encima de la lista, porque tiene que estar escuchando **antes** del primer
    // saludo: el acento llega con él.
    ref.watch(accentFromMacProvider);

    final estado = ref.watch(linkStateProvider).value;
    // Mientras no esté conectado se enseña «buscando tu Mac», y con un mínimo en
    // pantalla: en la misma red el handshake tarda menos que un fotograma, así que sin
    // el mínimo esa pantalla parpadeaba y quedaba un salto raro.
    return MinimoEnPantalla(
      mostrar: estado != LinkState.conectado,
      despues: const ConversationsPage(),
      child: ConnectingPage(
        alCancelar: () =>
            ref.read(pairingControllerProvider.notifier).olvidar(),
      ),
    );
  }
}

class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.void_,
    body: const SizedBox.shrink(),
  );
}
