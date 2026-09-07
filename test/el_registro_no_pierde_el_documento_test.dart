import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hasta_que.dart';

/// Lo que el registro de una conversación perdía al cerrar la app.
///
/// 🔴 **Salió usándolo.** Un encargo generó un diagrama, el chat enseñó su
/// enlace y un aviso de compresión; se cerró la app y al volver no estaba
/// ninguna de las dos cosas. El archivo seguía en el disco: lo que se perdió
/// fue el enlace, que es la peor forma de perderlo, porque parece que el
/// documento tampoco está.
///
/// Comprobado en el registro real de esa conversación —
/// `Application Support/…/conversaciones/…json`— el mensaje traía `pasos: 84`
/// y `documento: null`. Esa diferencia es el diagnóstico entero: los pasos se
/// sellan **síncronos** y el documento y los cambios no, así que `_archive()`
/// serializaba los mensajes mientras el documento aún se estaba buscando y
/// ganaba la carrera el archivado. El aviso de compresión se perdía por lo
/// otro: nacía después de archivar.
const _id = 'c1';
const _carpeta = '/Users/alguien/General';

/// La ventana por defecto son 200k, así que 180k es el 90 % y dispara la
/// compresión —el umbral está en 85—, y 60k es el 30 % de después.
const _contextoLleno = 180000;
const _contextoComprimido = 60000;

/// Un Claude de guion, que además **escribe un documento mientras trabaja**.
///
/// Lo de escribirlo desde aquí no es adorno: el documento se detecta comparando
/// la carpeta antes y después del encargo, así que para medir la carrera tiene
/// que aparecer justo en medio, como aparece de verdad.
class _Claude implements AskClaude {
  _Claude({required this.contextos, this.documento});

  /// Un contexto por llamada, en orden. `null` = el turno no reporta medida,
  /// que es lo que hace `/compact` a menudo y el motivo del mensaje sin número.
  final List<int?> contextos;

  /// Dónde dejar el documento durante el primer encargo, si hay que dejarlo.
  final File? documento;

  final pedidos = <String>[];

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    // Aquí no se pregunta nada: estas pruebas van del registro.
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
    final vuelta = pedidos.length;
    pedidos.add(instruction);

    if (vuelta == 0 && documento != null) {
      // **Con espera de reloj y no de microtask.** La foto de «antes» la toma
      // `_markRepo()`, que va suelto al arrancar el encargo y hace dos
      // llamadas a git por medio. Escribiendo el documento antes de esa foto,
      // el archivo saldría en las dos listas y no contaría como nuevo — la
      // prueba fallaría por una carrera suya, no por la que mide.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      documento!.writeAsStringSync('<html>un diagrama</html>');
    }

    // Un `await` de por medio: sin él todo pasaría en el mismo microtask y la
    // carrera que esto mide no existiría ni con el código viejo.
    await Future<void>.delayed(Duration.zero);
    yield const ClaudeTextDelta('ya está');
    yield ClaudeTurnCompleted(
      result: 'ya está',
      contextTokens: vuelta < contextos.length ? contextos[vuelta] : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Apunta lo que se le manda guardar, en orden.
class _AlmacenQueApunta implements LocalConversationStore {
  final guardados = <ConversationRecord>[];

  @override
  Future<void> save(ConversationRecord record) async => guardados.add(record);

  @override
  Future<List<ConversationSummary>> list(String folderPath) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// El destino externo, solo para contar cuántas veces se sale de la máquina.
class _DestinoQueCuenta implements ConversationArchive {
  var veces = 0;

  @override
  Future<void> save(ConversationRecord record) async => veces++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SinLlaveDeImagenes implements GeminiImageKeyStore {
  const _SinLlaveDeImagenes();
  @override
  Future<String?> read(String? perfil) async => null;
  @override
  Future<void> save(String? perfil, String key) async {}
  @override
  Future<void> clear(String? perfil) async {}
}

class _SinMemoria implements ConversationMemory {
  const _SinMemoria();
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory();
  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> rememberPermissionMode(
    String f,
    String mode, {
    String? claudeProfile,
  }) async {}

  @override
  Future<void> forget(String folderPath) async {}
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cajon;

  setUp(() {
    cajon = Directory.systemTemp.createTempSync('nexus-documentos');
    SharedPreferences.setMockInitialValues({'artifacts.folder': cajon.path});
  });
  tearDown(() => cajon.deleteSync(recursive: true));

  /// Espera a que **pase lo que se está esperando**, no un rato.
  ///
  /// 🔴 Esto eran `12 × 40 ms` a ojo, y con la máquina ocupada no llegaba: la
  /// cadena de `await` detrás de un encargo incluye un `git` de verdad, así que
  /// medio segundo alcanza en una máquina libre y no en una cargada. La prueba
  /// se ponía roja **sin que nadie hubiera tocado nada**, y esta es de las de
  /// regresión: una que falla a veces se acaba tratando como ruido, y el día que
  /// el fallo vuelva de verdad nadie la va a creer.
  ///
  /// El plazo es largo a propósito. No es lo que tarda: es lo que se tolera
  /// antes de decir que no va a pasar. En una máquina libre esto sale en
  /// milisegundos.
  /// Lo que hay que mirar cuando la del documento se cae: si se guardó algo y
  /// si el último mensaje del último registro traía el documento.
  String loGuardado(_AlmacenQueApunta almacen) {
    if (almacen.guardados.isEmpty) return 'guardados=0 (no se archivó nada)';
    final ultimo = almacen.guardados.last;
    final mensaje = ultimo.messages.isEmpty ? null : ultimo.messages.last;
    return 'guardados=${almacen.guardados.length} · '
        'mensajes=${ultimo.messages.length} · '
        'documento=${mensaje?.documento ?? "null"}';
  }

  /// Y para lo que hay que comprobar que **no** vuelve a pasar: se espera a que
  /// ocurra la primera vez y después se deja un rato de reposo. Aquí el tiempo
  /// fijo sí vale, porque una máquina lenta hace que pasen **menos** cosas, no
  /// más: no puede convertir un verde en un falso verde.
  Future<void> yQueNoHayaMas() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  ({
    ProviderContainer container,
    _AlmacenQueApunta almacen,
    _DestinoQueCuenta destino,
    _Claude claude,
  })
  montar({required List<int?> contextos, File? documento}) {
    final almacen = _AlmacenQueApunta();
    final destino = _DestinoQueCuenta();
    final claude = _Claude(contextos: contextos, documento: documento);
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(almacen),
        conversationArchiveProvider.overrideWith((ref) async => destino),
        askClaudeProvider(_id).overrideWithValue(claude),
        geminiImageKeyStoreProvider.overrideWithValue(
          const _SinLlaveDeImagenes(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (
      container: container,
      almacen: almacen,
      destino: destino,
      claude: claude,
    );
  }

  test('el documento que dejó el encargo entra en el registro', () async {
    final todo = montar(
      contextos: const [1000],
      documento: File('${cajon.path}/diagrama.html'),
    );
    final controlador = todo.container.read(
      assistantControllerProvider(_id).notifier,
    );
    // La carpeta se lee del disco al construir el proveedor, y hasta que
    // termine vale `null` — con `null` no se mira ningún cajón y el documento
    // no existiría para esta prueba por un motivo que no es el que mide.
    await todo.container.read(artifactsFolderProvider.notifier).cargada;

    await controlador.submit('dibuja la arquitectura');
    await hastaQue(
      () =>
          todo.almacen.guardados.isNotEmpty &&
          todo.almacen.guardados.last.messages.last.documento != null,
      esperando: 'que el registro guardado traiga el documento',
      loQueSeVe: () => loGuardado(todo.almacen),
    );

    expect(
      todo.almacen.guardados,
      isNotEmpty,
      reason: 'algo se tiene que guardar',
    );
    final ultimo = todo.almacen.guardados.last.messages.last;
    expect(
      ultimo.documento,
      '${cajon.path}/diagrama.html',
      reason:
          'antes se archivaba mientras el documento aún se buscaba, y el '
          'registro quedaba con documento: null — el enlace no volvía al '
          'reabrir la app aunque el archivo siguiera en el disco',
    );
  });

  test('el aviso de la compresión también, aunque nazca después', () async {
    // Primer turno lleno → comprime; el `/compact` no reporta medida.
    final todo = montar(contextos: const [_contextoLleno, null]);
    final controlador = todo.container.read(
      assistantControllerProvider(_id).notifier,
    );

    await controlador.submit('resume lo que hicimos');
    final strings = todo.container.read(stringsProvider);
    // 🔴 **Se espera al segundo guardado, no al primero.** Es lo que dice el
    // motivo de abajo: el aviso nace *después* de archivar, así que el primer
    // registro no lo lleva. Esperar a `guardados.isNotEmpty` resolvía con ese
    // primero y comparaba contra un registro que todavía no podía traerlo — el
    // mismo error de esperar la señal equivocada que esta prueba vino a dejar
    // de cometer.
    await hastaQue(
      () =>
          todo.claude.pedidos.contains('/compact') &&
          todo.almacen.guardados.any(
            (r) => r.messages.any((m) => m.text == strings.compactedUnknown),
          ),
      esperando: 'que el aviso de la compresión llegue al registro guardado',
      loQueSeVe: () =>
          '${loGuardado(todo.almacen)} · pedidos=${todo.claude.pedidos}',
    );

    expect(todo.claude.pedidos, contains('/compact'));
    final textos = todo.almacen.guardados.last.messages.map((m) => m.text);
    expect(
      textos,
      contains(strings.compactedUnknown),
      reason:
          'el aviso nace después de archivar, así que sin la segunda pasada '
          'del historial local no llegaba nunca al registro',
    );
  });

  test('y salir de la máquina sigue siendo una vez por turno', () async {
    final todo = montar(contextos: const [_contextoLleno, null]);
    final controlador = todo.container.read(
      assistantControllerProvider(_id).notifier,
    );

    await controlador.submit('resume lo que hicimos');
    await hastaQue(
      () => todo.destino.veces >= 1,
      esperando: 'que se escriba en el destino externo',
      loQueSeVe: () =>
          'veces=${todo.destino.veces} · ${loGuardado(todo.almacen)}',
    );
    await yQueNoHayaMas();

    expect(
      todo.destino.veces,
      1,
      reason:
          'el historial local es idempotente y se reescribe barato; el destino '
          'externo cuesta red, y dos escrituras por turno serían el precio de '
          'arreglar el aviso',
    );
  });

  test(
    'el aviso sin medida se completa con el contexto del turno siguiente',
    () async {
      // Lleno → comprime → `/compact` sin medida → el turno siguiente sí mide.
      final todo = montar(
        contextos: const [_contextoLleno, null, _contextoComprimido],
      );
      final controlador = todo.container.read(
        assistantControllerProvider(_id).notifier,
      );

      await controlador.submit('resume lo que hicimos');
      final strings = todo.container.read(stringsProvider);
      await hastaQue(
        () => todo.container
            .read(assistantControllerProvider(_id))
            .messages
            .any((m) => m.text == strings.compactedUnknown),
        esperando: 'el aviso de la compresión sin medida',
        loQueSeVe: () =>
            'en pantalla: '
            '${todo.container.read(assistantControllerProvider(_id)).messages.map((m) => m.text)}',
      );

      var estado = todo.container.read(assistantControllerProvider(_id));
      expect(
        estado.messages.map((m) => m.text),
        contains(strings.compactedUnknown),
        reason: 'de momento solo se puede prometer la medida',
      );

      await controlador.submit('y ahora sigue');
      await hastaQue(
        () => todo.container
            .read(assistantControllerProvider(_id))
            .messages
            .any((m) => m.text == strings.compacted(90, 30)),
        esperando: 'el aviso completado con la medida del turno siguiente',
        loQueSeVe: () =>
            'en pantalla: '
            '${todo.container.read(assistantControllerProvider(_id)).messages.map((m) => m.text)}',
      );

      estado = todo.container.read(assistantControllerProvider(_id));
      expect(
        estado.messages.map((m) => m.text),
        contains(strings.compacted(90, 30)),
        reason:
            'el turno siguiente trae el contexto nuevo: 180k y 60k de una '
            'ventana de 200k son el 90 % y el 30 %',
      );
      expect(
        estado.messages.map((m) => m.text),
        isNot(contains(strings.compactedUnknown)),
        reason:
            'se reescribe el mismo mensaje, no se añade otro: dos avisos para '
            'una compresión se leerían como dos compresiones',
      );
    },
  );
}
