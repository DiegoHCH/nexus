import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/el_recuerdo_de_los_mcp.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';

/// Lo que el CLI contestó la última vez, guardado.
///
/// 🔴 **Existe porque los conectores de claude.ai no están en ningún archivo
/// del perfil.** Llegan con la sesión, así que la única forma de saber que
/// existen es preguntarle a `claude mcp list` — y eso tarda casi un minuto,
/// porque comprueba la salud de cada uno. Sin recordar la respuesta la pantalla
/// tenía dos salidas malas: enseñar cinco de veinte —que es lo que se reportó—
/// o hacer esperar un minuto cada vez que se abre Ajustes.
void main() {
  late Directory carpeta;
  late ElRecuerdoDeLosMcp recuerdo;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('recuerdo_mcp');
    recuerdo = ElRecuerdoDeLosMcp(carpeta: carpeta);
  });
  tearDown(() => carpeta.deleteSync(recursive: true));

  const perfil = '/Users/alguien/.claude-work';

  test('sin nada guardado no hay nada que recordar', () async {
    expect(await recuerdo.leer(perfil), isNull);
  });

  test(
    'lo guardado vuelve entero: nombre, destino, estado y de dónde sale',
    () async {
      await recuerdo.guardar(perfil, const [
        McpServer(name: 'maestro', spec: 'maestro mcp'),
        McpServer(
          name: 'claude.ai Gmail',
          spec: 'https://gmailmcp.googleapis.com/mcp/v1',
          status: McpStatus.connected,
          fromAccount: true,
        ),
      ]);

      final leido = await recuerdo.leer(perfil);

      expect(leido, isNotNull);
      expect(leido!.servidores, hasLength(2));
      expect(leido.servidores.last.name, 'claude.ai Gmail');
      expect(leido.servidores.last.status, McpStatus.connected);
      expect(
        leido.servidores.last.fromAccount,
        isTrue,
        reason:
            'sin esto, un conector de la cuenta saldría con botón de quitar',
      );
      expect(leido.servidores.first.fromAccount, isFalse);
      // La fecha es la mitad del recuerdo: sin ella no se sabe si vale.
      expect(DateTime.now().difference(leido.cuando).inSeconds, lessThan(5));
    },
  );

  // Dos cuentas no pueden compartir recuerdo: cada perfil tiene sus servidores
  // y mezclarlos enseñaría en `work` los de `personal`.
  test('cada cuenta recuerda lo suyo', () async {
    await recuerdo.guardar(perfil, const [McpServer(name: 'g66', spec: 'uvx')]);
    await recuerdo.guardar('/Users/alguien/.claude', const [
      McpServer(name: 'otro', spec: 'npx'),
    ]);

    expect((await recuerdo.leer(perfil))!.servidores.single.name, 'g66');
    expect(
      (await recuerdo.leer('/Users/alguien/.claude'))!.servidores.single.name,
      'otro',
    );
  });

  group('un recuerdo que no se puede leer es lo mismo que no tenerlo', () {
    // Romper Ajustes por una caché sería cambiar un problema pequeño por uno
    // grande: aquí siempre se contesta `null` y se vuelve a preguntar.
    test('basura en el archivo', () async {
      await recuerdo.guardar(perfil, const [
        McpServer(name: 'maestro', spec: 'maestro mcp'),
      ]);
      final archivo = carpeta
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      archivo.writeAsStringSync('{esto no es json');

      expect(await recuerdo.leer(perfil), isNull);
    });

    test('otra versión del formato se tira, no se interpreta', () async {
      await recuerdo.guardar(perfil, const [
        McpServer(name: 'maestro', spec: 'maestro mcp'),
      ]);
      final archivo = carpeta
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      final leido = jsonDecode(archivo.readAsStringSync()) as Map;
      archivo.writeAsStringSync(
        jsonEncode({...leido, 'version': ElRecuerdoDeLosMcp.version + 1}),
      );

      expect(await recuerdo.leer(perfil), isNull);
    });

    test('y sin fecha tampoco vale: no se sabría si caducó', () async {
      await recuerdo.guardar(perfil, const [
        McpServer(name: 'maestro', spec: 'maestro mcp'),
      ]);
      final archivo = carpeta
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      final leido = jsonDecode(archivo.readAsStringSync()) as Map;
      archivo.writeAsStringSync(
        jsonEncode({...leido, 'cuando': 'ayer por la tarde'}),
      );

      expect(await recuerdo.leer(perfil), isNull);
    });
  });
}
