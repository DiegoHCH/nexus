import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
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
