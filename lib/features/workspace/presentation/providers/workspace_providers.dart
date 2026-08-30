import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/workspace/data/datasources/workspace_preferences_data_source.dart';
import 'package:nexus/features/workspace/data/repositories/workspace_store_impl.dart';
import 'package:nexus/features/workspace/data/datasources/claude_auth_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/repo_config_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';

final workspaceStoreProvider = Provider<WorkspaceStore>(
  (ref) => const WorkspaceStoreImpl(WorkspacePreferencesDataSource()),
);

final folderPickerProvider = Provider<FolderPicker>(
  (ref) => const SystemFolderPicker(),
);

/// El lector del `.nexus/` de cada repositorio. Una sola instancia para que la
/// caché por fecha y tamaño sobreviva a los repasos.
final repoConfigDataSourceProvider = Provider<RepoConfigDataSource>(
  (ref) => RepoConfigDataSource(),
);

/// El home del usuario, para pintar las rutas con `~` como en el mockup.
final homeDirectoryProvider = Provider<String>(
  (ref) => Platform.environment['HOME'] ?? '',
);

/// Las carpetas emparejadas y sus permisos, en memoria y en disco.
class WorkspaceController extends Notifier<Workspace> {
  /// **Lo que has elegido tú**, tal cual va al disco.
  ///
  /// Está separado de `state` porque `state` es lo que queda **después** de que
  /// el repositorio apriete lo suyo, y los dos tienen que existir a la vez: si
  /// los ajustes escribieran sobre lo apretado, cambiar de modelo en un repo que
  /// pide solo texto te borraría tu propia preferencia de voz sin decir nada.
  /// Todo lo que se guarda se calcula sobre este; nada se calcula sobre `state`.
  Workspace _guardado = const Workspace();

  Workspace get guardado => _guardado;

  @override
  Workspace build() {
    unawaited(_load());
    return const Workspace();
  }

  Future<void> _load() async {
    _guardado = await ref.read(workspaceStoreProvider).read();
    await _releer();
  }

  Future<void> _persist(Workspace next) async {
    _guardado = next;
    state = next;
    await ref.read(workspaceStoreProvider).save(next);
    await _releer();
  }

  /// Vuelve a leer lo que declara cada repositorio y rehace el estado efectivo.
  ///
  /// Público porque el archivo cambia también por fuera de la app —un `git
  /// pull`, o el propio Claude editándolo— y no hay ningún evento que lo diga.
  /// No hace falta vigilarlo como a las reglas de `CLAUDE.md`: eso avisa porque
  /// un cambio ahí puede pedirle a Claude algo nuevo, y esto solo puede
  /// apretar. Releer tarde es quedarse con **más** restricción, nunca con menos.
  Future<void> recargar() => _releer();

  Future<void> _releer() async {
    final configs = await ref.read(repoConfigDataSourceProvider).leerTodas({
      for (final folder in _guardado.folders)
        folder.path: folder.workingDirectory,
    });

    // Leer el disco es un hueco, y el provider puede haberse ido en él —pasa en
    // cada prueba que monta la superficie y la tira—. Sin esto, el `state` de
    // abajo revienta contra un `Ref` ya desechado.
    if (!ref.mounted) return;

    final folders = [
      for (final folder in _guardado.folders)
        configs[folder.path]?.aplicarA(folder) ?? folder,
    ];

    // El interruptor de escritura es de la app, así que lo aprieta el repo que
    // esté delante: si el activo dice solo lectura, no se escribe aunque el
    // interruptor de la barra esté dado. Al revés no: un repo no puede dar
    // escritura que tú no diste.
    final activo = configs[_guardado.activePath];
    state = _guardado.copyWith(
      folders: folders,
      delRepo: configs,
      permission: activo?.soloLectura ?? false
          ? FilePermission.readOnly
          : _guardado.permission,
    );
  }

  /// Abre el diálogo del sistema y empareja lo que se elija.
  ///
  /// La carpeta nueva entra en **solo texto**: el modo restrictivo. Si entrara
  /// en voz, la primera carpeta emparejada se filtraría hacia Google por
  /// omisión, que es exactamente el fallo que este control existe para evitar
  /// (decisión i5).
  Future<void> pairFolder() async {
    final path = await ref.read(folderPickerProvider).pickFolder();
    if (path == null) return;
    if (_guardado.folders.any((folder) => folder.path == path)) {
      await _persist(_guardado.copyWith(activePath: path));
      return;
    }

    final folder = PairedFolder(path: path, modality: FolderModality.textOnly);
    await _persist(
      _guardado.copyWith(
        folders: [..._guardado.folders, folder],
        activePath: path,
      ),
    );
  }

  Future<void> removeFolder(String path) async {
    final folders = _guardado.folders
        .where((folder) => folder.path != path)
        .toList();
    final wasActive = _guardado.activePath == path;
    await _persist(
      Workspace(
        folders: folders,
        activePath: wasActive ? null : _guardado.activePath,
        permission: _guardado.permission,
      ),
    );
  }

  Future<void> setActive(String path) async {
    if (_guardado.activePath == path) return;
    await _persist(_guardado.copyWith(activePath: path));
  }

  Future<void> setModality(String path, FolderModality modality) async {
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          folder.copyWith(modality: modality)
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  /// Con qué cuenta de Claude trabaja esta carpeta. `null` vuelve a la de
  /// siempre.
  /// **Se rehace entera y a mano porque `copyWith` no puede vaciar un campo**, y elegir
  /// dos veces la misma cuenta significa «la de fábrica». El precio de rehacerla es que
  /// hay que nombrar todos los campos: la versión que solo nombraba tres **borraba el
  /// modelo, el esfuerzo, el repo activo y los comandos bloqueados** cada vez que alguien
  /// cambiaba de cuenta, y eso no fallaba en ninguna parte — se perdía y ya.
  Future<void> setClaudeProfile(String path, String? profile) async {
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          PairedFolder(
            path: folder.path,
            modality: folder.modality,
            claudeProfile: profile,
            claudeModel: folder.claudeModel,
            claudeEffort: folder.claudeEffort,
            activeRepo: folder.activeRepo,
            blockedCommands: folder.blockedCommands,
            carpetaDePruebas: folder.carpetaDePruebas,
          )
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  /// El modelo y el esfuerzo de esta carpeta. `null` en cualquiera devuelve
  /// esa decisión al CLI.
  /// Sobre qué repo de dentro se trabaja. `null` vuelve a la carpeta entera,
  /// que es lo correcto cuando el encargo cruza varios.
  Future<void> setActiveRepo(String path, String? repo) async {
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          PairedFolder(
            path: folder.path,
            modality: folder.modality,
            claudeProfile: folder.claudeProfile,
            claudeModel: folder.claudeModel,
            claudeEffort: folder.claudeEffort,
            activeRepo: repo,
            blockedCommands: folder.blockedCommands,
            carpetaDePruebas: folder.carpetaDePruebas,
          )
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  /// Lo que Claude no puede ejecutar en esta carpeta.
  Future<void> setBlockedCommands(String path, List<String> commands) async {
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          PairedFolder(
            path: folder.path,
            modality: folder.modality,
            claudeProfile: folder.claudeProfile,
            claudeModel: folder.claudeModel,
            claudeEffort: folder.claudeEffort,
            activeRepo: folder.activeRepo,
            blockedCommands: commands,
            carpetaDePruebas: folder.carpetaDePruebas,
          )
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  Future<void> setClaudeModel(String path, String? model) => _replace(
    path,
    (folder) => folder.claudeModel == model ? null : model,
    null,
  );

  Future<void> setClaudeEffort(String path, String? effort) => _replace(
    path,
    null,
    (folder) => folder.claudeEffort == effort ? null : effort,
  );

  /// Dónde están las pruebas de esta carpeta. Vacío vuelve a la convención de Maestro.
  ///
  /// **Es lo que impide que se mezclen las de dos proyectos**: cada uno apunta a su
  /// subcarpeta y Nexus lista esa. La separación deja de depender de un filtro y pasa a
  /// depender de dónde miras, que no se puede equivocar.
  Future<void> setCarpetaDePruebas(String path, String? carpeta) async {
    final limpia = carpeta?.trim();
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          folder.copyWith(
            carpetaDePruebas: limpia,
            sinCarpetaDePruebas: limpia == null || limpia.isEmpty,
          )
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  /// Volver a elegir lo que ya estaba puesto lo quita: es la forma de decir
  /// «lo que decida el CLI» sin una opción aparte para eso.
  Future<void> _replace(
    String path,
    String? Function(PairedFolder)? model,
    String? Function(PairedFolder)? effort,
  ) async {
    final folders = [
      for (final folder in _guardado.folders)
        if (folder.path == path)
          PairedFolder(
            path: folder.path,
            modality: folder.modality,
            claudeProfile: folder.claudeProfile,
            claudeModel: model == null ? folder.claudeModel : model(folder),
            claudeEffort: effort == null ? folder.claudeEffort : effort(folder),
            activeRepo: folder.activeRepo,
            blockedCommands: folder.blockedCommands,
            carpetaDePruebas: folder.carpetaDePruebas,
          )
        else
          folder,
    ];
    await _persist(_guardado.copyWith(folders: folders));
  }

  Future<void> setPermission(FilePermission permission) async {
    if (_guardado.permission == permission) return;
    await _persist(_guardado.copyWith(permission: permission));
  }

  void togglePermission() {
    unawaited(
      setPermission(
        _guardado.permission == FilePermission.readOnly
            ? FilePermission.canEdit
            : FilePermission.readOnly,
      ),
    );
  }
}

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, Workspace>(WorkspaceController.new);

/// Las cuentas de Claude que hay en esta máquina. Se leen una vez: crear un
/// perfil nuevo no es algo que pase mientras Ajustes está abierto.
final claudeProfilesProvider = FutureProvider<List<ClaudeProfile>>(
  (ref) => const ClaudeProfilesDataSource().list(),
);

/// Quien sabe abrir el navegador para entrar en una cuenta.
final claudeAuthProvider = Provider<ClaudeAuthDataSource>(
  (ref) => const ClaudeAuthDataSource(),
);

/// El repositorio y la rama de una carpeta. Se relee al terminar cada turno,
/// porque la rama cambia también por fuera de la app —un `checkout` en la
/// terminal, o el propio Claude—.
final gitInfoProvider = FutureProvider.family<GitInfo?, String>(
  (ref, folderPath) => const GitDataSource().read(folderPath),
);

/// Los repos que hay dentro de una carpeta emparejada. Vacío cuando la carpeta
/// **es** el repo, que es el caso normal y no necesita elegir nada.
final reposInsideProvider = FutureProvider.family<List<String>, String>(
  (ref, folderPath) => const GitDataSource().reposInside(folderPath),
);
