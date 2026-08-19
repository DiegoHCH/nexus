import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';

/// Un micrófono concedido, para las pruebas que **no van del micrófono**.
///
/// Existe porque abrir la voz ahora consulta el permiso, y una prueba pura no
/// tiene binding: el canal nativo lanza «Binding has not yet been initialized» y
/// la prueba se cae por un camino que no tiene nada que ver con lo que afirma.
///
/// Se sustituye en vez de ensanchar el `catch` de la implementación de verdad:
/// tragarse cualquier error ahí taparía fallos reales del canal, y acomodar el
/// código de producción a las pruebas es hacerlo al revés.
class MicrofonoConcedido implements MicrophoneAccess {
  const MicrofonoConcedido();

  @override
  Future<MicrophoneStatus> status() async => MicrophoneStatus.granted;
}

/// Para las listas de `overrides`, que es donde se usa siempre.
///
/// Sin tipo escrito a mano y con el tipo inferido: `Override` **no está en la API
/// pública** de flutter_riverpod 3, así que nombrarlo no compila — la misma
/// piedra que ya está anotada en el arnés de pantallas.
final conMicrofono = microphoneAccessProvider.overrideWithValue(
  const MicrofonoConcedido(),
);
