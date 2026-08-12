import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';

class SaveGeminiKey extends UseCase<void, String> {
  const SaveGeminiKey(this._keyStore);

  final GeminiKeyStore _keyStore;

  @override
  Future<void> call(String params) => _keyStore.save(params.trim());
}
