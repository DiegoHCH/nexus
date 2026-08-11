import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/counter/data/datasources/counter_local_data_source.dart';
import 'package:nexus/features/counter/data/repositories/counter_repository_impl.dart';
import 'package:nexus/features/counter/domain/entities/counter.dart';
import 'package:nexus/features/counter/domain/repositories/counter_repository.dart';
import 'package:nexus/features/counter/domain/usecases/get_counter.dart';
import 'package:nexus/features/counter/domain/usecases/increment_counter.dart';

final counterLocalDataSourceProvider = Provider<CounterLocalDataSource>(
  (ref) => CounterLocalDataSourceImpl(),
);

final counterRepositoryProvider = Provider<CounterRepository>(
  (ref) => CounterRepositoryImpl(ref.watch(counterLocalDataSourceProvider)),
);

final getCounterProvider = Provider(
  (ref) => GetCounter(ref.watch(counterRepositoryProvider)),
);

final incrementCounterProvider = Provider(
  (ref) => IncrementCounter(ref.watch(counterRepositoryProvider)),
);

class CounterNotifier extends AsyncNotifier<Counter> {
  @override
  Future<Counter> build() =>
      ref.read(getCounterProvider).call(const NoParams());

  Future<void> increment() async {
    state = await AsyncValue.guard(
      () => ref.read(incrementCounterProvider).call(const NoParams()),
    );
  }
}

final counterNotifierProvider =
    AsyncNotifierProvider<CounterNotifier, Counter>(CounterNotifier.new);
