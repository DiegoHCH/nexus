import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// El puente hacia `claude -p` headless. Cada llamada a [ask] es un turno
/// independiente: no mantiene una sesión abierta entre instrucciones (eso es
/// trabajo de la Fase 3, con `--resume`).
abstract class ClaudeBridge {
  Stream<ClaudeEvent> ask(String instruction);
}
