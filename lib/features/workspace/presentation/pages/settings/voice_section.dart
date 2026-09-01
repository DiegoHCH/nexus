import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/agenda/data/datasources/gemini_tts_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/el_acento.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/presentation/providers/audio_output_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/microphone_tester.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/salidas_section.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// La sección de Voz de Ajustes.
///
/// Vive en su propio archivo desde que `settings_page.dart` pasó de las 1.400
/// líneas: cada sección es independiente —solo la usa el `switch` de la pantalla—
/// así que tenerlas juntas solo hacía que buscar una costara desplazarse por las
/// otras siete.

/// La voz con la que responde. Existe porque sin fijarla el servicio elegía
/// una distinta en cada sesión.
class VoiceSection extends ConsumerWidget {
  const VoiceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final selected = ref.watch(voicePreferenceProvider);
    final controller = ref.read(voicePreferenceProvider.notifier);

    // 🔴 **Desplaza, como las demás secciones largas.**
    //
    // Terminaba en `Expanded(child: MicrophoneTester())`, que absorbía la
    // holgura y hacía la sección de alto fijo: en cuanto se le añadió el acento
    // desbordó por 20 px y lo cazó la prueba que abre todas las secciones. El
    // probador tiene alto propio —48 px de onda y una fila— así que el
    // `Expanded` no le hacía falta, solo impedía que esto creciera.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.nexusVoice,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          Text(
            context.strings.voiceExplainer,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s5),
          // 🔴 **El botón va al lado del selector, no dentro de cada opción.**
          //
          // Lo natural sería una fila por voz con su propio «escuchar», pero esto
          // es un `DropdownButton`: tocar cualquier cosa de una opción la
          // selecciona y cierra el desplegable, así que un botón ahí dentro no
          // llega a poder pulsarse. Y elegir aquí es reversible y no cuesta nada
          // —es una preferencia, no una acción— así que auditar es «la elijo y la
          // escucho», que con treinta voces funciona igual de bien.
          Row(
            children: [
              Expanded(
                child: SettingsChooser<NexusVoice>(
                  value: NexusVoice.all.firstWhere(
                    (voice) => voice.name == selected.name,
                    orElse: () => NexusVoice.all.first,
                  ),
                  options: NexusVoice.all,
                  label: (voice) => voice.name,
                  detail: (voice) => voice.character,
                  onSelected: controller.select,
                ),
              ),
              const SizedBox(width: NexusSpacing.s3),
              const _BotonDeEscucha(),
            ],
          ),
          const SizedBox(height: NexusSpacing.s6),
          Text(
            context.strings.elAcento,
            style: NexusTypography.label.copyWith(color: colors.mute),
          ),
          const SizedBox(height: NexusSpacing.s2),
          Text(
            context.strings.elAcentoExplainer,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s3),
          SettingsChooser<ElAcento>(
            value: ref.watch(elAcentoProvider),
            options: ElAcento.opciones,
            label: (acento) =>
                acento.variante ?? context.strings.elAcentoAutomatico,
            onSelected: ref.read(elAcentoProvider.notifier).select,
          ),
          const SizedBox(height: NexusSpacing.s6),
          // La llave. Aquí y no solo en el primer arranque, porque hasta ahora la
          // pantalla de configuración prometía «puedes cambiar esto después en
          // Ajustes» y **no había dónde**: una llave mal escrita solo se arreglaba
          // tocando el llavero a mano. Y desde que la llave dejó de ser
          // obligatoria para entrar, este es el sitio donde se enciende la voz.
          const _GeminiKeyRow(),
          const SizedBox(height: NexusSpacing.s6),
          const _AudioOutputPicker(),
          const SizedBox(height: NexusSpacing.s6),
          // El micrófono se prueba aquí y no solo en el primer arranque: es donde
          // se viene cuando algo no se oye, y hasta ahora esta sección solo
          // dejaba cambiar la voz con la que Nexus habla, no comprobar la que
          // escucha.
          const MicrophoneTester(),
        ],
      ),
    );
  }
}

/// La llave del servicio de voz: si hay una guardada, y cómo cambiarla.
///
/// **No se enseña la llave guardada**, ni recortada. Enseñarla no sirve para
/// nada —no se compara a ojo— y la deja en pantalla a la vista de cualquiera que
/// pase por detrás, en la única pantalla que alguien abre cuando está enseñando
/// la app. Lo único que hace falta saber es si hay una, y eso cabe en una
/// palabra.
class _GeminiKeyRow extends ConsumerStatefulWidget {
  const _GeminiKeyRow();

  @override
  ConsumerState<_GeminiKeyRow> createState() => _GeminiKeyRowState();
}

class _GeminiKeyRowState extends ConsumerState<_GeminiKeyRow> {
  final _controller = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final llave = _controller.text.trim();
    if (llave.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    await ref.read(saveGeminiKeyProvider)(llave);
    if (!mounted) return;
    _controller.clear();
    setState(() => _guardando = false);
    // Para que la pantalla de salidas y la sesión de voz vean la nueva sin
    // reiniciar: las dos leen del llavero por su cuenta.
    ref.invalidate(geminiKeyStoreProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final hay = ref.watch(hayLlaveDeGeminiProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.geminiKey,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          hay ? strings.geminiKeySaved : strings.geminiKeyMissing,
          style: NexusTypography.mono.copyWith(
            color: hay ? colors.ok : colors.warn,
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: true,
                onSubmitted: (_) => _guardar(),
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(hintText: strings.geminiKeyHint),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(strings.geminiKeySave),
            ),
          ],
        ),
      ],
    );
  }
}

/// Por dónde sale la voz de Nexus, cuando hay más de un aparato conectado.
class _AudioOutputPicker extends ConsumerWidget {
  const _AudioOutputPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final devices = ref.watch(audioOutputDevicesProvider).value ?? const [];
    // Con un solo aparato no hay nada que elegir; el desplegable sobra.
    if (devices.length < 2) return const SizedBox.shrink();

    final selected = ref.watch(audioOutputControllerProvider);
    final options = <int?>[null, ...devices.map((device) => device.id)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.audioOutput,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        SettingsChooser<int?>(
          value: options.contains(selected) ? selected : null,
          options: options,
          label: (id) {
            if (id == null) return strings.audioOutputSystem;
            return devices.firstWhere((device) => device.id == id).name;
          },
          // El que usa el sistema se marca, para que elegir «el del sistema» no
          // sea elegir a ciegas.
          detail: (id) => id == null
              ? (devices
                        .where((device) => device.isDefault)
                        .firstOrNull
                        ?.name ??
                    '')
              : '',
          onSelected: ref.read(audioOutputControllerProvider.notifier).select,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.audioOutputExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

/// Escuchar la voz elegida **antes de dejarla puesta**.
///
/// No había forma de oírla sin abrir una sesión de voz entera y hablarle, que
/// para comparar treinta voces es inviable: había que elegir a ciegas por el
/// nombre y la coletilla.
///
/// Usa el TTS de los avisos, no la sesión en vivo, y por dos motivos que
/// empujan igual: una frase de dos segundos no necesita negociar un socket, y
/// el modelo de TTS es el barato. La contrapartida honesta es que el timbre del
/// TTS y el de la voz en vivo **no son idénticos** —son modelos distintos con el
/// mismo catálogo de voces—, así que esto sirve para comparar unas con otras,
/// que es para lo que se pide, y no como muestra exacta de la sesión.
class _BotonDeEscucha extends ConsumerStatefulWidget {
  const _BotonDeEscucha();

  @override
  ConsumerState<_BotonDeEscucha> createState() => _BotonDeEscuchaState();
}

class _BotonDeEscuchaState extends ConsumerState<_BotonDeEscucha> {
  bool _pidiendo = false;
  bool _sonando = false;
  String? _fallo;

  /// Lo ya sintetizado, por voz y acento.
  ///
  /// 🔴 **Porque comparar voces es ir y volver.** La síntesis es un viaje a
  /// Google y tarda unos cuatro segundos —medido en el registro de los avisos:
  /// «el TTS tardó 4256 ms»—, así que con treinta voces y sin esto cada
  /// segunda escucha vuelve a pagar la espera entera. Se reportó como «al
  /// darle play se demora en reproducir».
  ///
  /// Estático a propósito: sobrevive a cerrar y abrir Ajustes, que es
  /// exactamente cuando se vuelve a la voz que ya gustaba. No sobrevive a
  /// cerrar la app, y no hace falta que lo haga.
  static final _yaSintetizado = <String, Uint8List>{};

  /// El tope. Dos segundos de PCM a 24 kHz y 16 bits son unos 96 KB, así que
  /// treinta voces son ~3 MB: se guarda con holgura, pero con tope, porque las
  /// combinaciones de voz y acento se multiplican y esto no es una caché de
  /// verdad, es un recuerdo corto.
  static const _tope = 40;

  Future<void> _probar() async {
    if (_pidiendo || _sonando) return;
    setState(() {
      _fallo = null;
    });

    // El altavoz se pide **antes** de sintetizar. Al revés, la frase llegaba
    // hecha y se perdía el principio mientras el motor arrancaba: es el mismo
    // fallo que se corrigió en los avisos de agenda.
    final altavoz = ref.read(audioOutputProvider);
    // Y los textos se leen antes del primer `await`: después, el `context`
    // puede ser de una pantalla que ya no está.
    final strings = context.strings;
    final acento = ref.read(elAcentoProvider);
    final frase = acento.conElIdioma(
      strings.fraseDePrueba(ref.read(losNombresProvider).vocativo),
    );
    final voz = ref.read(voicePreferenceProvider).name;
    final clave = '$voz · ${acento.variante ?? ''} · $frase';

    // Ya oída: suena sin viajar a ningún sitio.
    if (_yaSintetizado[clave] case final pcm?) {
      await _sonar(altavoz, pcm);
      return;
    }

    setState(() => _pidiendo = true);
    try {
      // El llavero también se acota. Sin esto, la espera total era la lectura
      // del llavero **más** los 45 s de la síntesis, y el mensaje de fallo
      // decía «45s»: se reportó contando más que eso, y con razón. Cinco
      // segundos son de sobra para leer una clave ya desbloqueada.
      final llave = await ref
          .read(geminiKeyStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
      if (llave == null || llave.isEmpty) {
        // Sin llave no hay voz, y decirlo aquí ahorra el viaje: la fila de la
        // llave está en esta misma pantalla, justo debajo.
        if (mounted) setState(() => _fallo = strings.geminiKeyMissing);
        return;
      }
      final dicho = await const GeminiTtsDataSource().decir(
        llave: llave,
        // El acento entra también aquí: probar una voz con el acento puesto es
        // lo único que responde a la pregunta que se está haciendo.
        frase: frase,
        voz: voz,
        // 🔴 **Menos que el aviso de agenda, a propósito.**
        //
        // Los 45 s de allí están calibrados para algo que nadie mira: una
        // frase que llega tarde sigue siendo un aviso. Aquí hay una persona
        // delante mirando un giro, y para ella 45 s no son «paciencia», son
        // «esto no funciona». Lo normal medido son 3,9 s, así que quince dan
        // margen de sobra y fallan pronto cuando el servicio está en problemas
        // —que hoy lo está: cuatro caídas por tope ayer y un bloqueo por
        // política esta tarde.
        timeout: const Duration(seconds: 15),
      );
      // 🔴 **`decir` no lanza: devuelve el problema.** Así es como llegó el
      // «Request blocked for an unspecified policy reason» que bloqueó un aviso
      // de agenda esta tarde. Mirar solo el `catch` habría dejado el botón
      // haciendo nada en silencio en el caso más probable de todos.
      if (!dicho.salio) {
        if (mounted) setState(() => _fallo = dicho.problema);
        return;
      }
      if (_yaSintetizado.length >= _tope) {
        _yaSintetizado.remove(_yaSintetizado.keys.first);
      }
      _yaSintetizado[clave] = dicho.pcm!;
      await _sonar(altavoz, dicho.pcm!);
    } catch (error) {
      // Se dice, no se traga. Un botón que no hace nada y no explica por qué es
      // peor que no tener botón: no distingues «no hay llave» de «no hay red».
      if (mounted) setState(() => _fallo = '$error');
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
  }

  /// Suena, y el botón lo dice mientras dura.
  ///
  /// El alto se pregunta al altavoz en vez de cronometrarlo aquí: es él quien
  /// sabe cuánto PCM le queda por delante, y estimarlo por el tamaño del
  /// búfer sería adivinar la frecuencia por segunda vez.
  Future<void> _sonar(AudioOutput altavoz, Uint8List pcm) async {
    await altavoz.start();
    altavoz.enqueue(pcm);
    if (!mounted) return;
    setState(() => _sonando = true);
    await Future<void>.delayed(await altavoz.pending());
    if (mounted) setState(() => _sonando = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fallo = _fallo;
    return Tooltip(
      message:
          fallo ??
          (_sonando
              ? context.strings.escuchandoLaVoz
              : context.strings.escucharLaVoz),
      child: _Marco(
        onTap: _pidiendo || _sonando ? null : _probar,
        pidiendo: _pidiendo,
        child: Icon(
          switch ((fallo, _sonando)) {
            (final String _, _) => Icons.error_outline,
            (_, true) => Icons.graphic_eq,
            _ => Icons.play_arrow,
          },
          size: 18,
          color: switch ((fallo, _sonando)) {
            (final String _, _) => colors.warn,
            (_, true) => colors.accent,
            _ => colors.ink,
          },
        ),
      ),
    );
  }
}

/// El marco del botón de escucha: **el mismo que el del selector de al lado**.
///
/// 🔴 **Sin esto no se veía.** Iba como un `IconButton` pelado, 16 px en
/// `colors.faint` —el color de los textos de apoyo, el más apagado de la
/// paleta— sin borde ni fondo, pegado a un selector que sí tiene marco y
/// relleno. Se reportó como «sigo sin ver lo que pusiste»: estaba pintado y no
/// parecía un botón, que en una interfaz es lo mismo que no estar.
///
/// Repite la decoración de `SettingsChooser` a propósito, para que la fila se
/// lea como un control con dos partes y no como un control y una mota.
class _Marco extends StatelessWidget {
  const _Marco({required this.child, this.onTap, this.pidiendo = false});

  final Widget child;
  final VoidCallback? onTap;

  /// Se está esperando a que Google devuelva el audio.
  ///
  /// Va aparte del icono porque no es un estado del icono, es un estado del
  /// botón: **cuatro segundos sin señal de vida se leen como que no funciona**,
  /// y era el reporte literal. El giro no acorta la espera, la explica.
  final bool pidiendo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexusRadius.sm),
        child: Container(
          // El alto lo pone el selector, que se dimensiona por su contenido:
          // 44 px es lo que mide con la tipografía de datos y su relleno. Un
          // botón más bajo dejaba la fila escalonada.
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: colors.void_.withValues(alpha: 0.5),
            border: Border.all(color: colors.rule),
            borderRadius: BorderRadius.circular(NexusRadius.sm),
          ),
          child: Center(
            child: pidiendo
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: colors.accent,
                    ),
                  )
                : child,
          ),
        ),
      ),
    );
  }
}
