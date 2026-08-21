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
  group('el nombre de la cuenta desde su ruta', () {
    // Existe como funcion pura porque quien arranca un encargo necesita el nombre en
    // ese mismo instante, y listar las cuentas del disco es asincrono.
    test('saca el nombre de un .claude-*', () {
      expect(ClaudeProfile.nameFromPath('/Users/alguien/.claude-work'), 'work');
    });

    test('la de siempre no es una cuenta', () {
      // `.claude` a secas significa «la por defecto», que es la opcion de arriba y no
      // una cuenta con nombre. Devolver algo aqui inventaria una subcarpeta.
      expect(ClaudeProfile.nameFromPath('/Users/alguien/.claude'), isNull);
      expect(ClaudeProfile.nameFromPath(null), isNull);
      expect(ClaudeProfile.nameFromPath(''), isNull);
    });

    test('una barra al final no lo despista', () {
      expect(
        ClaudeProfile.nameFromPath('/Users/alguien/.claude-private/'),
        'private',
      );
    });
  });
}
