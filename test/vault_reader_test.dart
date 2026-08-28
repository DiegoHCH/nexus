import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/vault_reader.dart';
import 'package:nexus/features/history/data/repositories/conversation_markdown.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';

/// Una nota tal como las escribe La Oficina, copiada de un vault de verdad.
/// Es la forma que hay que entender para no esconder conversaciones que ya
/// existen sobre los mismos repos.
const notaDeLaOficina = '''
---
titulo: "ay alguna forma de hacer esto en mac?"
perfil: "work"
proyecto: "/Users/diego.hoyos/Workspace"
modelo: "claude-opus-5[1m]"
mensajes: 2
actualizada: "2026-08-06T16:43:10.246Z"
id: "67080156-fea1-4c2c-b917-49e3c7df9111"
tags: [la-oficina, work]
---

<!-- generado por La Oficina -->

> 🧠 Memoria del proyecto: [[_memoria]]

# ay alguna forma de hacer esto en mac?

> Perfil: work · Proyecto: `/Users/diego.hoyos/Workspace`

## 👤 Tú → dev

ay alguna forma de hacer esto en mac?

## 🤖 dev

Sí. Eso es Snap Layouts de Windows 11, y macOS tiene equivalente.
''';

void main() {
  group('lo que ya hay en el vault', () {
    test('una nota de La Oficina se entiende entera', () {
      final record = VaultReader.parse(notaDeLaOficina, fallbackId: 'x')!;

      expect(record.title, 'ay alguna forma de hacer esto en mac?');
      expect(record.folderPath, '/Users/diego.hoyos/Workspace');
      expect(record.profileName, 'work');
      expect(record.id, '67080156-fea1-4c2c-b917-49e3c7df9111');
      expect(record.messages, hasLength(2));
      // Quién habló: el encabezado te nombra a ti o no. El agente puede
      // llamarse «dev», «QA» o cualquier cosa, y sigue siendo la máquina.
      expect(record.messages.first.author, ChatAuthor.user);
      expect(record.messages.last.author, ChatAuthor.nexus);
      expect(record.messages.last.text, contains('Snap Layouts'));
    });

    test('y una de Nexus también, que para eso comparten cabecera', () {
      final escrita = ConversationMarkdown.conversation(
        ConversationRecord(
          id: 'c1',
          folderPath: '/Users/alguien/workspace',
          startedAt: DateTime(2026, 8, 12, 19, 30),
          profileName: 'private',
          messages: const [
            ChatMessage(
              author: ChatAuthor.user,
              text: 'mira el historial',
              spoken: true,
            ),
            ChatMessage(author: ChatAuthor.nexus, text: 'tres commits'),
          ],
        ),
        wikilinks: true,
      );

      final leida = VaultReader.parse(escrita, fallbackId: 'x')!;

      expect(leida.id, 'c1');
      expect(leida.folderPath, '/Users/alguien/workspace');
      expect(leida.profileName, 'private');
      expect(leida.messages.first.author, ChatAuthor.user);
      // Se conserva que se dijo por voz: es lo que explica una transcripción
      // rara meses después.
      expect(leida.messages.first.spoken, isTrue);
      expect(leida.messages.last.text, 'tres commits');
    });

    test('una nota cualquiera del vault no es una conversación', () {
      expect(VaultReader.parse('# apuntes sueltos', fallbackId: 'x'), isNull);
      expect(
        VaultReader.parse('---\ntags: [notas]\n---\n\nhola', fallbackId: 'x'),
        isNull,
      );
    });
  });

  group('recorriendo la carpeta', () {
    late Directory vault;

    setUp(() => vault = Directory.systemTemp.createTempSync('nexus_vault'));
    tearDown(() => vault.deleteSync(recursive: true));

    void escribe(String ruta, String contenido) {
      final file = File('${vault.path}/$ruta');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contenido);
    }

    test('solo salen las del proyecto que se pide', () async {
      escribe('work/Workspace/una.md', notaDeLaOficina);
      escribe(
        'private/nexus/otra.md',
        notaDeLaOficina.replaceAll(
          '/Users/diego.hoyos/Workspace',
          '/Users/diego.hoyos/personal/nexus',
        ),
      );

      final leidas = await VaultReader().list(
        vault.path,
        folderPath: '/Users/diego.hoyos/Workspace',
      );

      expect(leidas, hasLength(1));
      expect(leidas.single.profileName, 'work');
      // La cabecera de La Oficina ya trae cuántos turnos, así que la lista los
      // sabe sin abrir la nota.
      expect(leidas.single.turns, 2);
    });

    // `_memoria.md` es la nota de memoria de La Oficina, y la del proyecto
    // tampoco es una conversación: enseñarlas en el historial sería ruido.
    test('las notas de servicio no se cuelan', () async {
      escribe('work/Workspace/_memoria.md', notaDeLaOficina);

      final leidas = await VaultReader().list(
        vault.path,
        folderPath: '/Users/diego.hoyos/Workspace',
      );

      expect(leidas, isEmpty);
    });

    // El motivo de que el lector guarde estado. Refrescar el historial pasa en
    // cada turno, y un vault de verdad son miles de notas: releerlas todas
    // cada vez era el trabajo que más crecía con el uso.
    //
    // Se comprueba cambiando la nota **sin que el disco lo note**: mismo
    // tamaño y misma fecha de modificación. Si el lector la releyera, vería el
    // título nuevo; como se fía de lo que ya sabe, sigue diciendo el viejo.
    test('una nota que no cambió no se vuelve a leer', () async {
      escribe('work/Workspace/una.md', notaDeLaOficina);
      final lector = VaultReader();
      await lector.list(vault.path);

      final nota = File('${vault.path}/work/Workspace/una.md');
      final antes = nota.statSync();
      nota.writeAsStringSync(
        notaDeLaOficina.replaceAll(
          'ay alguna forma de hacer esto en mac?',
          'AY ALGUNA FORMA DE HACER ESTO EN MAC?',
        ),
      );
      nota.setLastModifiedSync(antes.modified);

      final leidas = await lector.list(vault.path);

      expect(leidas.single.title, 'ay alguna forma de hacer esto en mac?');
    });

    test('y una que sí cambió, sí', () async {
      escribe('work/Workspace/una.md', notaDeLaOficina);
      final lector = VaultReader();
      await lector.list(vault.path);

      escribe(
        'work/Workspace/una.md',
        notaDeLaOficina.replaceAll(
          'titulo: "ay alguna forma de hacer esto en mac?"',
          'titulo: "otra cosa"',
        ),
      );

      final leidas = await lector.list(vault.path);

      expect(leidas.single.title, 'otra cosa');
    });

    // Lo que ya no está en el disco tampoco puede seguir apareciendo en la
    // lista: la memoria del lector no puede resucitar una nota borrada.
    test('una nota borrada desaparece de la lista', () async {
      escribe('work/Workspace/una.md', notaDeLaOficina);
      final lector = VaultReader();
      expect(await lector.list(vault.path), hasLength(1));

      File('${vault.path}/work/Workspace/una.md').deleteSync();

      expect(await lector.list(vault.path), isEmpty);
    });

    test('una carpeta que ya no existe no rompe el historial', () async {
      final leidas = await VaultReader().list(
        '${vault.path}/lo-que-sea',
        folderPath: '/x',
      );

      expect(leidas, isEmpty);
    });
  });
}
