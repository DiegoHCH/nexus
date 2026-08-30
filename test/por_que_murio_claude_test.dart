import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/por_que_murio_claude.dart';

/// El peor fallo de la app era el que no decía nada.
///
/// La sesión de una cuenta caduca sola, sin tocar nada, y en pantalla salía
/// «claude terminó con código 1». El motivo venía en el mensaje y nadie lo
/// miraba.
void main() {
  group('la sesión caducada se reconoce', () {
    // Literal, tal como salió del CLI el día que pasó. Si algún día cambia la
    // redacción alrededor, esto sigue valiendo: se buscan dos señales, no la
    // frase.
    test('lo que dijo el CLI de verdad', () {
      expect(
        PorQueMurioClaude.esSesionCaducada(
          'claude terminó con código 1: Failed to authenticate: OAuth session '
          'expired and could not be refreshed',
        ),
        isTrue,
      );
    });

    test('en inglés de otra versión, y en cualquier caja', () {
      for (final salida in [
        'Authentication failed, your session has expired',
        'FAILED TO AUTHENTICATE: PLEASE LOG IN AGAIN',
      ]) {
        expect(
          PorQueMurioClaude.esSesionCaducada(salida),
          isTrue,
          reason: salida,
        );
      }
    });

    // La mitad que importa: pasarse de listo aquí convierte cualquier fallo en
    // «entra otra vez», y quien lo lea irá a reautenticarse por nada mientras
    // el problema de verdad sigue ahí.
    test('lo que no es una sesión caducada no se disfraza', () {
      for (final otro in [
        'claude terminó con código 1: ',
        'claude terminó con código 1: connection refused',
        'No conversation found with session ID abc123',
        'Error: ENOENT: no such file or directory',
        // Habla de expirar, pero no de autenticarse: es otra cosa.
        'the download link has expired',
        // Habla de autenticar, pero no de que caducara: una llave mal puesta
        // se arregla cambiándola, no volviendo a entrar.
        'Failed to authenticate: invalid API key',
      ]) {
        expect(PorQueMurioClaude.esSesionCaducada(otro), isFalse, reason: otro);
      }
    });
  });
}
