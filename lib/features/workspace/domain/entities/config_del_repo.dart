import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Lo que un repositorio declara sobre cómo se trabaja en él, versionado dentro
/// del propio repositorio en `.nexus/config.json`.
///
/// Es el paso de «herramienta personal» a «estándar de squad»: hasta ahora los
/// comandos vetados, la carpeta de pruebas y la modalidad vivían en las
/// preferencias de **cada** Mac, así que no se podían revisar en un PR ni
/// heredar al clonar. Lo que sabe el repo sobre sí mismo —que `build_runner`
/// tarda cuatro minutos, que sus flows están en `flows/`, que su contenido no
/// puede salir hacia un tercero— se aprendía una vez por persona.
///
/// ## La regla que lo hace seguro de adoptar
///
/// Un archivo que viaja dentro de un repositorio lo escribe **quien haya
/// escrito ese repositorio**, y clonar no puede ser un permiso. Así que cada
/// campo cae en uno de tres cajones, y ninguno de los tres deja que el archivo
/// abra nada:
///
/// 1. **Aprieta.** [soloTexto], [soloLectura] y [comandosVetados] solo pueden
///    restringir. Un repo puede apagarte la voz; no puede encenderla. Puede
///    añadir comandos a la lista de vetados; no puede quitar los tuyos.
/// 2. **Manda.** [carpetaDePruebas] es un hecho del repositorio y no una
///    opinión tuya —es la misma doctrina que ya escribía `pruebasEn`: la
///    declaración gana a la preferencia—. No abre ninguna puerta: solo dice
///    dónde mirar.
/// 3. **Sugiere.** [modelo] y [esfuerzo] son la propuesta del repo para quien
///    no ha elegido nada. Tu elección explícita gana, porque el cupo que se
///    gasta es el tuyo.
///
/// Lo que **nunca** se lee de aquí: la cuenta de Claude y el repo activo. Son
/// rutas del disco de una persona; versionarlas sería romperle el arranque a
/// todos los demás.
@immutable
class ConfigDelRepo {
  const ConfigDelRepo({
    this.soloTexto = false,
    this.soloLectura = false,
    this.comandosVetados = const [],
    this.carpetaDePruebas,
    this.modelo,
    this.esfuerzo,
    this.avisos = const [],
  });

  /// Dónde se busca, relativo a donde Claude trabaja de verdad.
  ///
  /// Una carpeta y no un archivo suelto en la raíz, igual que `.vscode/`: deja
  /// sitio para lo que venga después sin volver a discutir el nombre.
  static const archivo = '.nexus/config.json';

  /// El contenido de este repositorio no sale hacia el servicio de voz.
  final bool soloTexto;

  /// Aquí no se escribe, esté como esté el interruptor de la barra.
  final bool soloLectura;

  /// Comandos que Claude no ejecuta aquí. Se **suman** a los tuyos.
  final List<String> comandosVetados;

  /// Dónde viven las pruebas de este repositorio.
  final String? carpetaDePruebas;

  /// Con qué modelo y esfuerzo propone trabajar el repo, para quien no ha
  /// elegido.
  final String? modelo;
  final String? esfuerzo;

  /// Lo que el archivo trae mal, en cristiano y con el nombre del campo.
  ///
  /// No se tira en silencio: este archivo se edita a mano y se revisa en un PR,
  /// así que una llave mal escrita tiene que verse. Un aviso **nunca** concede
  /// nada — lo que no se entiende, no se aplica.
  final List<String> avisos;

  /// Si el archivo declara algo. Uno vacío o ilegible no es lo mismo que uno
  /// que dice «aquí no se escribe».
  bool get declaraAlgo =>
      soloTexto ||
      soloLectura ||
      comandosVetados.isNotEmpty ||
      carpetaDePruebas != null ||
      modelo != null ||
      esfuerzo != null;

  /// Lo que este repositorio le hace a la configuración que tengas tú.
  ///
  /// El orden importa y es siempre el mismo: se parte de lo tuyo y solo se
  /// aprieta. Ninguna rama de este método puede devolver una carpeta con más
  /// permiso del que entró.
  PairedFolder aplicarA(PairedFolder tuya) {
    final vetados = [
      ...tuya.blockedCommands,
      for (final comando in comandosVetados)
        if (!tuya.blockedCommands.contains(comando)) comando,
    ];

    return PairedFolder(
      path: tuya.path,
      // Solo hacia adentro: si el repo pide solo texto se cumple, y si no pide
      // nada se respeta lo tuyo. No existe el camino que devuelve `voice`.
      modality: soloTexto ? FolderModality.textOnly : tuya.modality,
      claudeProfile: tuya.claudeProfile,
      claudeModel: tuya.claudeModel ?? modelo,
      claudeEffort: tuya.claudeEffort ?? esfuerzo,
      activeRepo: tuya.activeRepo,
      blockedCommands: vetados,
      // **La tuya, y el repo no la toca.** Los vetados se suman porque un repo
      // puede cerrarse puertas a sí mismo; los permitidos no se leen siquiera,
      // porque un archivo que se concede permisos es un repo que clonas y ya
      // puede ejecutar. Ampliar es decisión de quien empareja la carpeta.
      allowedCommands: tuya.allowedCommands,
      carpetaDePruebas: carpetaDePruebas ?? tuya.carpetaDePruebas,
    );
  }

  /// Lee el archivo. Devuelve `null` solo si no hay nada que leer; un archivo
  /// roto devuelve una configuración vacía **con avisos**, que es distinto de
  /// no tener archivo.
  static ConfigDelRepo? deTexto(String? texto) {
    if (texto == null) return null;
    final crudo = texto.trim();
    if (crudo.isEmpty) return null;

    final Object? decodificado;
    try {
      decodificado = jsonDecode(crudo);
    } on FormatException catch (error) {
      return ConfigDelRepo(avisos: ['No es JSON válido: ${error.message}']);
    }
    if (decodificado is! Map<String, dynamic>) {
      return const ConfigDelRepo(
        avisos: ['La raíz del archivo tiene que ser un objeto `{ }`'],
      );
    }

    // Un local aparte y no `decodificado` a secas: la promoción del `is!` de
    // arriba no entra en las funciones de abajo, que sí lo necesitan.
    final mapa = decodificado;
    final avisos = <String>[];

    bool bandera(String llave) {
      final valor = mapa[llave];
      if (valor == null) return false;
      if (valor is bool) return valor;
      avisos.add('`$llave` tiene que ser `true` o `false`');
      return false;
    }

    String? texto_(String llave) {
      final valor = mapa[llave];
      if (valor == null) return null;
      if (valor is String && valor.trim().isNotEmpty) return valor.trim();
      avisos.add('`$llave` tiene que ser un texto');
      return null;
    }

    final comandos = <String>[];
    final lista = mapa['comandosVetados'];
    if (lista is List) {
      for (final entrada in lista) {
        if (entrada is String && entrada.trim().isNotEmpty) {
          comandos.add(entrada.trim());
        } else {
          avisos.add('`comandosVetados` solo admite textos');
        }
      }
    } else if (lista != null) {
      avisos.add('`comandosVetados` tiene que ser una lista');
    }

    for (final llave in mapa.keys) {
      if (!_llaves.contains(llave)) {
        avisos.add('`$llave` no se reconoce, así que no se aplica');
      }
    }

    return ConfigDelRepo(
      soloTexto: bandera('soloTexto'),
      soloLectura: bandera('soloLectura'),
      comandosVetados: comandos,
      carpetaDePruebas: texto_('carpetaDePruebas'),
      modelo: texto_('modelo'),
      esfuerzo: texto_('esfuerzo'),
      avisos: avisos,
    );
  }

  /// Las únicas llaves que existen. Lo que no esté aquí se avisa y se ignora:
  /// una llave inventada no puede conceder nada por parecerse a otra.
  static const _llaves = {
    'soloTexto',
    'soloLectura',
    'comandosVetados',
    'carpetaDePruebas',
    'modelo',
    'esfuerzo',
  };
}
