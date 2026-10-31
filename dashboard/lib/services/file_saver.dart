import 'file_saver_stub.dart' if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Saves text as a downloaded file (Blob + anchor on web). Returns false when unsupported.
bool saveTextFile(String filename, String content, {String mimeType = 'text/csv'}) =>
    impl.saveTextFile(filename, content, mimeType: mimeType);
