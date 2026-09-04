import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'services/app_controller.dart';

const supabaseUrl = 'https://nnntmfdfkafigabwsjzz.supabase.co';
const supabasePublishableKey = 'sb_publishable_g8lo_wxILrAawLX_Bxaauw_82Db9zKe';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  final controller = AppController(Supabase.instance.client);
  await controller.initialize();
  runApp(MeuKmApp(controller: controller));
}
