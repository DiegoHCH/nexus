import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/core/platform/claude_cli.dart';
import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/domain/entities/readiness.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';
import 'package:nexus/features/onboarding/domain/usecases/check_readiness.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

/// El arranque solo comprobaba la llave de Gemini.
///
/// **Claude Code no se verificaba nunca** — ni que el binario esté ni que haya
/// sesión — y es la mitad entera de «las manos»: el CLI se lanza con
/// `Process.start('claude', …)`, así que sin él el primer encargo moría en una
/// `ProcessException`, un fallo sin frase.
/// El workspace guardado: lo que ahora decide a qué pantalla se entra.
class _Guardado implements WorkspaceStore {
  const _Guardado({this.conCarpeta = true});

  final bool conCarpeta;

  @override
  Future<Workspace> read() async => Workspace(
    folders: conCarpeta
        ? const [PairedFolder(path: '/repo', modality: FolderModality.textOnly)]
        : const [],
  );

  @override
  Future<void> save(Workspace workspace) async {}
}

void main() {
  group('lo que se le pregunta al CLI', () {
    test('sin binario, «no está» — y no revienta', () async {
      final cli = ClaudeCli(
        run: (executable, args, {environment}) =>
            throw const ProcessException('claude', [], 'no such file', 2),
      );
      expect(await cli.installed(), isFalse);
    });

    test('con binario que arranca, «está»', () async {
      final cli = ClaudeCli(
        run: (executable, args, {environment}) async {
          expect(args, ['--version']);
          return ProcessResult(1, 0, '2.1.0', '');
        },
      );
      expect(await cli.installed(), isTrue);
    });

    test('la sesión se lee del JSON del CLI, no del llavero', () async {
      final cli = ClaudeCli(
        run: (executable, args, {environment}) async =>
            ProcessResult(1, 0, '{"loggedIn": true}', ''),
      );
      expect(await cli.loggedIn(null), isTrue);
    });

    test('y un código de salida distinto de cero es «no»', () async {
      final cli = ClaudeCli(
        run: (executable, args, {environment}) async =>
            ProcessResult(1, 1, '', 'not logged in'),
      );
      expect(await cli.loggedIn(null), isFalse);
    });
  });

  group('el informe', () {
    Future<Readiness> informe({
      required bool cli,
      required bool session,
      String? key = 'una-llave',
      Duration cliTarda = Duration.zero,
    }) => CheckReadiness(
      _Sonda(cli: cli, session: session, tarda: cliTarda),
      _Llavero(key),
      timeout: const Duration(milliseconds: 50),
    )(const NoParams());

    test('sin binario no se afirma nada sobre la sesión', () async {
      // Preguntarle a un binario que no está y concluir «no hay sesión» sería
      // inventarse una segunda cosa rota a partir de la primera.
      final r = await informe(cli: false, session: false);
      expect(r.cli, CheckResult.failed);
      expect(r.session, CheckResult.unknown);
      expect(r.blocksWork, isTrue);
    });

    test('con binario y sin sesión, bloquea', () async {
      final r = await informe(cli: true, session: false);
      expect(r.cli, CheckResult.ok);
      expect(r.session, CheckResult.failed);
      expect(r.blocksWork, isTrue);
    });

    test('con todo, no bloquea', () async {
      final r = await informe(cli: true, session: true);
      expect(r.blocksWork, isFalse);
    });

    // Lo que separa esto de un `bool`: agotar el plazo **no es** que falte algo.
    test('si la pregunta se cuelga, no se sabe — y no bloquea', () async {
      final r = await informe(
        cli: true,
        session: true,
        cliTarda: const Duration(seconds: 5),
      );
      expect(r.cli, CheckResult.unknown);
      expect(r.session, CheckResult.unknown, reason: 'ni se llegó a preguntar');
      expect(
        r.blocksWork,
        isFalse,
        reason: 'acusar de algo que no se comprobó es peor que dejar pasar',
      );
    });

    test('la llave de Gemini se lee, pero no bloquea el trabajo', () async {
      final sinLlave = await informe(cli: true, session: true, key: null);
      expect(sinLlave.geminiKey, isFalse);
      expect(
        sinLlave.blocksWork,
        isFalse,
        reason: 'sin Gemini se puede trabajar por texto',
      );
    });
  });

  group('a qué pantalla se va', () {
    Future<AppRouteState> arranque({
      required bool cli,
      required bool session,
      String? key = 'una-llave',
      bool conCarpeta = true,
    }) async {
      final container = ProviderContainer(
        overrides: [
          geminiKeyStoreProvider.overrideWithValue(_Llavero(key)),
          readinessProbeProvider.overrideWithValue(
            _Sonda(cli: cli, session: session),
          ),
          workspaceStoreProvider.overrideWithValue(
            _Guardado(conCarpeta: conCarpeta),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appRouteControllerProvider, (_, _) {});
      // El splash tiene un mínimo de 900 ms a propósito.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      return container.read(appRouteControllerProvider);
    }

    test('sin Claude Code se dice qué falta antes de entrar', () async {
      final state = await arranque(cli: false, session: false);
      expect(state, isA<AppRouteNotReady>());
      expect((state as AppRouteNotReady).readiness.cli, CheckResult.failed);
    });

    test('sin sesión, igual — y la pantalla sabe cuál de las dos es', () async {
      final state = await arranque(cli: true, session: false);
      expect(state, isA<AppRouteNotReady>());
      final r = (state as AppRouteNotReady).readiness;
      expect(r.cli, CheckResult.ok);
      expect(r.session, CheckResult.failed);
    });

    test('con todo listo y una carpeta, directo a Reposo', () async {
      expect(await arranque(cli: true, session: true), isA<AppRouteReady>());
    });

    // El orden importa: lo del sistema va delante de lo de la app. Sin las manos,
    // la llave de Gemini solo consigue que te contesten sin poder hacer nada.
    test('lo que falta del sistema se dice antes que lo de la app', () async {
      expect(
        await arranque(cli: false, session: false, key: null),
        isA<AppRouteNotReady>(),
      );
    });

    // La regla que cambió: decide la carpeta, no la llave. Este grupo ya tenía
    // escrito, doce líneas más arriba, que «sin Gemini se puede trabajar por
    // texto» — y la puerta decía lo contrario.
    test('listo y sin llave se entra: la voz es lo único que falta', () async {
      expect(
        await arranque(cli: true, session: true, key: null),
        isA<AppRouteReady>(),
      );
    });

    test('listo y sin carpeta, a la configuración', () async {
      expect(
        await arranque(cli: true, session: true, conCarpeta: false),
        isA<AppRouteNeedsSetup>(),
      );
    });
  });

  group('las dos salidas de la pantalla', () {
    ProviderContainer contenedor({
      String? key = 'una-llave',
      bool conCarpeta = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          geminiKeyStoreProvider.overrideWithValue(_Llavero(key)),
          readinessProbeProvider.overrideWithValue(
            const _Sonda(cli: false, session: false),
          ),
          workspaceStoreProvider.overrideWithValue(
            _Guardado(conCarpeta: conCarpeta),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appRouteControllerProvider, (_, _) {});
      return container;
    }

    test('«entrar de todas formas» no deja a nadie encerrado fuera', () async {
      final container = contenedor();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        container.read(appRouteControllerProvider),
        isA<AppRouteNotReady>(),
      );

      container.read(appRouteControllerProvider.notifier).continueAnyway();
      expect(container.read(appRouteControllerProvider), isA<AppRouteReady>());
    });

    test('y sin carpeta lleva a la configuración, no a Reposo', () async {
      final container = contenedor(conCarpeta: false);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      container.read(appRouteControllerProvider.notifier).continueAnyway();
      expect(
        container.read(appRouteControllerProvider),
        isA<AppRouteNeedsSetup>(),
        reason: 'saltarse la comprobación no es saltarse la configuración',
      );
    });

    test('«comprobar de nuevo» vuelve a pasar por el splash', () async {
      final container = contenedor();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      container.read(appRouteControllerProvider.notifier).recheck();
      expect(
        container.read(appRouteControllerProvider),
        isA<AppRouteLoading>(),
        reason: 'un botón que no cambia nada durante un segundo se siente roto',
      );
    });
  });
}

class _Sonda implements ReadinessProbe {
  const _Sonda({
    required this.cli,
    required this.session,
    this.tarda = Duration.zero,
  });

  final bool cli;
  final bool session;
  final Duration tarda;

  @override
  Future<bool> cliInstalled() => Future<bool>.delayed(tarda, () => cli);

  @override
  Future<bool> anySession() async => session;
}

class _Llavero implements GeminiKeyStore {
  const _Llavero(this._value);

  final String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> save(String key) async {}
}
