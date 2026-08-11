import 'package:nexus/features/counter/domain/entities/counter.dart';

abstract class CounterRepository {
  Future<Counter> getCounter();
  Future<Counter> increment();
}
