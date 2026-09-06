import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'microfono.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abrir una pantalla de verdad, con lo de fuera sustituido.
///
/// Existe por la deuda b12: en un solo día se rompieron tres pantallas —una
/// fuera del alcance de los textos, una sección que existía y no estaba en el
/// menú, y una lectura de providers en mitad del build— **con el análisis
/// limpio y todas las pruebas en verde**. Todas las pruebas eran de reglas, y
/// esos tres fallos son de montaje: solo aparecen al abrir la pantalla.
///
/// Así que esto no comprueba lógica. Comprueba que **abre y pinta**, que es
/// justo lo que ninguna prueba hacía.

/// El micrófono, que en una prueba no existe: sin esto, cualquier pantalla que
/// enseñe la prueba de sonido revienta al pedir permiso.
class FakeVoiceInput implements VoiceInput {
  @override
  Stream<void> get pausas => const Stream<void>.empty();

  const FakeVoiceInput({this.granted = true});

  final bool granted;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Stream<AudioFrame> listen() => const Stream.empty();
}

/// La máquina, que en una prueba tampoco existe.
///
/// **Hace falta desde que los dispositivos están en el compositor**: el icono
/// mira la lista para saber si enciende su punto, y el compositor se monta en
/// casi todas las pruebas de pantalla. Sin esto, cada una lanzaría
/// `flutter emulators` y un par de `adb` de verdad —segundos por prueba— y su
/// plazo de espera deja un `Timer` vivo cuando el árbol ya se tiró: «A Timer is
/// still pending even after the widget tree was disposed». Diecisiete pruebas a
/// la vez, y ninguna por su culpa.
///
/// Va aquí y no en cada archivo por el mismo motivo que el micrófono falso: es
/// una puerta al sistema, y este arnés existe para cerrarlas todas de una vez.
class SinDispositivos extends EmuladoresDataSource {
  const SinDispositivos();

  @override
  Future<({List<Emulador> emuladores, String? error})> listar() async =>
      (emuladores: const <Emulador>[], error: null);

  @override
  Future<List<DispositivoConectado>> listarDispositivos() async => const [];
}

class FixedWorkspace extends WorkspaceController {
  FixedWorkspace(this._value);

  final Workspace _value;

  @override
  Workspace build() => _value;
}

/// Un espacio de trabajo cualquiera, con una carpeta emparejada.
Workspace workspaceWith({
  String path = '/Users/alguien/proyecto',
  FolderModality modality = FolderModality.voice,
}) => Workspace(
  folders: [PairedFolder(path: path, modality: modality)],
  activePath: path,
);

/// Deja el entorno de plataforma en un estado en el que una prueba puede
/// correr: preferencias vacías, un directorio de soporte temporal, y los
/// canales nativos contestando lo justo.
///
/// Se llama en `setUp`. Devuelve la carpeta temporal para poder borrarla.
Directory prepareScreenTest() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final support = Directory.systemTemp.createTempSync('nexus_pantalla');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => support.path,
  );
  // El atajo global se registra al abrir la casa. En una prueba no hay nadie al
  // otro lado del canal, y sin esto la pantalla principal ni se monta.
  messenger.setMockMethodCallHandler(
    const MethodChannel('hotkey_manager'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('nexus/audio'),
    (call) async => call.method == 'hasPermission' ? true : null,
  );

  return support;
}

/// Monta una pantalla como la monta la app: con sus textos por encima del
/// navegador, su tema y su ámbito de providers.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {

  /// La ventana de verdad, no los 800×600 de fábrica de una prueba: esta app
  /// es de escritorio y a 800 de ancho no cabe ni su barra superior. Aun así
  /// una pantalla no debería desbordar nunca — la primera prueba que abrió
  /// Ajustes encontró justo eso.
  Size size = const Size(1280, 800),
  // `List<Object>` y no el tipo de verdad: `Override` no está en la API
  // pública de flutter_riverpod 3, así que no se puede nombrar desde aquí. El
  // `cast()` de abajo lo recupera sin importar sus tripas, que es lo que
  // rompería con la próxima versión.
  List<Object> overrides = const [],

  /// Si la pantalla de arranque puede abrir su puerta de voz.
  ///
  /// 🔴 **Apagada por defecto.** Sin conversaciones, la casa saluda y pregunta
  /// dónde se trabaja, y mientras esa puerta está abierta **no hay caja de
  /// texto** — que es justo lo que mira la mitad de estas pruebas. Encenderla
  /// aquí y no con un `override` suelto porque Riverpod 3 no deja pisar dos
  /// veces el mismo proveedor: el arnés ya pone uno.
  bool conPuerta = false,

  /// El tema con el que se dibuja. Existe porque **el tema claro nunca se
  /// había mirado**: estaba construido y cableado, pero sin forma de elegirlo
  /// nadie lo vio nunca puesto, así que ninguna pantalla se había comprobado
  /// en claro. Un desbordamiento o un texto ilegible ahí no rompen ninguna
  /// regla — solo se ven.
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceInputProvider.overrideWithValue(const FakeVoiceInput()),
        // 🔴 **Sin micrófono por defecto, y a propósito.** Al arrancar sin
        // conversaciones la pantalla abre una sesión de voz que saluda y
        // pregunta dónde se trabaja; una prueba de pantalla no quiere levantar
        // eso —ni salir a la red— y mientras la puerta está abierta no hay caja
        // de texto, que es lo que la mitad de estas pruebas mira.
        //
        // Quien sí prueba la puerta pone `conMicrofono` en sus propios
        // `overrides`, que van después y ganan.
        microphoneAccessProvider.overrideWithValue(
          conPuerta ? const MicrofonoConcedido() : const MicrofonoDenegado(),
        ),
        emuladoresDataSourceProvider.overrideWithValue(const SinDispositivos()),
        ...overrides.cast(),
      ],
      child: MaterialApp(
        theme: theme ?? NexusTheme.dark(),
        builder: (context, child) =>
            StringsScope(strings: const NexusStringsEs(), child: child!),
        home: screen,
      ),
    ),
  );
  // Dos bombeos y no `pumpAndSettle`: varias pantallas tienen animaciones que
  // no paran nunca —el orbe gira siempre— y esperar a que se asienten sería
  // esperar para siempre.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
