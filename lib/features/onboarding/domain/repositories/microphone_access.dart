/// Solo el permiso, no la captura — eso es la Fase 2 (2.2). La
/// configuración inicial necesita saber si Nexus puede llegar a escuchar,
/// nada más.
abstract class MicrophoneAccess {
  Future<bool> hasPermission();
}
