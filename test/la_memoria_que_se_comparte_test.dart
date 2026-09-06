import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/la_sesion_que_se_comparte.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/la_sesion_sin_dueno.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dos chats sobre la misma carpeta **no son dos hilos**, y lo parecían.
///
/// 🔴 La sesión de Claude va por carpeta y cuenta: cualquier conversación sobre
/// esa carpeta reanuda la misma, así que comparten contexto, lo pedido y el
/// permiso concedido. Lo que no comparten es lo que se ve. Y cerrar todos los
/// chats **no la suelta** —eso protege el archivo, con razón— así que se podía
/// cerrar todo, abrir una nueva y que el modelo siguiera acordándose sin que
/// nada lo dijera.
const _carpeta = '/Users/alguien/Workspace/front-mobile-b2c';

class _Memoria implements ConversationMemory {
  _Memoria({this.sessionId});

  String? sessionId;
  final olvidadas = <String>[];

  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      FolderMemory(sessionId: sessionId);

  @override
  Future<void> forget(String folderPath) async {
    olvidadas.add(folderPath);
    sessionId = null;
  }

  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}

  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}

  @override
  Future<void> rememberPermissionMode(
    String folderPath,
    String mode, {
    String? claudeProfile,
  }) async {}
}

/// El archivo: lo que queda guardado de cada carpeta.
class _Archivo implements LocalConversationStore {
  _Archivo(this.fichas, {this.revienta = false});

  List<ConversationSummary> fichas;
  final bool revienta;

  @override
  Future<List<ConversationSummary>> list(String folderPath) async {
    if (revienta) throw StateError('el disco no contesta');
    return fichas;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Disco implements ConversationsDataSource {
  const _Disco();

  @override
  Future<Map<String, dynamic>> read() async => const {};

  @override
  Future<void> write(Map<String, dynamic> json) async {}
}

ConversationSummary _ficha(String id) => ConversationSummary(
  id: id,
  folderPath: _carpeta,
  startedAt: DateTime(2026, 9, 6),
  title: 'algo',
  turns: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('la regla', () {
    test('se cuentan todas las que comparten, también la que pregunta', () {
      expect(
        LaSesionQueSeComparte.cuantasComparten([
          _carpeta,
          _carpeta,
          '/otra',
        ], _carpeta),
        2,
      );
    });

    test('sin sesión guardada no se continúa nada', () {
      expect(LaSesionQueSeComparte.continuaSinVerse(null), isFalse);
      expect(LaSesionQueSeComparte.continuaSinVerse(''), isFalse);
      expect(LaSesionQueSeComparte.continuaSinVerse('e5e1d988'), isTrue);
    });

    test('la sesión se suelta solo cuando no queda ningún registro', () {
      bool sinDueno({
        bool abiertas = false,
        bool archivadas = false,
        bool leido = true,
      }) => LaSesionQueSeComparte.seQuedoSinDueno(
        quedanAbiertas: abiertas,
        quedanArchivadas: archivadas,
        seLeyoElArchivo: leido,
      );

      expect(sinDueno(), isTrue);
      expect(sinDueno(abiertas: true), isFalse);
      // Mientras el registro exista, la sesión sigue: retomar una conversación
      // archivada sin memoria es justo lo contrario de lo que se fue a buscar.
      expect(sinDueno(archivadas: true), isFalse);
      // Un fallo de disco no es una lista vacía.
      expect(sinDueno(leido: false), isFalse);
    });
  });

  group('al abrir una conversación nueva', () {
    late _Memoria memoria;
    late ProviderContainer contenedor;

    ProviderContainer montar({String? sessionId}) {
      memoria = _Memoria(sessionId: sessionId);
      contenedor = ProviderContainer(
        overrides: [
          conversationMemoryProvider.overrideWithValue(memoria),
          conversationsDataSourceProvider.overrideWithValue(const _Disco()),
          localConversationStoreProvider.overrideWithValue(_Archivo([])),
          conversationArchiveProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(contenedor.dispose);
      return contenedor;
    }

    Future<String> abrir() async {
      final id = await contenedor
          .read(conversationsProvider.notifier)
          .open(_carpeta);
      // El aviso lo pone el controlador al acabar de buscar lo dicho, que es
      // asíncrono: se le deja llegar al disco y volver.
      contenedor.read(assistantControllerProvider(id!));
      await pumpEventQueue();
      return id;
    }

    test(
      'si la carpeta ya tenía sesión, se dice y se ofrece la salida',
      () async {
        montar(sessionId: 'e5e1d988-263b-48c7-8ef0-3abd6ea2563a');
        final id = await abrir();

        final hud = contenedor.read(assistantControllerProvider(id));
        expect(hud.notice, contenedor.read(stringsProvider).continuoDondeQuedo);
        expect(
          hud.puedeEmpezarDeCero,
          isTrue,
          reason: 'un aviso sin salida solo sirve para dar mala conciencia',
        );
      },
    );

    test('y si no la tenía, no se dice nada', () async {
      montar();
      final id = await abrir();

      expect(contenedor.read(assistantControllerProvider(id)).notice, isNull);
    });

    test('empezar de cero olvida la sesión y quita el aviso', () async {
      montar(sessionId: 'e5e1d988');
      final id = await abrir();

      await contenedor
          .read(assistantControllerProvider(id).notifier)
          .forgetConversation();

      expect(memoria.olvidadas, [_carpeta]);
      final hud = contenedor.read(assistantControllerProvider(id));
      expect(hud.notice, isNull);
      expect(hud.puedeEmpezarDeCero, isFalse);
    });
  });

  group('cuando la sesión se queda sin dueño', () {
    late _Memoria memoria;
    late _Archivo archivo;
    late ProviderContainer contenedor;

    Future<void> montar({
      List<ConversationSummary> guardadas = const [],
      bool elDiscoRevienta = false,
    }) async {
      memoria = _Memoria(sessionId: 'e5e1d988');
      archivo = _Archivo([...guardadas], revienta: elDiscoRevienta);
      contenedor = ProviderContainer(
        overrides: [
          conversationMemoryProvider.overrideWithValue(memoria),
          conversationsDataSourceProvider.overrideWithValue(const _Disco()),
          localConversationStoreProvider.overrideWithValue(archivo),
          conversationArchiveProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(contenedor.dispose);
    }

    test('cerrar la última sin nada guardado la suelta', () async {
      await montar();
      final id = await contenedor
          .read(conversationsProvider.notifier)
          .open(_carpeta);
      await contenedor.read(conversationsProvider.notifier).close(id!);

      expect(memoria.olvidadas, [_carpeta]);
    });

    // 🔴 **Cerrar no olvida mientras quede algo que retomar.** Si cerrar tirara
    // la sesión, retomar una conversación archivada volvería sin memoria.
    test('pero no si queda algo en el archivo', () async {
      await montar(guardadas: [_ficha('r1')]);
      final id = await contenedor
          .read(conversationsProvider.notifier)
          .open(_carpeta);
      await contenedor.read(conversationsProvider.notifier).close(id!);

      expect(memoria.olvidadas, isEmpty);
    });

    test('ni si queda otra conversación abierta sobre la carpeta', () async {
      await montar();
      final mando = contenedor.read(conversationsProvider.notifier);
      final una = await mando.open(_carpeta);
      await mando.open(_carpeta);
      await mando.close(una!);

      expect(memoria.olvidadas, isEmpty);
    });

    // Tirar una sesión por no haber podido mirar es el error que no se puede
    // deshacer.
    test('y si el archivo no se pudo leer, se deja como estaba', () async {
      await montar(elDiscoRevienta: true);
      final id = await contenedor
          .read(conversationsProvider.notifier)
          .open(_carpeta);
      await contenedor.read(conversationsProvider.notifier).close(id!);

      expect(memoria.olvidadas, isEmpty);
    });

    test('borrar la última del archivo también la suelta', () async {
      await montar(guardadas: [_ficha('r1')]);
      archivo.fichas = [];

      await contenedor.read(laSesionSinDuenoProvider)(_carpeta);

      expect(memoria.olvidadas, [_carpeta]);
    });
  });
}
