import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

void main() {
  // Claude Code guarda el token de cada perfil en el llavero con el nombre
  // `Claude Code-credentials-<sha256(directorio)[:8]>`. Comprobado contra el
  // llavero de esta máquina: `.claude` es 1a5cfcd2 y `.claude-work`, 5fd47d76.
  // Si esa fórmula cambia, todos los perfiles pasarían a verse «sin sesión».
  test('el servicio del llavero sale del directorio del perfil', () {
    expect(
      ClaudeProfilesDataSource.keychainService('/Users/diego.hoyos/.claude'),
      'Claude Code-credentials-1a5cfcd2',
    );
    expect(
      ClaudeProfilesDataSource.keychainService(
        '/Users/diego.hoyos/.claude-work',
      ),
      'Claude Code-credentials-5fd47d76',
    );
  });

  group('la cuenta va con la carpeta', () {
    test('se guarda y se vuelve a leer', () {
      const folder = PairedFolder(
        path: '/repo',
        modality: FolderModality.textOnly,
        claudeProfile: '/Users/alguien/.claude-work',
      );

      final leida = PairedFolder.fromJson(folder.toJson())!;

      expect(leida.claudeProfile, '/Users/alguien/.claude-work');
      expect(leida.modality, FolderModality.textOnly);
    });

    // Lo guardado antes de que esto existiera no trae el campo, y eso no puede
    // impedir leer la carpeta: se entiende como «la cuenta de siempre».
    test('una carpeta guardada sin cuenta usa la de siempre', () {
      final leida = PairedFolder.fromJson({
        'path': '/repo',
        'modality': 'voice',
      })!;

      expect(leida.claudeProfile, isNull);
      expect(leida.modality, FolderModality.voice);
    });

    // Modelo y esfuerzo viven donde la cuenta, y por lo mismo: un repo grande
    // pide Opus y una nota rápida se contesta con Haiku.
    test('el modelo y el esfuerzo también van con la carpeta', () {
      const folder = PairedFolder(
        path: '/repo',
        modality: FolderModality.voice,
        claudeModel: 'opus',
        claudeEffort: 'high',
      );

      final leida = PairedFolder.fromJson(folder.toJson())!;

      expect(leida.claudeModel, 'opus');
      expect(leida.claudeEffort, 'high');
    });

    test('una carpeta sin modelo deja decidir al CLI', () {
      final leida = PairedFolder.fromJson({
        'path': '/repo',
        'modality': 'voice',
      })!;

      expect(leida.claudeModel, isNull);
      expect(leida.claudeEffort, isNull);
    });

    test('cambiar de cuenta no toca el permiso de voz', () {
      const folder = PairedFolder(
        path: '/repo',
        modality: FolderModality.voice,
      );

      final cambiada = folder.copyWith(claudeProfile: '/x/.claude-private');

      expect(cambiada.modality, FolderModality.voice);
      expect(cambiada.claudeProfile, '/x/.claude-private');
    });
  });
}
