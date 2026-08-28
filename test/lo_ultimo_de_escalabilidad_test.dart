import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/remote/domain/event_log.dart';

/// ESC-04 y ESC-05, lo último que quedaba de escalabilidad.

void main() {
  // ESC-05. El registro es **uno solo** para todas las conversaciones vivas, así
  // que los cincuenta segundos que cubre se reparten entre ellas.
  group('el búfer de resync', () {
    /// Cincuenta segundos de escritura continua en todas las conversaciones a la
    /// vez: `porConversacion` deltas por cada una de las que caben.
    void cincuentaSegundosEnTodas(EventLog log) {
      for (var i = 0; i < EventLog.porConversacion * Conversations.max; i++) {
        log.emitir('delta');
      }
    }

    test('dimensionado para el muelle lleno, un túnel todavía se resync', () {
      final log = EventLog(
        capacidad: EventLog.porConversacion * Conversations.max,
      );
      cincuentaSegundosEnTodas(log);

      // `null` significa «pídeme el snapshot», que es el camino que la decisión
      // 4.4 declaró excepcional y que en 4G es justo lo que se quiere evitar.
      expect(
        log.desde(1),
        isNotNull,
        reason: 'quien vio el primero sigue pudiendo pedir desde ahí',
      );
    });

    test('y con el tamaño de una sola, no cabía', () {
      final log = EventLog(capacidad: EventLog.porConversacion);
      cincuentaSegundosEnTodas(log);

      expect(
        log.desde(1),
        isNull,
        reason:
            'este es el hallazgo: con varias vivas, el búfer se queda corto',
      );
    });

    // El número de conversaciones ya se movió una vez —de tres a seis— y este
    // búfer no se enteró. Se ata a la constante para que no vuelva a pasar.
    test('el canal lo multiplica por cuántas caben, y no pone un número', () {
      final proveedores = File(
        'lib/features/remote/presentation/providers/channel_providers.dart',
      ).readAsStringSync();

      expect(
        proveedores,
        contains('EventLog.porConversacion * Conversations.max'),
        reason:
            'un numero escrito a mano se queda viejo el dia que cambie el muelle',
      );
    });
  });

  // ESC-04. Las dos que el informe señalaba por nombre: las demás son
  // comprobaciones de si un archivo existe, y esas no valen una rama.
  group('lo que ya no bloquea el hilo que dibuja', () {
    test('medir una pasada no recorre el disco de forma síncrona', () {
      final fuente = File(
        'lib/features/e2e/data/datasources/e2e_data_source.dart',
      ).readAsStringSync();
      final desde = fuente.indexOf('Future<int> bytesDe(');
      expect(desde, isNot(-1), reason: 'bytesDe ya no es síncrono');
      final cuerpo = fuente.substring(desde, fuente.indexOf('\n  }', desde));

      expect(cuerpo, isNot(contains('listSync')));
      expect(cuerpo, isNot(contains('lengthSync')));
    });

    test('y el .claude.json de cada encargo tampoco', () {
      // Sin los comentarios: ahí se nombra el `readAsStringSync` de antes para
      // explicar por qué esto es asíncrono, y esa mención es justo lo que hay
      // que conservar.
      final permisos =
          File('lib/features/assistant/domain/usecases/mcp_permissions.dart')
              .readAsLinesSync()
              .where(
                (l) =>
                    !l.trimLeft().startsWith('//') &&
                    !l.trimLeft().startsWith('///'),
              )
              .join('\n');

      expect(permisos, isNot(contains('readAsStringSync')));
      // Pero se sigue leyendo cada vez: un permiso cacheado no se cierra hasta
      // reiniciar, que es la misma regla que la frase de escritura.
      expect(permisos, contains('await file.readAsString()'));
    });

    test(
      'el puente lo resuelve antes de arrancar, no dentro de la llamada',
      () {
        final puente = File(
          'lib/features/assistant/data/repositories/claude_bridge_impl.dart',
        ).readAsStringSync();

        final resuelve = puente.indexOf('await McpPermissions.permitidosPara(');
        final arranca = puente.indexOf(
          'await for (final json in _dataSource.run(',
        );
        expect(resuelve, isNot(-1));
        expect(
          resuelve,
          lessThan(arranca),
          reason: 'dentro de la llamada seguiría en el camino del lanzamiento',
        );
      },
    );
  });
}
