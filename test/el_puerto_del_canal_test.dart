import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';

// El puerto del canal: sus tipos y lo que calculan.
//
// Habla en tipos propios y **no en las entidades del asistente**, y eso es la
// decisión que esta prueba protege. `Conversation` ya tiene un `toJson` y era
// tentador reutilizarlo — pero ese `toJson` es para persistir, no para el cable.
// Compartirlos ataría el formato que viaja al formato que se guarda, y el que se
// rompería en silencio es el que ya está instalado en un teléfono.
void main() {
  group('el medidor viaja calculado', () {
    test('el porcentaje lo hace quien tiene el dato', () {
      // No se deja al teléfono, y hay una razón medida: el ancho de la ventana
      // depende de la variante del modelo, y en esta app se calculó mal una vez —
      // una sesión de un millón se enseñaba al 88 % porque se asumió 200k. Que lo
      // haga el que tiene el dato evita repetir el error en el otro extremo.
      const m = RemoteMeter(
        model: 'claude-opus-5[1m]',
        contextTokens: 175922,
        contextWindow: 1000000,
      );
      expect(m.percent, 18);
      expect(m.toJson()['percent'], 18);
    });

    test('sin datos no inventa un cero tranquilizador', () {
      expect(const RemoteMeter().percent, isNull);
      expect(const RemoteMeter(contextTokens: 100).percent, isNull);
      expect(const RemoteMeter(contextWindow: 200000).percent, isNull);
      // Y lo que es nulo no viaja: el teléfono distingue «no sé» de «cero».
      expect(const RemoteMeter().toJson().containsKey('percent'), isFalse);
    });

    test('acotado al 100, como en el escritorio', () {
      const m = RemoteMeter(contextTokens: 796410, contextWindow: 200000);
      expect(m.percent, 100);
    });
  });

  group('el permiso es un AND', () {
    final ahora = DateTime(2026, 8, 20, 12);

    test(
      'hace falta que la carpeta lo permita **y** que la ventana esté abierta',
      () {
        // Las cuatro combinaciones otra vez, por lo mismo: un AND mal escrito
        // acierta en tres.
        expect(
          RemotePermission(
            folderCanWrite: true,
            remoteWriteUntil: ahora.add(const Duration(minutes: 5)),
          ).canWriteAt(ahora),
          isTrue,
        );
        expect(
          const RemotePermission(
            folderCanWrite: true,
            remoteWriteUntil: null,
          ).canWriteAt(ahora),
          isFalse,
          reason: 'sin ventana no escribe, aunque la carpeta lo permita',
        );
        expect(
          RemotePermission(
            folderCanWrite: false,
            remoteWriteUntil: ahora.add(const Duration(minutes: 5)),
          ).canWriteAt(ahora),
          isFalse,
          reason: 'la ventana no sube lo que la carpeta niega',
        );
        expect(
          const RemotePermission(
            folderCanWrite: false,
            remoteWriteUntil: null,
          ).canWriteAt(ahora),
          isFalse,
        );
      },
    );

    test('una ventana caducada no vale', () {
      expect(
        RemotePermission(
          folderCanWrite: true,
          remoteWriteUntil: ahora.subtract(const Duration(seconds: 1)),
        ).canWriteAt(ahora),
        isFalse,
      );
    });
  });

  group('la paginación', () {
    test('sin más páginas, el cursor es nulo y no un final', () {
      // Un cursor que siempre existe invita a pedir una página más para siempre.
      const pagina = RemotePage<RemoteMessage>(items: []);
      expect(pagina.nextCursor, isNull);
    });
  });

  test('la conversación viaja con lo que el móvil manda y lo que muestra', () {
    // El `id` es lo que se manda —persiste entre arranques— y la carpeta es lo que
    // se muestra, porque un identificador no le dice nada a nadie.
    const c = RemoteConversation(
      id: 'abc',
      folder: '/Users/x/repo',
      focused: true,
    );
    expect(c.toJson(), {
      'id': 'abc',
      'folder': '/Users/x/repo',
      'focused': true,
    });
    // Y lo que no tiene foco no gasta un campo en decirlo.
    const otra = RemoteConversation(id: 'd', folder: '/y', focused: false);
    expect(otra.toJson().containsKey('focused'), isFalse);
  });

  test('pedir algo de una conversación que no existe tiene nombre', () {
    // El teléfono guarda ids, y una conversación se puede cerrar en el Mac
    // mientras el móvil la tenía en pantalla. Eso no es un fallo del canal: es una
    // respuesta, «vuelve a pedir la lista».
    const error = UnknownConversation('se-cerro');
    expect('$error', contains('se-cerro'));
  });
}
