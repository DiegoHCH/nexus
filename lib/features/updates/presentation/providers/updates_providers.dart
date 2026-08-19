import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/updates/data/repositories/github_release_feed.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/repositories/release_feed.dart';
import 'package:package_info_plus/package_info_plus.dart';

final releaseFeedProvider = Provider<ReleaseFeed>(
  (ref) => const GitHubReleaseFeed(),
);

/// El reloj, inyectable: la política de esta feature **es** temporal, y probarla
/// con el reloj de verdad significaría esperar quince minutos.
final relojProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// La versión que corre, leída del paquete y no escrita a mano.
///
/// A mano se queda desfasada en cuanto alguien publique sin tocar la constante,
/// y entonces el aviso mentiría en la dirección peor: diciendo que estás al día.
final currentVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Si hay versión nueva, y cada cuánto se pregunta.
///
/// **Solo avisa.** No descarga ni instala, y menos aún reinicia: reiniciarse por
/// su cuenta sería matar un `claude -p` a media escritura, que es exactamente lo
/// que la ficha `le9` viene a impedir.
class UpdatesController extends Notifier<ReleaseCheck?> {
  /// Al volver a la ventana se pregunta como mucho con este hueco. Sin el tope,
  /// cambiar de app y volver diez veces son diez peticiones a GitHub.
  static const alVolver = Duration(minutes: 15);

  /// Y de fondo, cada tanto: sin esto, quien deja la app abierta días no se
  /// enteraría nunca.
  static const deFondo = Duration(hours: 2);

  DateTime? _ultima;
  Timer? _timer;

  @override
  ReleaseCheck? build() {
    _timer = Timer.periodic(deFondo, (_) => unawaited(_mirar()));
    ref.onDispose(() => _timer?.cancel());
    // Al arrancar, una vez.
    unawaited(_mirar());
    return null;
  }

  /// Se llama al volver a la ventana. Respeta el hueco.
  Future<void> alRegresar() async {
    final ahora = ref.read(relojProvider)();
    final ultima = _ultima;
    if (ultima != null && ahora.difference(ultima) < alVolver) return;
    await _mirar();
  }

  Future<void> _mirar() async {
    _ultima = ref.read(relojProvider)();
    final actual = await ref.read(currentVersionProvider.future);
    final publicada = await ref.read(releaseFeedProvider).latest();

    state = ReleaseCheck(
      current: actual,
      latest: publicada?.tag,
      url: publicada?.url,
    );
    // Queda registro, que es lo que pide la ficha: sin esto, «no me avisó» no se
    // puede distinguir de «no había nada».
    debugPrint(
      'actualizaciones · corriendo $actual · publicada ${publicada?.tag ?? "ninguna"}',
    );
  }
}

final updatesControllerProvider =
    NotifierProvider<UpdatesController, ReleaseCheck?>(UpdatesController.new);
