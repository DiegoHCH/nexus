import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';

final claudeCliDataSourceProvider = Provider<ClaudeCliDataSource>(
  (ref) => const ClaudeCliDataSource(),
);

final claudeBridgeProvider = Provider<ClaudeBridge>(
  (ref) => ClaudeBridgeImpl(ref.watch(claudeCliDataSourceProvider)),
);

final askClaudeProvider = Provider<AskClaude>(
  (ref) => AskClaude(ref.watch(claudeBridgeProvider)),
);
