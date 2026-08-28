/// Las estadísticas de uso.
///
/// Lo que gasta cada cuenta de Claude, y cómo se dice.
///
/// Los tres van juntos —lo que se declara y sus dos traducciones— porque lo
/// que se rompe es la terna: añadir un texto y olvidar un idioma. Tenerlos en
/// el mismo archivo hace que el hueco se vea al escribirlo, no al compilar.
mixin EstadisticasStrings {
  // Estadísticas de uso, por cuenta.
  String get sectionStats;
  String get statsOverview;
  String get statsModels;
  String get statsRangeAll;
  String get statsRange30;
  String get statsRange7;
  String get statsSessions;
  String get statsMessages;
  String get statsTotalTokens;
  String get statsActiveDays;
  String get statsCurrentStreak;
  String get statsLongestStreak;
  String get statsPeakHour;
  String get statsFavoriteModel;
  String get statsReading;
  String get statsUnreadable;
  String get statsNothingYet;
  String get statsNoAccounts;
  String statsCachedFootnote(String amount);
  String statsDayTooltip(String day, int messages);
  String statsInOut(String input, String output);
}

mixin EstadisticasStringsEs implements EstadisticasStrings {
  @override
  String get sectionStats => 'Estadísticas';
  @override
  String get statsOverview => 'Resumen';
  @override
  String get statsModels => 'Modelos';
  @override
  String get statsRangeAll => 'Todo';
  @override
  String get statsRange30 => '30d';
  @override
  String get statsRange7 => '7d';
  @override
  String get statsSessions => 'Sesiones';
  @override
  String get statsMessages => 'Mensajes';
  @override
  String get statsTotalTokens => 'Tokens';
  @override
  String get statsActiveDays => 'Días activos';
  @override
  String get statsCurrentStreak => 'Racha actual';
  @override
  String get statsLongestStreak => 'Racha más larga';
  @override
  String get statsPeakHour => 'Hora punta';
  @override
  String get statsFavoriteModel => 'Modelo favorito';
  @override
  String get statsReading => 'Leyendo los transcritos…';
  @override
  String get statsUnreadable =>
      'No se pudieron leer los transcritos de esta cuenta.';
  @override
  String get statsNothingYet => 'Todavía no hay nada que contar en este tramo.';
  @override
  String get statsNoAccounts => 'No hay ninguna cuenta de Claude configurada.';
  @override
  String statsCachedFootnote(String amount) =>
      'Además, $amount de tokens leídos o escritos en caché — fuera del total '
      'porque lo eclipsaría.';
  @override
  String statsDayTooltip(String day, int messages) =>
      '$day · $messages mensajes';
  @override
  String statsInOut(String input, String output) =>
      '$input entrada · $output salida';
}

mixin EstadisticasStringsEn implements EstadisticasStrings {
  @override
  String get sectionStats => 'Statistics';
  @override
  String get statsOverview => 'Overview';
  @override
  String get statsModels => 'Models';
  @override
  String get statsRangeAll => 'All';
  @override
  String get statsRange30 => '30d';
  @override
  String get statsRange7 => '7d';
  @override
  String get statsSessions => 'Sessions';
  @override
  String get statsMessages => 'Messages';
  @override
  String get statsTotalTokens => 'Tokens';
  @override
  String get statsActiveDays => 'Active days';
  @override
  String get statsCurrentStreak => 'Current streak';
  @override
  String get statsLongestStreak => 'Longest streak';
  @override
  String get statsPeakHour => 'Peak hour';
  @override
  String get statsFavoriteModel => 'Favorite model';
  @override
  String get statsReading => 'Reading the transcripts…';
  @override
  String get statsUnreadable =>
      'This account\'s transcripts could not be read.';
  @override
  String get statsNothingYet => 'Nothing to count in this range yet.';
  @override
  String get statsNoAccounts => 'No Claude account is set up.';
  @override
  String statsCachedFootnote(String amount) =>
      'Plus $amount tokens read from or written to cache — kept out of the '
      'total because it would dwarf it.';
  @override
  String statsDayTooltip(String day, int messages) =>
      '$day · $messages messages';
  @override
  String statsInOut(String input, String output) => '$input in · $output out';
}
