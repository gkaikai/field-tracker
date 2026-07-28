// Integration test driver for running on emulator
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:field_tracker/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
