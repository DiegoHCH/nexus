import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/appearance_channel.dart';
import 'package:nexus/core/diagnostico/registro_de_la_app.dart';
import 'package:nexus/core/diagnostico/registro_providers.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/theme_preference.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/platform/app_menu_channel.dart';
import 'package:nexus/features/artifacts/presentation/widgets/artifacts_sheet.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/presentation/widgets/conversation_history_sheet.dart';
import 'package:nexus/features/onboarding/presentation/pages/app_root.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/agenda/presentation/providers/el_vigilante_de_la_agenda.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/presentation/widgets/el_permiso_dialogo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **Lo primero de todo.** Enganchar el registro después de arrancar dejaría
  // fuera justo los fallos del arranque, que son los que menos se pueden
  // reproducir después.
  final registro = RegistroDeLaApp();
  engancharElRegistro(registro);
  debugPrint('nexus · arranca');

  // Los atajos globales los registra el sistema, no la app: sobreviven a un
  // hot reload y quedarían duplicados —o peor, huérfanos— sin esta limpieza
  // al arrancar.
  await hotKeyManager.unregisterAll();
  runApp(
    ProviderScope(
      // El mismo que ya está escribiendo, para que Ajustes pueda decir dónde
      // vive. Construir otro daría una segunda ruta y ninguna sería la buena.
      overrides: [registroDeLaAppProvider.overrideWithValue(registro)],
      child: const MainApp(),
    ),
  );
}

/// Deja escrito en el registro todo lo que la app cuente de sí misma.
///
/// Tres fuentes, y las tres hacían falta:
///
/// **`debugPrint`**, envuelto en vez de sustituido en los 41 sitios que lo
/// llaman. Sigue imprimiendo en la consola de `flutter run` —que es para lo que
/// sirve— y además cae en el archivo, que es lo que faltaba en release.
///
/// **Los errores del framework**, que hoy se pintan en la consola y ahí mueren.
/// Un `RenderFlex overflowed` en el Mac de otro no lo cuenta nadie.
///
/// **Lo que escapa de una zona asíncrona**, que ni siquiera llega a la consola
/// en release. Se devuelve `false` a propósito: manejarlo aquí sería tragárselo,
/// y esto solo viene a mirar.
void engancharElRegistro(RegistroDeLaApp registro) {
  final imprimirDeAntes = debugPrint;
  debugPrint = (String? mensaje, {int? wrapWidth}) {
    imprimirDeAntes(mensaje, wrapWidth: wrapWidth);
    if (mensaje != null && mensaje.trim().isNotEmpty) {
      unawaited(registro.anotar(mensaje));
    }
  };

  final erroresDeAntes = FlutterError.onError;
  FlutterError.onError = (detalles) {
    erroresDeAntes?.call(detalles);
    unawaited(
      registro.anotar('error de interfaz · ${detalles.exceptionAsString()}'),
    );
  };

  PlatformDispatcher.instance.onError = (error, pila) {
    unawaited(registro.anotar('error suelto · $error'));
    // `false`: no se da por manejado. Lo de aquí es enterarse, no decidir.
    return false;
  };
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  /// Los ajustes se abren desde el menú de macOS, que no tiene un `context` a
  /// mano. Esta llave es ese `context`.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    AppMenuChannel.listen(
      onOpenSettings: _openSettings,
      onOpenHistory: _openHistory,
      onOpenArtifacts: _openArtifacts,
    );
  }

  /// Los documentos generados (⌘J). No dependen de la conversación abierta —un
  /// mockup de ayer sigue siendo tuyo hoy—, así que basta con el navegador.
  void _openArtifacts() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    ArtifactsSheet.open(navigator.context);
  }

  void _openSettings() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    SettingsPage.open(navigator.context);
  }

  /// El historial es **de una carpeta**, no de una conversación abierta.
  ///
  /// Esa confusión lo dejaba mudo justo cuando más se necesita: recién abierta
  /// la app, sin ningún chat en marcha, pedir el historial es exactamente lo
  /// que uno hace para retomar algo de ayer. Así que si no hay conversación en
  /// foco se usa la carpeta activa, y al elegir una conversación se abre una
  /// conversación nueva sobre esa carpeta para volcarla dentro.
  Future<void> _openHistory() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final focused = ref.read(conversationsProvider).focused;
    final workspace = ref.read(workspaceControllerProvider);
    final folder =
        focused?.folderPath ??
        workspace.activePath ??
        workspace.folders.firstOrNull?.path;
    if (folder == null) return;

    await ConversationHistorySheet.open(
      navigator.context,
      forgetFolder: focused == null ? null : folder.split('/').last,
      onPick: (record) async {
        // El mensajero **se coge antes del `await`**, no después: buscar el
        // `BuildContext` cuando la espera ya pasó es usar un contexto que puede no
        // estar montado, y el analizador lo marca con razón. Cogerlo antes no
        // cuesta nada cuando no hace falta.
        final mensajero = ScaffoldMessenger.maybeOf(navigator.context);

        // La decisión vive en su proveedor, que es quien sabe qué hay abierto.
        // Aquí solo queda contar los desenlaces que necesitan palabras.
        final resultado = await ref.read(retomarDelArchivoProvider)(record);
        final aviso = switch (resultado) {
          RetomarResultado.noCabe =>
            'Ya hay ${Conversations.max} conversaciones abiertas. Cierra una '
                'para retomar esta.',
          // La ficha estaba en la lista pero detrás no hay nada: la nota se
          // borró desde Obsidian, o el archivo se fue con una limpieza. Callar
          // aquí se lee como que el clic no hizo nada.
          RetomarResultado.noEsta =>
            'Esa conversación ya no está donde se guardó.',
          RetomarResultado.yaEstaba || RetomarResultado.enPestanaNueva => null,
        };
        if (aviso == null) return;

        mensajero?.showSnackBar(SnackBar(content: Text(aviso)));
      },
      onForget: () {
        final id = focused?.id;
        if (id == null) return;
        ref.read(assistantControllerProvider(id).notifier).forgetConversation();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // No es const: theme/darkTheme llaman a NexusTheme.light()/.dark(), que
    // arman un ThemeData vía ColorScheme.fromSeed. Ni fromSeed ni ThemeData
    // tienen constructor const, así que no hay forma de recuperar el const
    // que tenía este MaterialApp sin abandonar fromSeed por un ColorScheme
    // literal con sus ~40 campos a mano. El costo real es nulo: light()/
    // dark() cachean el resultado, ahora por acento en un mapa.
    final locale = ref.watch(localeProvider);
    // El acento elegido en la rueda. El tema claro no puede usar el mismo tono
    // que el oscuro y seguir siendo legible, así que cada uno pide el suyo.
    final acento = ref.watch(accentControllerProvider);

    // El marco de la ventana va por libre —es AppKit— así que se le avisa cada
    // vez que cambia lo que toca pintar. `ref.listen` y no una llamada en el
    // build: esto es un efecto sobre el sistema, no parte de dibujar.
    ref.listen(isDarkProvider, (previous, next) {
      if (previous != next) AppearanceChannel.apply(dark: next);
    });
    // Y la primera vez, que `listen` no dispara solo: al arrancar, el marco lo
    // puso Swift con lo que dice el sistema, y aquí ya se sabe si el usuario
    // eligió otra cosa.
    AppearanceChannel.apply(dark: ref.watch(isDarkProvider));

    // **El canal del móvil, vivo desde el arranque.**
    //
    // Se mira aquí y no solo en su pantalla porque hasta ahora lo único que lo
    // construía era la sección «Móvil» de Ajustes: el «si estaba encendido, se
    // vuelve a encender» únicamente ocurría si abrías esa pantalla, y las veces que
    // el teléfono conectó «solo» fue porque la app había reabierto justo ahí. Con la
    // ventana en el HUD no escuchaba nadie, y el teléfono decía «no se llega» sin que
    // hubiera nada que arreglar en el teléfono.
    //
    // Es lo que hace verdad la promesa de recordarlo: la razón de encender el canal
    // es precisamente no tener que tocar el Mac.
    ref.watch(channelControllerProvider);

    // **Y el vigilante de la agenda, por lo mismo y por segunda vez.**
    //
    // 🔴 Es el bug de arriba otra vez: lo único que construía el vigilante era la
    // sección «Avisos» de Ajustes, así que el reloj que dispara los avisos no
    // existía hasta que abrías esa pantalla. El interruptor quedaba guardado
    // diciendo que sí y no armaba nada, y cada relanzamiento volvía a empezar sin
    // vigilante — con la app abierta toda la mañana y ni un aviso.
    //
    // Que haya pasado dos veces dice algo del patrón: un provider perezoso que
    // *hace* algo por su cuenta no puede tener como único testigo la pantalla que
    // lo configura. Se arma donde vive la app, no donde se ajusta.
    ref.watch(elVigilanteDeLaAgendaProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      // La cinta de «DEBUG» fuera: esta app se usa a diario en compilación de
      // depuración —es su forma normal de correr, no una prueba de un rato— y
      // la cinta tapa la esquina del HUD.
      debugShowCheckedModeBanner: false,
      // El tono ya ajustado para cada tema: se elige el color y la app le busca
      // el brillo que cumple contraste sobre los fondos que toquen.
      theme: NexusTheme.light(accent: acento.forBrightness(Brightness.light)),
      darkTheme: NexusTheme.dark(accent: acento.forBrightness(Brightness.dark)),
      themeMode: ref.watch(themeControllerProvider).mode,
      locale: locale,
      supportedLocales: NexusStrings.supported,
      // Los de Flutter, para que los widgets de Material —menús, selección de
      // texto— hablen el mismo idioma que la app y no se queden en inglés.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Por encima del Navigator, no envolviendo `home`: Ajustes se abre como
      // una ruta nueva, y esas se construyen **fuera** del hijo de `home`. Con
      // el scope ahí abajo, abrir Ajustes reventaba con «falta un
      // StringsScope» — y solo en esa pantalla, que es lo que lo hacía fácil
      // de no ver hasta usarla.
      builder: (context, child) => StringsScope(
        strings: NexusStrings.of(locale),
        // El permiso, por el mismo motivo que el scope y un párrafo más
        // arriba: Ajustes es una ruta nueva y se construye **fuera** del hijo
        // de `home`. Colgado de la pantalla principal, abrir Ajustes con una
        // pregunta en pie la tapaba — y como al otro lado hay un proceso
        // detenido esperando, taparla es dejar el encargo colgado hasta que
        // alguien cierre Ajustes sin saber por qué.
        //
        // El `Stack` va suelto y no en `expand`: aquí el hijo ya recibe el
        // tamaño entero de la ventana, así que las dos formas miden igual
        // —medido— y la suelta no promete nada que no haga falta.
        child: Stack(children: [child!, ElPermisoDialogo.enElArbol()]),
      ),
      home: const AppRoot(),
    );
  }
}
