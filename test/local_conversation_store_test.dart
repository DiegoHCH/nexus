import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';

ConversationRecord record({
  String id = 'c1',
  String folder = '/Users/alguien/workspace',
  DateTime? when,
  List<ChatMessage>? messages,
}) => ConversationRecord(
  id: id,
  folderPath: folder,
  startedAt: when ?? DateTime(2026, 8, 12, 19, 30),
  messages:
      messages ??
      const [
        ChatMessage(
          author: ChatAuthor.user,
          text: 'mira el historial',
          spoken: true,
        ),
        ChatMessage(author: ChatAuthor.nexus, text: 'tres commits sin subir'),
      ],
);

void main() {
  late Directory support;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    support = Directory.systemTemp.createTempSync('nexus_soporte');
    // path_provider habla con la plataforma, que en una prueba no existe.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => support.path,
        );
  });

  tearDown(() => support.deleteSync(recursive: true));

  const store = LocalConversationStore();

  test('listar trae la ficha: título, fecha y cuántos turnos', () async {
    await store.save(record());

    final leidas = await store.list('/Users/alguien/workspace');

    expect(leidas, hasLength(1));
    expect(leidas.single.title, 'mira el historial');
    expect(leidas.single.turns, 2);
  });

  test('y abrir una trae la conversación entera', () async {
    await store.save(record());

    final ficha = (await store.list('/Users/alguien/workspace')).single;
    final entera = await store.read(ficha);

    expect(entera!.messages, hasLength(2));
    // Se conserva si se dijo por voz: meses después, eso explica una
    // transcripción rara.
    expect(entera.messages.first.spoken, isTrue);
  });

  test('lo más reciente va primero', () async {
    await store.save(record(id: 'vieja', when: DateTime(2026, 8, 1)));
    await store.save(
      record(
        id: 'nueva',
        when: DateTime(2026, 8, 12),
        messages: const [
          ChatMessage(author: ChatAuthor.user, text: 'lo último'),
        ],
      ),
    );

    final leidas = await store.list('/Users/alguien/workspace');

    expect(leidas.map((r) => r.id), ['nueva', 'vieja']);
  });

  // La regla de todo el producto: la carpeta es la frontera. El historial de un
  // proyecto no puede enseñar el de otro.
  test('cada carpeta ve solo lo suyo', () async {
    await store.save(record());
    await store.save(
      record(
        id: 'c2',
        folder: '/Users/alguien/otro',
        messages: const [
          ChatMessage(author: ChatAuthor.user, text: 'del otro'),
        ],
      ),
    );

    expect(await store.list('/Users/alguien/workspace'), hasLength(1));
    expect((await store.list('/Users/alguien/otro')).single.title, 'del otro');
  });

  // Dos proyectos pueden llamarse igual estando en sitios distintos, así que la
  // identidad es la ruta entera y no el nombre de la carpeta.
  test('dos carpetas con el mismo nombre no se mezclan', () async {
    await store.save(record(folder: '/trabajo/api'));
    await store.save(
      record(
        id: 'c2',
        folder: '/personal/api',
        messages: const [ChatMessage(author: ChatAuthor.user, text: 'la mía')],
      ),
    );

    expect((await store.list('/trabajo/api')).single.id, 'c1');
    expect((await store.list('/personal/api')).single.title, 'la mía');
  });

  test('guardar dos veces la misma conversación la actualiza', () async {
    await store.save(record());
    await store.save(
      record(
        messages: const [
          ChatMessage(author: ChatAuthor.user, text: 'mira el historial'),
          ChatMessage(author: ChatAuthor.nexus, text: 'tres commits sin subir'),
          ChatMessage(author: ChatAuthor.user, text: 'súbelos'),
        ],
      ),
    );

    final leidas = await store.list('/Users/alguien/workspace');
    expect(leidas, hasLength(1));
    expect(leidas.single.turns, 3);
  });

  test('una conversación en la que nadie dijo nada no se guarda', () async {
    await store.save(record(messages: const []));
    expect(await store.list('/Users/alguien/workspace'), isEmpty);
  });

  // Perder una conversación rota es molesto; perder el historial entero por
  // ella, inaceptable.
  test('un archivo ilegible se salta, y el resto se lee', () async {
    await store.save(record());
    final carpeta = Directory(
      '${support.path}/conversaciones/Users-alguien-workspace',
    );
    File('${carpeta.path}/roto.json').writeAsStringSync('esto no es JSON');
    File(
      '${carpeta.path}/sin-fecha.json',
    ).writeAsStringSync(jsonEncode({'id': 'x'}));

    expect(await store.list('/Users/alguien/workspace'), hasLength(1));
  });

  test('se puede borrar una', () async {
    await store.save(record());
    await store.delete(record().summary);

    expect(await store.list('/Users/alguien/workspace'), isEmpty);
  });

  // El índice es lo que hace que listar no cueste abrir todas. Estas tres
  // pruebas son sobre él: que exista, que no se crea a sí mismo cuando el disco
  // dice otra cosa, y que listar no dependa de poder leer las conversaciones.
  group('el índice', () {
    Directory carpetaDe(String slug) =>
        Directory('${support.path}/conversaciones/$slug');

    test('se escribe al guardar', () async {
      await store.save(record());

      final indice = File(
        '${carpetaDe('Users-alguien-workspace').path}/_index.json',
      );
      expect(indice.existsSync(), isTrue);
      final decoded = jsonDecode(indice.readAsStringSync()) as Map;
      expect((decoded['conversaciones'] as List), hasLength(1));
    });

    test('listar no abre las conversaciones', () async {
      await store.save(record());
      // Se deja el índice y se rompe la conversación: si listar necesitara
      // abrirla, esto se notaría. Como solo lee el índice, no.
      File(
        '${carpetaDe('Users-alguien-workspace').path}/c1.json',
      ).writeAsStringSync('esto ya no es JSON');

      final leidas = await store.list('/Users/alguien/workspace');

      expect(leidas.single.title, 'mira el historial');
      expect(leidas.single.turns, 2);
    });

    test('se rehace solo si falta', () async {
      await store.save(record());
      File(
        '${carpetaDe('Users-alguien-workspace').path}/_index.json',
      ).deleteSync();

      final leidas = await store.list('/Users/alguien/workspace');

      expect(leidas.single.title, 'mira el historial');
      expect(
        File(
          '${carpetaDe('Users-alguien-workspace').path}/_index.json',
        ).existsSync(),
        isTrue,
      );
    });

    // El motivo de todo esto: archivar pasa **en cada turno**, y no puede
    // costar lo que ocupe el proyecto entero.
    //
    // Se comprueba dejando una conversación ilegible que sí está en el índice:
    // si guardar otra rehiciera el índice leyendo la carpeta, esa se caería de
    // la lista. Como no lo hace, sigue ahí.
    test('guardar una nueva no relee las vecinas', () async {
      await store.save(record());
      File(
        '${carpetaDe('Users-alguien-workspace').path}/c1.json',
      ).writeAsStringSync('ya no se puede leer');

      await store.save(
        record(
          id: 'c2',
          messages: const [ChatMessage(author: ChatAuthor.user, text: 'otra')],
        ),
      );

      final leidas = await store.list('/Users/alguien/workspace');

      expect(leidas.map((r) => r.id), containsAll(['c1', 'c2']));
      expect(
        leidas.firstWhere((r) => r.id == 'c1').title,
        'mira el historial',
        reason: 'la ficha de c1 sigue siendo la que se escribió al guardarla',
      );
    });

    // El índice no es la verdad: la verdad son los archivos. Borrar uno desde
    // el Finder tiene que quitarlo de la lista, no dejar un fantasma que al
    // abrirlo no lleva a ninguna parte.
    test('un archivo borrado a mano desaparece de la lista', () async {
      await store.save(record());
      await store.save(
        record(
          id: 'c2',
          messages: const [ChatMessage(author: ChatAuthor.user, text: 'otra')],
        ),
      );
      File('${carpetaDe('Users-alguien-workspace').path}/c2.json').deleteSync();

      final leidas = await store.list('/Users/alguien/workspace');

      expect(leidas.map((r) => r.id), ['c1']);
    });
  });
}
