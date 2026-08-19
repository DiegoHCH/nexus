import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/repositories/conversation_markdown.dart';
import 'package:nexus/features/history/data/repositories/markdown_archive.dart';
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
        ChatMessage(author: ChatAuthor.user, text: 'Mira el historial de git'),
        ChatMessage(
          author: ChatAuthor.nexus,
          text: 'Hay tres commits sin subir.',
        ),
      ],
);

void main() {
  group('cómo se titula y se nombra', () {
    test('el título es lo primero que pediste', () {
      expect(record().title, 'Mira el historial de git');
    });

    test('el proyecto es el nombre de la carpeta', () {
      expect(record().projectName, 'workspace');
    });

    test('el archivo lleva la fecha delante, para que ordenen solos', () {
      expect(
        ConversationMarkdown.fileName(record()),
        '2026-08-12-mira-el-historial-de-git.md',
      );
    });

    // Los dos puntos rompen el archivo en Windows y confunden a Obsidian en
    // los enlaces; los acentos, según el sistema, se guardan de dos formas.
    test('el nombre sobrevive a acentos y signos raros', () {
      final nombre = ConversationMarkdown.fileName(
        record(
          messages: const [
            ChatMessage(
              author: ChatAuthor.user,
              text: '¿Qué versión? Añade: café/té',
            ),
          ],
        ),
      );

      expect(nombre, '2026-08-12-que-version-anade-cafete.md');
      expect(nombre, isNot(contains(':')));
      expect(nombre, isNot(contains('/')));
    });
  });

  group('lo que se escribe', () {
    test('lleva quién dijo qué, y si se dijo por voz', () {
      final texto = ConversationMarkdown.conversation(
        record(
          messages: const [
            ChatMessage(
              author: ChatAuthor.user,
              text: 'corre los tests',
              spoken: true,
            ),
            ChatMessage(author: ChatAuthor.nexus, text: 'Pasan los 112.'),
          ],
        ),
        wikilinks: false,
      );

      expect(texto, contains('## Tú · por voz'));
      expect(texto, contains('## Nexus'));
      expect(texto, contains('Pasan los 112.'));
      expect(texto, contains('proyecto: "/Users/alguien/workspace"'));
    });

    // Es la diferencia entre los dos destinos de disco, y no es estética: sin
    // el [[enlace]] Obsidian no dibuja el grafo del proyecto.
    test('en Obsidian el proyecto va como enlace; en una carpeta, no', () {
      expect(
        ConversationMarkdown.conversation(record(), wikilinks: true),
        contains('[[workspace]]'),
      );
      expect(
        ConversationMarkdown.conversation(record(), wikilinks: false),
        isNot(contains('[[workspace]]')),
      );
    });

    test(
      'la nota del proyecto enlaza sus conversaciones, la última arriba',
      () {
        final texto = ConversationMarkdown.project(
          'workspace',
          '/Users/alguien/workspace',
          [
            record(when: DateTime(2026, 8, 10)),
            record(
              when: DateTime(2026, 8, 12),
              messages: const [
                ChatMessage(author: ChatAuthor.user, text: 'lo más reciente'),
              ],
            ),
          ],
          wikilinks: true,
        );

        expect(
          texto.indexOf('2026-08-12'),
          lessThan(texto.indexOf('2026-08-10')),
        );
        expect(texto, contains('[[2026-08-12-lo-mas-reciente]]'));
      },
    );
  });

  // La convención del vault: `perfil/proyecto/`, la misma que ya usa La
  // Oficina. Si cada app inventara la suya, el mismo proyecto acabaría en dos
  // sitios y ninguna lista estaría completa.
  group('lo que acaba en el disco', () {
    late Directory destino;

    setUp(() => destino = Directory.systemTemp.createTempSync('nexus_archivo'));
    tearDown(() => destino.deleteSync(recursive: true));

    // Lo que se pidió: cinco conversaciones de un proyecto juntas, y las de
    // otro proyecto en su propio sitio — un grafo por proyecto, no una nube.
    test('cada proyecto en su carpeta, con su nota central', () async {
      final archivo = MarkdownArchive(root: destino.path, wikilinks: true);

      await archivo.save(record());
      await archivo.save(
        record(
          id: 'c2',
          folder: '/Users/alguien/otro-proyecto',
          messages: const [
            ChatMessage(author: ChatAuthor.user, text: 'algo del otro repo'),
          ],
        ),
      );

      final base = destino.path;
      expect(File('$base/workspace/workspace.md').existsSync(), isTrue);
      expect(
        File(
          '$base/workspace/2026-08-12-mira-el-historial-de-git.md',
        ).existsSync(),
        isTrue,
      );
      expect(File('$base/otro-proyecto/otro-proyecto.md').existsSync(), isTrue);
      // Y no se mezclan: la nota de un proyecto no enlaza lo del otro.
      final nota = File('$base/workspace/workspace.md').readAsStringSync();
      expect(nota, isNot(contains('algo-del-otro-repo')));
    });

    test('guardar dos veces la misma conversación no la duplica', () async {
      final archivo = MarkdownArchive(root: destino.path, wikilinks: false);

      await archivo.save(record());
      await archivo.save(record());

      final carpeta = Directory('${destino.path}/workspace');
      final md = carpeta.listSync().whereType<File>().length;
      // La conversación y la nota del proyecto. Ni una copia más.
      expect(md, 2);
    });

    test(
      'la nota del proyecto se rehace leyendo lo que hay en el disco',
      () async {
        final archivo = MarkdownArchive(root: destino.path, wikilinks: true);

        await archivo.save(record());
        // Otra conversación del mismo proyecto, como si fuera otro día y otro
        // arranque de la app: la nota tiene que acabar enlazando las dos.
        await archivo.save(
          record(
            id: 'c3',
            when: DateTime(2026, 8, 13),
            messages: const [
              ChatMessage(author: ChatAuthor.user, text: 'segunda charla'),
            ],
          ),
        );

        final nota = File(
          '${destino.path}/workspace/workspace.md',
        ).readAsStringSync();

        expect(nota, contains('[[2026-08-12-mira-el-historial-de-git]]'));
        expect(nota, contains('[[2026-08-13-segunda-charla]]'));
      },
    );

    test('con cuenta elegida, el perfil es el primer nivel', () async {
      final archivo = MarkdownArchive(root: destino.path, wikilinks: true);

      await archivo.save(
        ConversationRecord(
          id: 'c9',
          folderPath: '/Users/alguien/Workspace',
          startedAt: DateTime(2026, 8, 12),
          profileName: 'work',
          messages: const [
            ChatMessage(author: ChatAuthor.user, text: 'algo del trabajo'),
          ],
        ),
      );

      expect(
        File(
          '${destino.path}/work/Workspace/2026-08-12-algo-del-trabajo.md',
        ).existsSync(),
        isTrue,
      );
    });

    test('una conversación en la que nadie dijo nada no se guarda', () async {
      final archivo = MarkdownArchive(root: destino.path, wikilinks: false);

      await archivo.save(record(messages: const []));

      expect(Directory('${destino.path}/workspace').existsSync(), isFalse);
    });
  });
}
