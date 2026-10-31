import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool saveTextFile(String filename, String content, {String mimeType = 'text/csv'}) {
  final blob = web.Blob(<JSAny>[content.toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
