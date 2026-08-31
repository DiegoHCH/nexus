import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/imagenes_section.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// «Hay overflow en el menú de imágenes» — la segunda vez, y por abajo.
///
/// La sección crece con las cuentas que tengas: con tres —la de siempre,
/// `private` y `work`— son tres etiquetas, tres campos y tres botones debajo
/// del selector, y deja de caber en el alto de Ajustes.
///
/// Se prueba **con la ventana baja y con varias cuentas**, que es donde ocurre.
/// Con una sola cuenta cabe, y por eso no se vio al escribirla.
class _SinLlaves implements GeminiImageKeyStore {
  const _SinLlaves();
  @override
  Future<String?> read(String? perfil) async => null;
  @override
  Future<void> save(String? perfil, String key) async {}
  @override
  Future<void> clear(String? perfil) async {}
}

void main() {
  Future<void> montar(WidgetTester tester, {required double alto}) async {
    tester.view.physicalSize = Size(700, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geminiImageKeyStoreProvider.overrideWithValue(const _SinLlaves()),
          claudeProfilesProvider.overrideWith(
            (ref) async => const [
              ClaudeProfile(
                path: '/Users/alguien/.claude-private',
                name: 'private',
                signedIn: true,
              ),
              ClaudeProfile(
                path: '/Users/alguien/.claude-work',
                name: 'work',
                signedIn: true,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: NexusTheme.dark(),
          builder: (context, child) =>
              StringsScope(strings: const NexusStringsEs(), child: child!),
          home: const Scaffold(
            body: SizedBox(width: 600, child: ImagenesSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cabe con tres cuentas en una ventana baja', (tester) async {
    await montar(tester, alto: 620);

    expect(
      tester.takeException(),
      isNull,
      reason: 'la sección crece con las cuentas y tiene que poder rodar',
    );
  });

  // Y lo que se explica arriba no puede contradecir al selector: decía «Gemini
  // 2.5 Flash Image» con Nano Banana 2 elegido debajo.
  testWidgets('la explicación no fija un modelo concreto', (tester) async {
    await montar(tester, alto: 900);

    expect(find.textContaining('2.5 Flash Image'), findsNothing);
  });
}
