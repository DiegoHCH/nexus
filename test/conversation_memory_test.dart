import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversation_memory_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/conversation_memory_impl.dart';

/// El almacén, sin tocar las preferencias del sistema.
class _FakeStore extends ConversationMemoryDataSource {
  _FakeStore([Map<String, dynamic>? initial]) : _data = initial ?? {};

  Map<String, dynamic> _data;

  @override
  Future<Map<String, dynamic>> read() async => _data;

  @override
  Future<void> write(Map<String, dynamic> value) async => _data = value;
}

void main() {
  const repoA = '/Users/alguien/repo-a';
  const repoB = '/Users/alguien/repo-b';

  test('una carpeta sin memoria no inventa nada', () async {
    final memory = ConversationMemoryImpl(_FakeStore());
    final read = await memory.read(repoA);

    expect(read.sessionId, isNull);
    expect(read.prompts, isEmpty);
  });

  // La regla del producto, y la que sostiene todo 3.4: la carpeta es la
  // frontera. Dos conversaciones sobre el mismo repo comparten sesión; dos
  // sobre repos distintos no se enteran la una de la otra.
  test('la memoria es de la carpeta, no del que pregunta', () async {
    final memory = ConversationMemoryImpl(_FakeStore());

    await memory.rememberSession(repoA, 'sesion-a');
    await memory.rememberPrompt(repoA, 'mira el historial');

    expect((await memory.read(repoA)).sessionId, 'sesion-a');
    expect((await memory.read(repoB)).sessionId, isNull);
    expect((await memory.read(repoB)).prompts, isEmpty);
  });

  test('lo último pedido va primero', () async {
    final memory = ConversationMemoryImpl(_FakeStore());

    await memory.rememberPrompt(repoA, 'primero');
    await memory.rememberPrompt(repoA, 'segundo');

    expect((await memory.read(repoA)).prompts, ['segundo', 'primero']);
  });

  test('repetir una petición la sube, no la duplica', () async {
    final memory = ConversationMemoryImpl(_FakeStore());

    await memory.rememberPrompt(repoA, 'corre los tests');
    await memory.rememberPrompt(repoA, 'mira el git');
    await memory.rememberPrompt(repoA, 'corre los tests');

    expect((await memory.read(repoA)).prompts, [
      'corre los tests',
      'mira el git',
    ]);
  });

  test('la lista tiene tope: es un panel, no un archivo histórico', () async {
    final memory = ConversationMemoryImpl(_FakeStore());
    for (var i = 0; i < 40; i++) {
      await memory.rememberPrompt(repoA, 'petición $i');
    }

    final prompts = (await memory.read(repoA)).prompts;
    expect(prompts, hasLength(30));
    expect(prompts.first, 'petición 39');
  });

  test('guardar la sesión no borra lo pedido, ni al revés', () async {
    final memory = ConversationMemoryImpl(_FakeStore());

    await memory.rememberPrompt(repoA, 'algo');
    await memory.rememberSession(repoA, 'sesion-1');
    await memory.rememberPrompt(repoA, 'otra cosa');

    final read = await memory.read(repoA);
    expect(read.sessionId, 'sesion-1');
    expect(read.prompts, ['otra cosa', 'algo']);
  });

  // «Empezar de cero» tira el contexto arrastrado, no la lista de lo pedido:
  // repetir una petición anterior sigue teniendo sentido.
  test('olvidar suelta la sesión y conserva el historial', () async {
    final memory = ConversationMemoryImpl(_FakeStore());
    await memory.rememberSession(repoA, 'sesion-1');
    await memory.rememberPrompt(repoA, 'algo');

    await memory.forget(repoA);

    final read = await memory.read(repoA);
    expect(read.sessionId, isNull);
    expect(read.prompts, ['algo']);
  });

  test('olvidar una carpeta no toca a las demás', () async {
    final memory = ConversationMemoryImpl(_FakeStore());
    await memory.rememberSession(repoA, 'sesion-a');
    await memory.rememberSession(repoB, 'sesion-b');

    await memory.forget(repoA);

    expect((await memory.read(repoB)).sessionId, 'sesion-b');
  });

  // Lo guardado puede venir de una versión anterior o corrompido a mano: leer
  // basura no puede tumbar el arranque, porque esto se lee al abrir la app.
  test('una entrada con forma rara se lee como vacía', () async {
    final memory = ConversationMemoryImpl(
      _FakeStore({
        repoA: 'esto no es un mapa',
        repoB: {'sessionId': 42, 'prompts': 'tampoco es una lista'},
      }),
    );

    expect((await memory.read(repoA)).prompts, isEmpty);
    expect((await memory.read(repoB)).prompts, isEmpty);
  });
}
