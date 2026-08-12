/// Si ya se resolvió la configuración inicial (2.6): con la llave de Gemini
/// guardada, el arranque va directo a Reposo. El permiso de micrófono no
/// forma parte de esta decisión — se pide desde la propia pantalla de
/// configuración y no bloquea arranques siguientes si el usuario lo niega.
class OnboardingStatus {
  const OnboardingStatus({required this.hasGeminiKey});

  final bool hasGeminiKey;
}
