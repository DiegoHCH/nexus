import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abrir una conversación no puede borrar las que había.
///
/// El notifier devuelve la lista **vacía** al construirse y lee el disco después. En
/// esa ventana, `open` construía el estado nuevo a partir de una lista vacía y
/// persistía una lista con **solo la nueva** — así se perdió una conversación con su
/// contenido: quedó un id nuevo sobre la misma carpeta y el registro viejo huérfano en
/// disco, que es por lo que al reabrir la app el chat aparecía en blanco.

const _carpeta = '/Users/alguien/personal/nexus';
const _otra = '/Users/alguien/General';

class _Disco implements ConversationsDataSource {
  _Disco(this.contenido);

  Map<String, dynamic> contenido;
  var lecturas = 0;

  @override
  Future<Map<String, dynamic>> read() async {
    lecturas++;
    // Con una vuelta de espera: el disco no contesta en el mismo microtask, y es
    // justo esa demora la que abría la ventana.
    await Future<void>.delayed(Duration.zero);
    return contenido;
  }

  @override
  Future<void> write(Map<String, dynamic> json) async => contenido = json;
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [
      PairedFolder(path: _carpeta, modality: FolderModality.voice),
      PairedFolder(path: _otra, modality: FolderModality.voice),
    ],
    activePath: _carpeta,
  );
}

void main() {
  // `open` marca la carpeta activa, y eso pasa por preferencias: sin binding lanza, y
  // el sintoma se disfraza del fallo que se esta midiendo.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('abrir justo al arrancar no se lleva la que ya había', () async {
    final disco = _Disco({
      'items': [
        {'id': 'la-que-tenia', 'folderPath': _carpeta},
      ],
      'focusedId': 'la-que-tenia',
    });
    final c = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(disco),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(c.dispose);

    // **Sin dar ninguna vuelta**: se abre en el mismo instante en que se construye,
    // que es la ventana donde el estado todavía está vacío.
    final nueva = await c.read(conversationsProvider.notifier).open(_otra);

    final ids = c.read(conversationsProvider).items.map((i) => i.id).toList();
    expect(
      ids,
      containsAll(['la-que-tenia', nueva]),
      reason:
          'la de antes tiene que seguir ahí: perderla borra su contenido de vista',
    );
    // Y lo guardado también, que es lo que se lee al reabrir la app.
    expect(
      (disco.contenido['items'] as List).length,
      2,
      reason:
          'si el disco se queda con una, reabrir la app enseña un chat en blanco',
    );
  });

  test('cerrar justo al arrancar tampoco vacía la lista', () async {
    final disco = _Disco({
      'items': [
        {'id': 'una', 'folderPath': _carpeta},
        {'id': 'otra', 'folderPath': _otra},
      ],
      'focusedId': 'una',
    });
    final c = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(disco),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(c.dispose);

    await c.read(conversationsProvider.notifier).close('una');

    expect(c.read(conversationsProvider).items.map((i) => i.id), [
      'otra',
    ], reason: 'cerrar una no puede convertirse en «dejar la lista vacía»');
  });

  test('renombrar justo al arrancar no borra las demás', () async {
    final disco = _Disco({
      'items': [
        {'id': 'una', 'folderPath': _carpeta},
        {'id': 'otra', 'folderPath': _otra},
      ],
      'focusedId': 'una',
    });
    final c = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(disco),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(c.dispose);

    await c
        .read(conversationsProvider.notifier)
        .renombrar('una', 'lo del login');

    final items = c.read(conversationsProvider).items;
    expect(items, hasLength(2));
    expect(items.firstWhere((i) => i.id == 'una').name, 'lo del login');
  });
  test('«vacio» y «todavia no se» no son lo mismo', () async {
    // Es el fallo que veia el usuario: al arrancar, la lista nace vacia y el disco se
    // lee despues, asi que la pantalla de primera vez aparecia en una app que SI tenia
    // una conversacion abierta — y tocar el orbe ahi creaba otra en vez de traer la
    // suya. `cargado` es lo que separa las dos cosas.
    final disco = _Disco({
      'items': [
        {'id': 'la-que-tenia', 'folderPath': _carpeta},
      ],
      'focusedId': 'la-que-tenia',
    });
    final c = ProviderContainer(
      overrides: [
        conversationsDataSourceProvider.overrideWithValue(disco),
        workspaceControllerProvider.overrideWith(_Espacio.new),
      ],
    );
    addTearDown(c.dispose);

    // Recien construido: vacio **y sin cargar**, que es lo que la pantalla tiene que
    // poder distinguir.
    final recien = c.read(conversationsProvider);
    expect(recien.items, isEmpty);
    expect(
      recien.cargado,
      isFalse,
      reason: 'sin esto la pantalla dice «no tienes ninguna» antes de saberlo',
    );

    await c.read(conversationsProvider.notifier).open(_otra);
    expect(c.read(conversationsProvider).cargado, isTrue);
  });
  test('la pantalla no decide antes de saber', () {
    // Comprobacion **sobre el codigo** y se dice por que: levantar `HomePage` entera
    // aqui pide voz, micro, atajos y ventana, y costaria mucho mas de lo que mide. Lo
    // que se ata es el orden, que es justo lo que estaba mal: preguntaba «hay alguna
    // con el foco?» antes de saber si la lista estaba leida.
    final home = File(
      'lib/features/assistant/presentation/pages/home_page.dart',
    ).readAsStringSync();

    final guarda = home.indexOf('if (!conversaciones.cargado)');
    final decision = home.indexOf(
      'if (focused == null) return const _FirstRun();',
    );

    expect(guarda, isNot(-1), reason: 'la pantalla volvio a decidir sin saber');
    expect(
      guarda,
      lessThan(decision),
      reason:
          'preguntar por el foco antes de que la lista este leida es lo que '
          'enseñaba la pantalla de primera vez en una app con conversaciones',
    );
  });
}
