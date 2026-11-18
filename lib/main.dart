// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'app.dart';
import 'state/ragaa_controller.dart';

export 'app.dart';
export 'core/date_ranges.dart';
export 'core/formatters.dart';
export 'state/ragaa_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await RagaaController.createDefault();
  runApp(RagaaApp(controller: controller));
}
