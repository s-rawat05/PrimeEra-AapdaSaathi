import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Minimal persistent string key/value box. Hive in the app, in-memory in tests.
abstract class LocalBox {
  String? get(String key);
  Future<void> put(String key, String value);
  Future<void> delete(String key);
  Iterable<String> get keys;
}

class MemoryBox implements LocalBox {
  final Map<String, String> _data = {};

  @override
  String? get(String key) => _data[key];

  @override
  Future<void> put(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Iterable<String> get keys => List.of(_data.keys);
}

class HiveBox implements LocalBox {
  HiveBox._(this._box);

  final Box<String> _box;

  static bool _initialised = false;

  static Future<HiveBox> open(String name) async {
    if (!_initialised) {
      await Hive.initFlutter('aapda_saathi');
      _initialised = true;
    }
    return HiveBox._(await Hive.openBox<String>(name));
  }

  @override
  String? get(String key) => _box.get(key);

  @override
  Future<void> put(String key, String value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Iterable<String> get keys => _box.keys.map((k) => k.toString()).toList();
}
