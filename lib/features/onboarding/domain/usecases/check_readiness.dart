import 'dart:async';

import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/domain/entities/readiness.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';

/// Si Nexus puede trabajar, preguntado en el arranque.
///
/// Existe porque la puerta solo miraba la llave de Gemini: **Claude Code no se
/// comprobaba nunca**, y es la mitad entera de «las manos». Sin el binario, el
/// primer encargo moría en una `ProcessException` que no dice qué hacer.
class CheckReadiness extends UseCase<Readiness, NoParams> {
  const CheckReadiness(this._probe, this._keyStore, {this.timeout = _default});

  static const _default = Duration(seconds: 4);

  final ReadinessProbe _probe;
  final GeminiKeyStore _keyStore;

  /// Con plazo porque esto corre **delante del splash**: un CLI colgado dejaría
  /// la app mirando el orbe para siempre. Agotarlo no es «falta», es «no se
  /// sabe» — y eso no bloquea.
  final Duration timeout;

  @override
  Future<Readiness> call(NoParams params) async {
    final key = await _keyStore.read();
    final cli = await _ask(_probe.cliInstalled);
    // Sin binario no se le puede preguntar por la sesión, y contestar «no hay»
    // sería inventarse una segunda cosa rota a partir de la primera.
    final session = cli == CheckResult.ok
        ? await _ask(_probe.anySession)
        : CheckResult.unknown;

    return Readiness(
      cli: cli,
      session: session,
      geminiKey: key != null && key.isNotEmpty,
    );
  }

  Future<CheckResult> _ask(Future<bool> Function() probe) async {
    try {
      final yes = await probe().timeout(timeout);
      return yes ? CheckResult.ok : CheckResult.failed;
    } on TimeoutException {
      return CheckResult.unknown;
    } on Exception {
      // Lo inesperado tampoco es una respuesta. Se deja pasar.
      return CheckResult.unknown;
    }
  }
}
