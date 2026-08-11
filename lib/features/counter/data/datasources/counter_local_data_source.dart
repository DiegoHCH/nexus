abstract class CounterLocalDataSource {
  Future<int> getCounter();
  Future<int> increment();
}

class CounterLocalDataSourceImpl implements CounterLocalDataSource {
  int _value = 0;

  @override
  Future<int> getCounter() async => _value;

  @override
  Future<int> increment() async => ++_value;
}
