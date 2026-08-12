import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/presentation/state/activity_layout.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';

ActivityItem step(
  String id, {
  String? parentId,
  bool done = false,
  String description = 'paso',
}) => ActivityItem(
  id: id,
  description: description,
  writes: false,
  done: done,
  parentId: parentId,
);

void main() {
  test('sin delegaciones, el orden es el de llegada y todo va al ras', () {
    final rows = layoutActivity([step('a', done: true), step('b')]);

    expect(rows.map((r) => r.item.id), ['a', 'b']);
    expect(rows.every((r) => r.depth == 0), isTrue);
  });

  test('lo que hace el subagente cuelga de la delegación', () {
    final rows = layoutActivity([
      step('lee', done: true),
      step('delega'),
      step('sub1', parentId: 'delega', done: true),
      step('sub2', parentId: 'delega'),
    ]);

    expect(rows.map((r) => r.item.id), ['lee', 'delega', 'sub1', 'sub2']);
    expect(rows.map((r) => r.depth), [0, 0, 1, 1]);
  });

  // El motivo de que esto viva fuera del widget: agrupar por orden de llegada
  // parecía suficiente hasta que Claude abre dos delegaciones a la vez y sus
  // pasos llegan intercalados.
  test('dos delegaciones a la vez no se mezclan', () {
    final rows = layoutActivity([
      step('dA'),
      step('dB'),
      step('a1', parentId: 'dA'),
      step('b1', parentId: 'dB'),
      step('a2', parentId: 'dA'),
    ]);

    expect(rows.map((r) => r.item.id), ['dA', 'a1', 'a2', 'dB', 'b1']);
    expect(rows.map((r) => r.depth), [0, 1, 1, 0, 1]);
  });

  group('cuál está corriendo', () {
    test('es el paso del subagente, no la delegación que lo espera', () {
      final rows = layoutActivity([
        step('delega'),
        step('sub', parentId: 'delega'),
      ]);

      expect(rows.firstWhere((r) => r.item.id == 'delega').running, isFalse);
      expect(rows.firstWhere((r) => r.item.id == 'sub').running, isTrue);
    });

    test('con todo terminado no corre ninguno', () {
      final rows = layoutActivity([
        step('a', done: true),
        step('b', done: true),
      ]);

      expect(rows.any((r) => r.running), isFalse);
    });

    test('vuelve a la delegación cuando su subagente ya terminó', () {
      final rows = layoutActivity([
        step('delega'),
        step('sub', parentId: 'delega', done: true),
      ]);

      expect(rows.firstWhere((r) => r.item.id == 'delega').running, isTrue);
    });
  });

  test('un paso huérfano se enseña igual, al final y al ras', () {
    final rows = layoutActivity([
      step('lee', done: true),
      step('perdido', parentId: 'delegacion-que-nunca-llego'),
    ]);

    expect(rows.map((r) => r.item.id), ['lee', 'perdido']);
    expect(rows.last.depth, 0);
  });

  test('nada que colocar, nada que pintar', () {
    expect(layoutActivity(const []), isEmpty);
  });
}
