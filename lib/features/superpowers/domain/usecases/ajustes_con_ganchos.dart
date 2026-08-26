import 'package:nexus/features/superpowers/domain/entities/nexus_hook.dart';

/// Cómo entra y sale un gancho del `settings.json` de una cuenta **sin tocar lo demás**.
///
/// Está aparte del disco a propósito. Ese archivo no es nuestro: lleva el modelo, el
/// esfuerzo, los permisos y los ganchos que haya puesto otra cosa —el de `ai-context`, sin
/// ir más lejos, vive en la cuenta por defecto—. Escribirlo mal no da un error: deja al
/// CLI arrancando sin nada de eso. Así que la parte que decide **qué queda escrito** se
/// prueba con mapas y sin archivos, que es donde se puede probar el caso raro.
abstract final class AjustesConGanchos {
  /// Cómo se reconoce una entrada nuestra: por dónde apunta, no por su texto.
  ///
  /// El nombre del gancho podría repetirlo cualquiera; la carpeta `nexus-hooks` la
  /// escribe solo esta app. Y por eso una entrada escrita a mano que apunte a otro sitio
  /// **no se toca**: no es nuestra, aunque haga lo mismo.
  static bool esNuestra(Object? comando, NexusHook gancho) =>
      comando is String && comando.contains('/nexus-hooks/${gancho.id}.py');

  /// Los ajustes con el gancho puesto, apuntando a [comando].
  ///
  /// Deja una sola entrada por gancho: si había otras nuestras —de una instalación
  /// anterior, o de cuando el archivo vivía en otra ruta— se retiran antes. Reinstalar
  /// tiene que dejar el archivo igual que instalar, o a la tercera vez el CLI llamaría al
  /// mismo script tres veces.
  static Map<String, Object?> con(
    Map<String, Object?> ajustes,
    NexusHook gancho, {
    required String comando,
    String? statusMessage,
  }) {
    final entrada = <String, Object?>{
      'type': 'command',
      'command': comando,
      'timeout': gancho.timeout,
      if (statusMessage != null && statusMessage.isNotEmpty)
        'statusMessage': statusMessage,
    };

    final limpio = sin(ajustes, gancho);
    final hooks = _mapa(limpio['hooks']);
    final delEvento = [
      ..._lista(hooks[gancho.event]),
      <String, Object?>{
        'matcher': gancho.matcher,
        'hooks': [entrada],
      },
    ];

    return {
      ...limpio,
      'hooks': {...hooks, gancho.event: delEvento},
    };
  }

  /// Los ajustes sin ninguna entrada nuestra de ese gancho.
  ///
  /// Se recorren **todos** los eventos y no solo el suyo: si un día un gancho cambia de
  /// `PreToolUse` a otro sitio, la entrada vieja se quedaría llamando a un script que ya
  /// no está y el CLI se quejaría en cada turno.
  ///
  /// Y se poda lo que queda vacío. Un `"PreToolUse": []` no rompe nada, pero convierte
  /// «no tengo ganchos» en un archivo que parece tenerlos.
  static Map<String, Object?> sin(
    Map<String, Object?> ajustes,
    NexusHook gancho,
  ) {
    final hooks = _mapa(ajustes['hooks']);
    if (hooks.isEmpty) return {...ajustes};

    final resultado = <String, Object?>{};
    for (final evento in hooks.entries) {
      final grupos = <Object?>[];
      for (final grupo in _lista(evento.value)) {
        final mapa = _mapa(grupo);
        final dentro = _lista(mapa['hooks'])
            .where((h) => !esNuestra(_mapa(h)['command'], gancho))
            .toList();
        // El grupo entero desaparece si lo único que tenía era nuestro. Si tenía más
        // —alguien metió dos ganchos en la misma entrada— se conserva con el resto.
        if (dentro.isEmpty) continue;
        grupos.add({...mapa, 'hooks': dentro});
      }
      if (grupos.isNotEmpty) resultado[evento.key] = grupos;
    }

    final copia = {...ajustes};
    if (resultado.isEmpty) {
      copia.remove('hooks');
    } else {
      copia['hooks'] = resultado;
    }
    return copia;
  }

  /// Si el CLI llama a ese gancho tal como lo instala Nexus.
  static bool registrado(Map<String, Object?> ajustes, NexusHook gancho) {
    for (final evento in _mapa(ajustes['hooks']).values) {
      for (final grupo in _lista(evento)) {
        for (final entrada in _lista(_mapa(grupo)['hooks'])) {
          if (esNuestra(_mapa(entrada)['command'], gancho)) return true;
        }
      }
    }
    return false;
  }

  /// Lo que venga que no sea un mapa se lee como vacío en vez de reventar.
  ///
  /// Un `settings.json` escrito a mano puede tener cualquier cosa dentro, y una excepción
  /// aquí dejaría la pantalla de Superpoderes en blanco por culpa de una línea ajena.
  static Map<String, Object?> _mapa(Object? valor) =>
      valor is Map ? valor.cast<String, Object?>() : const {};

  static List<Object?> _lista(Object? valor) =>
      valor is List ? valor : const [];
}
