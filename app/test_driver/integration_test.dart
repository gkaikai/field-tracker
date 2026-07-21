/// Integration test driver for running on emulator
import 'package:flutter_driver/driver_extension.dart';
import 'package:field_tracker/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
