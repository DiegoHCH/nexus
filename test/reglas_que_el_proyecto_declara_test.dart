import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/project_context_data_source.dart';

/// Que un repo pueda decirle a Nexus qué reglas cargarle.
///
/// Existe por un hueco medido: Nexus solo miraba los `CLAUDE.md` del arbol y el
/// `CONTEXT.md` del repo, asi que un proyecto que guarda sus reglas **repartidas por
/// capa en otro sitio** las tenia invisibles. En el caso real que lo motivo eran
/// **33 archivos y 328 KB**, y ninguno llegaba al modelo: el trabajo salia sin la mitad
/// de la ley del sitio y quien lo revisaba lo devolvia.
///
/// Las elige una persona y no la app, y eso no es una limitacion: 328 KB son dieciseis
/// veces lo que cabe en un encargo, asi que alguien tiene que decidir qué entra.
void main() {
  late Directory repo;

  setUp(() => repo = Directory.systemTemp.createTempSync('repo'));
  tearDown(() => repo.deleteSync(recursive: true));

  File escribir(String ruta, String texto) {
    final f = File('${repo.path}/$ruta')..createSync(recursive: true);
    return f..writeAsStringSync(texto);
  }

  Future<List<String>> reglasDe() async =>
      (await const ProjectContextDataSource().read(
        repo.path,
      )).rules.map((r) => r.content).toList();

  test('sin el archivo, nada cambia', () async {
    escribir('CLAUDE.md', 'la del proyecto');
    expect(await reglasDe(), ['la del proyecto']);
  });

  test('lo declarado se carga, y va despues del CLAUDE.md', () async {
    // El orden es la mitad del valor: esta medido que Claude Code aplica todos los
    // `CLAUDE.md` **sin jerarquia**, y lo que funciona es repetirlos en orden porque lo
    // ultimo leido es lo que pesa. Las reglas que el repo declara para si mismo son las
    // que mandan, asi que van al final.
    escribir('CLAUDE.md', 'la del proyecto');
    escribir('reglas/dominio.md', 'el dominio no conoce la base de datos');
    escribir('.nexus-reglas', 'reglas/dominio.md\n');

    expect(await reglasDe(), [
      'la del proyecto',
      'el dominio no conoce la base de datos',
    ]);
  });

  test('respeta el orden en que se declararon', () async {
    // Quien escribe el archivo esta decidiendo prioridad, no solo qué entra.
    escribir('reglas/a.md', 'primera');
    escribir('reglas/b.md', 'segunda');
    escribir('.nexus-reglas', 'reglas/a.md\nreglas/b.md\n');

    expect(await reglasDe(), ['primera', 'segunda']);
  });

  test('los comentarios y las lineas vacias no son rutas', () async {
    escribir('reglas/a.md', 'la buena');
    escribir('.nexus-reglas', '''
# Las reglas de este repo, en orden de peso.

reglas/a.md

# reglas/desactivada.md  ← comentada a proposito
''');

    expect(await reglasDe(), ['la buena']);
  });

  test('las reglas por capa no se cargan aqui: las pone el gancho', () async {
    // **El fallo que esto cierra.** La forma con flecha la añadio el gancho, que carga la
    // regla justo antes de cada edicion sabiendo que archivo se toca. Este lado no se
    // entero y trataba la linea entera como una ruta, asi que cada encargo se llevaba un
    // «Nexus no encontro esta regla declarada: **/domain/** -> …» — un aviso falso, en
    // todos los encargos, sobre una regla que si existia y llegaba por otro camino.
    escribir('reglas/siempre.md', 'esta va en todos');
    escribir('reglas/dominio.md', 'esta la pone el gancho');
    escribir('.nexus-reglas', '''
reglas/siempre.md
**/domain/** -> reglas/dominio.md
''');

    final reglas = await reglasDe();
    expect(reglas, contains('esta va en todos'));
    expect(reglas, isNot(contains('esta la pone el gancho')));
    expect(reglas.join(), isNot(contains('no encontró')));
  });

  test('una regla declarada que no existe se dice, no se calla', () async {
    // **Es el caso que mas importa.** Un archivo que se movio o un nombre mal escrito
    // sin aviso produce trabajo que ignora una regla, y el sintoma no apunta a ningun
    // sitio: nadie sospecha de un archivo que creia cargado.
    escribir('.nexus-reglas', 'reglas/que-no-esta.md\n');

    final reglas = await reglasDe();
    expect(reglas, hasLength(1));
    expect(reglas.single, contains('no encontró'));
    expect(reglas.single, contains('reglas/que-no-esta.md'));
  });

  test('una ruta absoluta vale, porque las reglas suelen vivir fuera', () async {
    // El caso que motivo esto: las reglas viven en un repo **hermano** de contexto.
    // Exigirlas dentro del proyecto seria no servir para el unico caso real que hay.
    final fuera = Directory.systemTemp.createTempSync('fuera');
    addTearDown(() => fuera.deleteSync(recursive: true));
    File('${fuera.path}/capa.md').writeAsStringSync('la de la capa');
    escribir('.nexus-reglas', '${fuera.path}/capa.md\n');

    expect(await reglasDe(), ['la de la capa']);
  });

  test('un archivo declarado pero vacio no ocupa sitio', () async {
    // El presupuesto por encargo es de 20.000 caracteres y viaja en **cada** uno:
    // meter una seccion vacia gasta formato sin decir nada.
    escribir('reglas/vacia.md', '   \n\n');
    escribir('.nexus-reglas', 'reglas/vacia.md\n');

    expect(await reglasDe(), isEmpty);
  });
}
