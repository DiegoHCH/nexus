import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';

import '../../domain/usecases/donde_vive_el_repo_de_pruebas.dart';

/// Cómo acabó una sincronización con el remoto.
enum ComoFueLaSync {
  /// No estaba y se clonó.
  clonado,

  /// Estaba y se puso al día con el remoto.
  aldia,

  /// Estaba, tenía cambios sin publicar y **no se tocó**.
  sucio,

  /// No se pudo: sin git, sin red, sin permiso.
  fallo,
}

class ResultadoDeSync {
  const ResultadoDeSync(this.como, {this.clon, this.detalle = ''});

  final ComoFueLaSync como;
  final String? clon;

  /// Qué pasó, en una línea, para poder enseñarlo. Nunca lleva credenciales:
  /// aquí no pasa ninguna.
  final String detalle;

  bool get sirve => clon != null && como != ComoFueLaSync.fallo;
}

/// Cómo acabó publicar un cambio.
class Publicacion {
  const Publicacion({required this.ok, this.rama = '', this.url = '', this.detalle = ''});

  final bool ok;
  final String rama;

  /// La URL del PR. Vacía si se quedó en el push.
  final String url;
  final String detalle;
}

/// El repo de pruebas remoto: clonarlo, mantenerlo al día y publicar en él.
///
/// **Nexus es el único que toca este clon.** No está en tu workspace, no lo abres
/// y no editas dentro. Eso es lo que permite que `ponerAlDia` haga `reset --hard`
/// sin pensarlo dos veces: no hay trabajo de nadie que perder. La única excepción
/// —un push que falló y dejó cosas sin publicar— se detecta y se respeta.
///
/// 🔴 **Aquí no entra ninguna credencial.** Las variables de una cuenta se le pasan
/// a Maestro por `-e` desde `LasVariablesDelProyecto`; no se escribe ningún
/// `config.yaml` dentro del clon. Es lo que hace imposible empujar una contraseña
/// por accidente: no está en el sitio desde el que se empuja.
class RepoDePruebasDataSource {
  const RepoDePruebasDataSource();

  /// Deja el clon listo para usar: lo crea si no está, lo actualiza si sí.
  Future<ResultadoDeSync> asegurar({
    required String soporte,
    String slug = DondeViveElRepoDePruebas.slugPorDefecto,
    String rama = DondeViveElRepoDePruebas.ramaPorDefecto,
  }) async {
    final git = await _git();
    if (git == null) {
      return const ResultadoDeSync(
        ComoFueLaSync.fallo,
        detalle: 'No encuentro git en esta máquina.',
      );
    }

    final clon = DondeViveElRepoDePruebas.de(soporte: soporte, slug: slug);
    final esRepo =
        Directory('$clon/.git').existsSync() || File('$clon/.git').existsSync();

    if (!esRepo) {
      // Si la carpeta existe pero no es un repo, es basura de un clonado a medias.
      // Se borra: reintentar sobre ella deja a git quejándose de un destino no
      // vacío y no hay nada ahí que valga la pena conservar.
      final carpeta = Directory(clon);
      if (carpeta.existsSync()) await carpeta.delete(recursive: true);
      await Directory(clon).parent.create(recursive: true);

      final r = await _correr(git, [
        'clone',
        '--branch', rama,
        DondeViveElRepoDePruebas.urlDe(slug),
        clon,
      ], en: Directory(clon).parent.path);

      return r.ok
          ? ResultadoDeSync(ComoFueLaSync.clonado, clon: clon, detalle: 'Clonado $slug.')
          : ResultadoDeSync(ComoFueLaSync.fallo, detalle: _corto(r.error));
    }

    return _ponerAlDia(git, clon: clon, rama: rama);
  }

  Future<ResultadoDeSync> _ponerAlDia(
    String git, {
    required String clon,
    required String rama,
  }) async {
    final sucio = await _correr(git, ['status', '--porcelain'], en: clon);
    if (sucio.ok && sucio.salida.trim().isNotEmpty) {
      return ResultadoDeSync(
        ComoFueLaSync.sucio,
        clon: clon,
        detalle: 'El clon tiene cambios sin publicar; no lo toco.',
      );
    }

    final fetch = await _correr(git, ['fetch', 'origin', rama], en: clon);
    if (!fetch.ok) {
      // Sin red se sigue trabajando con lo que hay: los flows de ayer corren
      // igual, y decir «no se pudo actualizar» es mejor que no dejar correr.
      return ResultadoDeSync(
        ComoFueLaSync.aldia,
        clon: clon,
        detalle: 'No pude hablar con el remoto; uso la copia que ya estaba.',
      );
    }

    await _correr(git, ['checkout', rama], en: clon);
    final reset = await _correr(git, ['reset', '--hard', 'origin/$rama'], en: clon);
    return reset.ok
        ? ResultadoDeSync(ComoFueLaSync.aldia, clon: clon, detalle: 'Al día con origin/$rama.')
        : ResultadoDeSync(ComoFueLaSync.fallo, clon: clon, detalle: _corto(reset.error));
  }

  /// Los flows del clon, como rutas relativas a la raíz del repo.
  ///
  /// Se listan **todos** los `.yaml` bajo `flows/`, incluidos `commons/` y `auth/`:
  /// son flows de verdad y alguno se corre suelto. Quien quiera enseñar solo los
  /// numerados que filtre arriba; aquí no se decide eso.
  Future<List<String>> flows(String clon) async {
    final raiz = Directory(DondeViveElRepoDePruebas.flowsEn(clon));
    if (!raiz.existsSync()) return const [];

    final rutas = <String>[];
    await for (final e in raiz.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final nombre = e.path.split('/').last;
      if (!nombre.endsWith('.yaml') && !nombre.endsWith('.yml')) continue;
      if (nombre.startsWith('.')) continue;
      rutas.add(e.path.substring(clon.length + 1));
    }
    rutas.sort();
    return rutas;
  }

  Future<String?> leer({required String clon, required String ruta}) async {
    final archivo = File('$clon/$ruta');
    if (!archivo.existsSync()) return null;
    try {
      return await archivo.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// Escribe un flow y lo publica: rama, commit, push y PR contra [rama].
  ///
  /// **Rama y PR, no push a main**, porque es el repo de un equipo y alguien mira
  /// antes de que entre. Si el `gh` no está o falla, el push ya se hizo: se devuelve
  /// `ok` con la rama y sin URL, que es un estado útil —el trabajo está a salvo en
  /// el remoto— y no una mentira.
  Future<Publicacion> publicar({
    required String clon,
    required String ruta,
    required String contenido,
    required String mensaje,
    String rama = DondeViveElRepoDePruebas.ramaPorDefecto,
    DateTime? cuando,
  }) async {
    final git = await _git();
    if (git == null) {
      return const Publicacion(ok: false, detalle: 'No encuentro git en esta máquina.');
    }

    final nueva = DondeViveElRepoDePruebas.ramaPara(
      flow: ruta,
      cuando: cuando ?? DateTime.now(),
    );

    final base = await _correr(git, ['checkout', rama], en: clon);
    if (!base.ok) {
      return Publicacion(ok: false, detalle: _corto(base.error));
    }
    final creada = await _correr(git, ['checkout', '-b', nueva], en: clon);
    if (!creada.ok) {
      return Publicacion(ok: false, detalle: _corto(creada.error));
    }

    try {
      final archivo = File('$clon/$ruta');
      await archivo.parent.create(recursive: true);
      await archivo.writeAsString(contenido);
    } on FileSystemException catch (e) {
      await _correr(git, ['checkout', rama], en: clon);
      return Publicacion(ok: false, rama: nueva, detalle: 'No pude escribir el archivo: ${e.message}');
    }

    // `--` separa la ruta de cualquier cosa que git pudiera leer como opción. La
    // ruta viene de dentro del repo, pero el hábito es el que evita el día raro.
    await _correr(git, ['add', '--', ruta], en: clon);

    final commit = await _correr(git, ['commit', '-m', mensaje], en: clon);
    if (!commit.ok) {
      await _correr(git, ['checkout', rama], en: clon);
      // Sin cambios que commitear no es un fallo del sistema: es que el archivo
      // ya estaba igual. Se dice así y no como un error de git.
      final igual = commit.salida.contains('nothing to commit') ||
          commit.error.contains('nothing to commit');
      return Publicacion(
        ok: false,
        rama: nueva,
        detalle: igual ? 'El archivo ya estaba igual: no hay nada que publicar.' : _corto(commit.error),
      );
    }

    final push = await _correr(git, ['push', '-u', 'origin', nueva], en: clon);
    if (!push.ok) {
      return Publicacion(ok: false, rama: nueva, detalle: _corto(push.error));
    }

    final url = await _abrirPr(clon: clon, contra: rama, titulo: mensaje);
    // Se vuelve a la rama base siempre: dejar el clon en una rama de trabajo hace
    // que la siguiente sincronización la vea y no sepa qué hacer con ella.
    await _correr(git, ['checkout', rama], en: clon);

    return Publicacion(
      ok: true,
      rama: nueva,
      url: url ?? '',
      detalle: url == null
          ? 'Empujado a $nueva. El PR ábrelo tú: no pude usar gh.'
          : 'PR abierto.',
    );
  }

  Future<String?> _abrirPr({
    required String clon,
    required String contra,
    required String titulo,
  }) async {
    final gh = await HerramientaExterna.donde(
      'gh',
      candidatos: HerramientaExterna.candidatosDeGh(),
    );
    if (gh == null) return null;

    final r = await _correr(gh, [
      'pr', 'create',
      '--base', contra,
      '--title', titulo,
      '--body', 'Prueba escrita desde Nexus.',
    ], en: clon);
    if (!r.ok) return null;

    final url = RegExp(r'https://\S+').firstMatch(r.salida)?.group(0);
    return url;
  }

  Future<String?> _git() => HerramientaExterna.donde(
    'git',
    candidatos: HerramientaExterna.candidatosDeGit(),
  );

  Future<_Salida> _correr(String binario, List<String> args, {required String en}) async {
    try {
      final r = await Process.run(
        binario,
        args,
        workingDirectory: en,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
      return _Salida(r.exitCode == 0, '${r.stdout}', '${r.stderr}');
    } on ProcessException catch (e) {
      return _Salida(false, '', e.message);
    }
  }

  /// La primera línea con contenido del error. Un stderr de git son diez líneas y
  /// la que importa casi siempre es la última; se prefiere corta y entera a larga
  /// y cortada por la mitad en la UI.
  static String _corto(String error) {
    final lineas = error
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lineas.isEmpty) return 'Falló y no dijo por qué.';
    return lineas.last.length > 200 ? '${lineas.last.substring(0, 200)}…' : lineas.last;
  }
}

class _Salida {
  const _Salida(this.ok, this.salida, this.error);
  final bool ok;
  final String salida;
  final String error;
}
