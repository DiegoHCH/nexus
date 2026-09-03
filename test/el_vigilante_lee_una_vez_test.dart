import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/data/datasources/agenda_data_source.dart';
import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/agenda/presentation/providers/el_vigilante_de_la_agenda.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El vigilante, probado de verdad y no por sus trozos.
///
/// 🔴 **Antes esto no se podía escribir.** El notificador construía a mano
/// `const AgendaDataSource()` y `const GeminiTtsDataSource()`, así que cualquier
/// prueba llamaba al calendario de verdad —un `claude -p` de treinta segundos—
/// y al servicio de voz. Con las fuentes en proveedores hay por dónde entrar, y
/// lo que se comprueba aquí es lo que costaba cupo de la suscripción cada vez
/// que se equivocaba.
const carpeta = '/Users/alguien/repo';

class _Workspace extends WorkspaceController {
  _Workspace(this.emparejada);

  final bool emparejada;

  @override
  Workspace build() => Workspace(
    folders: emparejada
        ? [PairedFolder(path: carpeta, modality: FolderModality.voice)]
        : const [],
    activePath: emparejada ? carpeta : null,
  );
}

/// Un calendario que cuenta cuántas veces le preguntan.
class _Calendario extends AgendaDataSource {
  _Calendario([this.devuelve = const []]);

  final List<Reunion> devuelve;
  var veces = 0;

  @override
  Future<List<Reunion>> delDia(
    DateTime dia, {
    required String carpeta,
    String? configDir,
  }) async {
    veces++;
    return devuelve;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'avisos_agenda_encendidos': true,
      'avisos_agenda_minutos': 5,
      'avisos_agenda_carpeta': carpeta,
    });
  });

  /// Jueves 3 de septiembre de 2026, a las nueve. Clavado a propósito: media
  /// decisión del vigilante cuelga de la jornada, así que con el reloj de la
  /// máquina esta suite se pondría roja sola cada sábado — y el CI corre a
  /// cualquier hora.
  final jueves = DateTime(2026, 9, 3, 9);

  ProviderContainer montar(
    _Calendario calendario, {
    bool emparejada = true,
    DateTime? cuando,
  }) {
    final container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(() => cuando ?? jueves),
        agendaDataSourceProvider.overrideWithValue(calendario),
        workspaceControllerProvider.overrideWith(() => _Workspace(emparejada)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Deja que el `_cargar()` del arranque termine antes de mirar nada.
  Future<void> asentar(ProviderContainer container) async {
    container.read(elVigilanteDeLaAgendaProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'con la carpeta todavía sin cargar no se le pregunta al calendario',
    () async {
      final calendario = _Calendario();
      final container = montar(calendario, emparejada: false);

      await asentar(container);
      await container.read(elVigilanteDeLaAgendaProvider.notifier).loDeHoy();

      expect(
        calendario.veces,
        0,
        reason:
            'el vigilante le gana la carrera al workspace al arrancar, y leer '
            'ahí sacaría la agenda de la cuenta por defecto en vez de la de la '
            'carpeta — que es otra cuenta, con otro calendario o con ninguno',
      );
    },
  );

  // 🔴 El fallo medido que motivó la lectura única: el reloj tira cada treinta
  // segundos, la lectura tarda entre veintiséis y cuarenta, y el tic siguiente
  // entraba mientras el primero todavía esperaba. Dos `claude -p` por arranque,
  // o sea el doble de cupo para leer la misma agenda.
  test('varias preguntas seguidas no son varias consultas', () async {
    final calendario = _Calendario();
    final container = montar(calendario);
    final vigilante = container.read(elVigilanteDeLaAgendaProvider.notifier);

    await asentar(container);
    await Future.wait([
      vigilante.loDeHoy(),
      vigilante.loDeHoy(),
      vigilante.loDeHoy(),
    ]);

    expect(
      calendario.veces,
      1,
      reason: 'las tres esperan a la misma lectura, no lanzan tres',
    );
  });

  test('releer a mano sí vuelve a preguntar', () async {
    final calendario = _Calendario();
    final container = montar(calendario);
    final vigilante = container.read(elVigilanteDeLaAgendaProvider.notifier);

    await asentar(container);
    await vigilante.loDeHoy();
    final tras = calendario.veces;
    await vigilante.releer();

    expect(
      calendario.veces,
      greaterThan(tras),
      reason:
          'una reunión puesta a media mañana no está en lo que se leyó al '
          'arrancar: para eso existe el botón',
    );
  });

  test('lo que devuelve el calendario es lo que se contesta', () async {
    final calendario = _Calendario([
      Reunion(
        id: 'e1',
        titulo: 'Refinamiento',
        comienza: DateTime(2026, 9, 3, 11, 30),
        invitados: 3,
      ),
      // Un bloque propio: se lee del calendario y no se cuenta como agenda.
      Reunion(id: 'e2', titulo: 'comer', comienza: DateTime(2026, 9, 3, 13)),
    ]);
    final container = montar(calendario);

    await asentar(container);
    final dicho = await container
        .read(elVigilanteDeLaAgendaProvider.notifier)
        .loDeHoy();

    expect(dicho, contains('11:30 · Refinamiento'));
    expect(
      dicho,
      isNot(contains('comer')),
      reason: 'sin invitados no es una reunión, es un bloque tuyo',
    );
  });

  test(
    'fuera de jornada no se consulta, y se dice que ya no se sabe',
    () async {
      final calendario = _Calendario();
      // Sábado 5 de septiembre de 2026, a las diez.
      final container = montar(calendario, cuando: DateTime(2026, 9, 5, 10));

      await asentar(container);
      final dicho = await container
          .read(elVigilanteDeLaAgendaProvider.notifier)
          .loDeHoy();

      expect(calendario.veces, 0);
      expect(
        dicho,
        isNotNull,
        reason:
            'no es «no tienes reuniones»: eso sería mentir sobre un día que sí '
            'las tuvo. Es que la agenda ya está borrada',
      );
    },
  );

  test('con los avisos apagados no se lee nada y no se contesta', () async {
    SharedPreferences.setMockInitialValues({'avisos_agenda_encendidos': false});
    final calendario = _Calendario();
    final container = montar(calendario);

    await asentar(container);
    final dicho = await container
        .read(elVigilanteDeLaAgendaProvider.notifier)
        .loDeHoy();

    expect(calendario.veces, 0);
    expect(
      dicho,
      isNull,
      reason:
          'sin agenda que mirar, quien pregunta sigue por el camino largo en '
          'vez de recibir un «no tengo» que sería mentira',
    );
  });
}
