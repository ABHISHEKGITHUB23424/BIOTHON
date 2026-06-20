import 'file_picker_helper_stub.dart'
    if (dart.library.html) 'file_picker_helper_web.dart' as impl;

abstract class FilePickerHelper {
  static Future<PickedFile?> pickFile() {
    return impl.pickFile();
  }
}

class PickedFile {
  final String name;
  final String base64Content;
  PickedFile(this.name, this.base64Content);
}
