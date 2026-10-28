import 'package:flutter/material.dart';
import 'app/controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = AppController(
      await AppController.loadCatalog(),
      LocalStorage(),
    );
    await controller.load();
    runApp(LexiStackApp(controller: controller));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'LexiStack could not load its bundled puzzles. Please reinstall the app.\n\n$e',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
