import 'dart:async';
import 'package:nexus/features/artifacts/data/datasources/modelo_de_imagen_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/modelo_de_imagen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/data/repositories/gemini_image_key_store_impl.dart';
import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final artifactsDataSourceProvider = Provider<ArtifactsDataSource>(
  (ref) => const ArtifactsDataSource(),
);

/// La carpeta donde acaban los documentos generados.
///
/// Una sola y no una por cuenta: un mockup no es de `work` ni de `private`, es
/// tuyo. La cuenta separa memoria y contexto —lo que Claude sabe de cada
/// mundo—; un archivo terminado no tiene ese problema.
///
/// Vacía de partida a propósito. Escribir en el disco del usuario en un sitio
/// que él no ha elegido es exactamente lo que no se hace aquí, igual que con el
/// archivo de conversaciones.
class ArtifactsFolder extends Notifier<String?> {
  static const _key = 'artifacts.folder';

  /// Se completa cuando la carpeta **ya se leyó del disco**. Mismo motivo que en los
  /// ajustes del archivo: `build()` devuelve `null` y carga después, así que el
  /// teléfono —que pide la lista una vez— recibía «no hay carpeta» y enseñaba cero
  /// documentos habiendo uno.
  late final Future<void> cargada;

  @override
  String? build() {
    cargada = _load().catchError((Object _) {});
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null && stored.isNotEmpty) state = stored;
  }

  Future<void> choose(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
    state = path;
    ref.invalidate(artifactsProvider);
  }
}

final artifactsFolderProvider = NotifierProvider<ArtifactsFolder, String?>(
  ArtifactsFolder.new,
);

/// Lo que hay en esa carpeta ahora mismo.
///
/// Se relee al abrir la lista y no se guarda: los documentos los escribe Claude
/// mientras la app está abierta, así que una copia cacheada estaría vieja justo
/// cuando importa —al terminar el encargo que acabas de pedir—.
final artifactsProvider = FutureProvider<List<Artifact>>((ref) async {
  final folder = ref.watch(artifactsFolderProvider);
  if (folder == null) return const [];
  // Las cuentas del Mac, para saber en qué subcarpetas se puede entrar. Si no se
  // pueden leer, se sigue con la raíz: quedarse sin lista por eso sería peor.
  final cuentas = await ref
      .watch(claudeProfilesProvider.future)
      .then((p) => p.map((c) => c.name).toSet())
      .onError((_, _) => const <String>{});
  return ref.watch(artifactsDataSourceProvider).list(folder, cuentas: cuentas);
});

/// La llave con la que se generan imágenes. Ver [GeminiImageKeyStore] para por
/// qué no es la misma que la de voz.
final geminiImageKeyStoreProvider = Provider<GeminiImageKeyStore>(
  (ref) => GeminiImageKeyStoreImpl(SecureStorageDataSource()),
);

/// Si hay una puesta **para esa cuenta**. La pantalla solo pregunta eso: el
/// valor no sale nunca.
final hayLlaveDeImagenesProvider = FutureProvider.family<bool, String?>(
  (ref, perfil) async =>
      await ref.watch(geminiImageKeyStoreProvider).read(perfil) != null,
);

final modeloDeImagenDataSourceProvider = Provider<ModeloDeImagenDataSource>(
  (ref) => const ModeloDeImagenDataSource(),
);

/// Con qué modelo se dibuja. Se elige en Ajustes y vale desde el siguiente
/// encargo.
class ModeloDeImagenController extends Notifier<ModeloDeImagen> {
  @override
  ModeloDeImagen build() {
    unawaited(_cargar());
    return ModeloDeImagen.nanoBanana2;
  }

  Future<void> _cargar() async {
    final guardado = await ref.read(modeloDeImagenDataSourceProvider).read();
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaría en vez de no hacer nada.
    if (!ref.mounted) return;
    state = ModeloDeImagen.porId(guardado);
  }

  Future<void> elegir(ModeloDeImagen modelo) async {
    state = modelo;
    await ref.read(modeloDeImagenDataSourceProvider).write(modelo.id);
  }
}

final modeloDeImagenProvider =
    NotifierProvider<ModeloDeImagenController, ModeloDeImagen>(
      ModeloDeImagenController.new,
    );
