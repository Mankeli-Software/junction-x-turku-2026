import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands [text] to the browser as a download named [name].
void saveTextFile(String name, String text, String mimeType) {
  final blob = web.Blob(<JSAny>[text.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}
