import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';

void main() {
  test('dos encargos sobre la misma carpeta no corren a la vez', () async {
    final queue = FolderErrandQueue();
    final orden = <String>[];

    final primero = queue.acquire('/repo').then((release) async {
      orden.add('entra A');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      orden.add('sale A');
      release();
    });

    // Se pide el turno con el primero todavía dentro: es el caso real de dos
    // conversaciones sobre el mismo repo.
    final segundo = queue.acquire('/repo').then((release) {
      orden.add('entra B');
      release();
    });

    await Future.wait([primero, segundo]);
    expect(orden, ['entra A', 'sale A', 'entra B']);
  });

  test('carpetas distintas no se estorban', () async {
    final queue = FolderErrandQueue();
    final orden = <String>[];

    final uno = queue.acquire('/repo-a').then((release) async {
      orden.add('entra A');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      release();
    });
    final otro = queue.acquire('/repo-b').then((release) {
      orden.add('entra B');
      release();
    });

    await Future.wait([uno, otro]);
    // B entra sin esperar a que A termine: su carpeta es otra.
    expect(orden, ['entra A', 'entra B']);
  });

  test('la carpeta libre no se declara ocupada', () async {
    final queue = FolderErrandQueue();
    expect(queue.isBusy('/repo'), isFalse);

    final release = await queue.acquire('/repo');
    expect(queue.isBusy('/repo'), isTrue);
    expect(queue.isBusy('/otro'), isFalse);

    release();
    // Y al soltar no queda rastro: si no, este mapa acumularía una entrada por
    // cada carpeta usada en toda la vida de la app.
    expect(queue.isBusy('/repo'), isFalse);
  });

  test('soltar dos veces no adelanta a nadie', () async {
    final queue = FolderErrandQueue();
    final release = await queue.acquire('/repo');
    release();
    release();

    final segundo = await queue
        .acquire('/repo')
        .timeout(const Duration(seconds: 1));
    segundo();
  });

  // El caso que dejaría la carpeta muerta para el resto de la sesión: si el
  // encargo de la otra conversación revienta, el siguiente tiene que entrar.
  test('un encargo que falla no bloquea la carpeta', () async {
    final queue = FolderErrandQueue();

    final roto = queue.acquire('/repo').then((release) {
      try {
        throw StateError('el encargo falló');
      } finally {
        release();
      }
    });
    await expectLater(roto, throwsStateError);

    final siguiente = await queue
        .acquire('/repo')
        .timeout(const Duration(seconds: 1));
    siguiente();
  });
}
