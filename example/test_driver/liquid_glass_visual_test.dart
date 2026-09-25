import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final FlutterDriver driver = await FlutterDriver.connect();
  await integrationDriver(
    driver: driver,
    onScreenshot:
        (
          String screenshotName,
          List<int> screenshotBytes, [
          Map<String, Object?>? args,
        ]) async {
          final Directory output = Directory('build');
          await output.create(recursive: true);
          await File(
            '${output.path}${Platform.pathSeparator}$screenshotName.png',
          ).writeAsBytes(screenshotBytes, flush: true);
          return true;
        },
  );
}
