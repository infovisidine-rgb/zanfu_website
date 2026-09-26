import 'package:shared_preferences/shared_preferences.dart';

const bool isFileSystemAvailable = false;

const _prefix = 'disk_cache_';

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

Future<String?> readText(String filename) async {
  return (await _prefs()).getString('$_prefix$filename');
}

Future<void> writeText(String filename, String contents) async {
  await (await _prefs()).setString('$_prefix$filename', contents);
}

Future<bool> exists(String filename) async {
  return (await _prefs()).containsKey('$_prefix$filename');
}

Future<List<int>?> readBytes(String filename) async => null;

Future<void> writeBytes(String filename, List<int> bytes) async {}

Future<String?> documentsPath() async => null;

Future<String?> absolutePath(String filename) async => null;

bool absolutePathExists(String path) => false;
