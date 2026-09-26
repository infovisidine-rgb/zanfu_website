import 'disk_cache_stub.dart' as impl;

/// Text/binary cache via SharedPreferences on web.
class DiskCache {
  DiskCache._();

  static bool get isFileSystemAvailable => impl.isFileSystemAvailable;

  static Future<String?> readText(String filename) => impl.readText(filename);

  static Future<void> writeText(String filename, String contents) =>
      impl.writeText(filename, contents);

  static Future<bool> exists(String filename) => impl.exists(filename);

  static Future<List<int>?> readBytes(String filename) =>
      impl.readBytes(filename);

  static Future<void> writeBytes(String filename, List<int> bytes) =>
      impl.writeBytes(filename, bytes);

  static Future<String?> documentsPath() => impl.documentsPath();

  static Future<String?> absolutePath(String filename) =>
      impl.absolutePath(filename);

  static bool absolutePathExists(String path) => impl.absolutePathExists(path);
}
