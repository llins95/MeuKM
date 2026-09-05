import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meukm/models/app_update.dart';
import 'package:meukm/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installed = InstalledAppVersion(name: '0.2.0', code: 2);

  test('interpreta a release do MeuKM com Android e Windows', () {
    final parsed = AppUpdateInfo.fromGitHubRelease({
      'tag_name': 'v0.3.0+3',
      'body': 'Novidades',
      'assets': [
        {
          'name': 'MeuKM.apk',
          'browser_download_url': 'https://github.com/demo/MeuKM.apk',
        },
        {
          'name': 'MeuKM.apk.sha256',
          'browser_download_url': 'https://github.com/demo/MeuKM.apk.sha256',
        },
        {
          'name': 'MeuKM-Windows-x64.zip',
          'browser_download_url': 'https://github.com/demo/MeuKM-Windows-x64.zip',
        },
        {
          'name': 'MeuKM-Windows-x64.zip.sha256',
          'browser_download_url': 'https://github.com/demo/MeuKM-Windows-x64.zip.sha256',
        },
      ],
    });

    expect(parsed.versionName, '0.3.0');
    expect(parsed.versionCode, 3);
    expect(parsed.releaseNotes, 'Novidades');
    expect(parsed.isNewerThan(installed), isTrue);
    expect(parsed.windowsPackageUri, isNotNull);
    expect(parsed.windowsChecksumUri, isNotNull);
  });

  test('rejeita release sem APK e checksum', () {
    expect(
      () => AppUpdateInfo.fromGitHubRelease({
        'tag_name': 'v0.3.0+3',
        'assets': const [],
      }),
      throwsFormatException,
    );
  });

  test('script sinaliza pronto antes de extrair e tem rollback', () async {
    final script = await rootBundle.loadString('assets/windows/meukm_updater.ps1');

    expect(script, contains(r'$ReadyPath'));
    expect(script, contains('Copia de seguranca'));
    expect(script, contains('Restauracao da versao anterior'));
    expect(script, contains("-Value 'success'"));
    expect(
      script.indexOf("Set-Content -LiteralPath \$ReadyPath -Value 'ready'"),
      lessThan(script.indexOf('Expand-Archive')),
    );
  });

  test('não fecha o app quando o atualizador informa falha', () async {
    final directory = await Directory.systemTemp.createTemp('meukm-updater-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final ready = File('${directory.path}/ready');
    final result = File('${directory.path}/result');
    final cancel = File('${directory.path}/cancel');
    final log = File('${directory.path}/updater.log');
    await result.writeAsString('failure\nFalha controlada.');

    await expectLater(
      AppUpdateService.waitForWindowsUpdaterReady(
        ready: ready,
        result: result,
        cancel: cancel,
        log: log,
        timeout: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 5),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await ready.exists(), isFalse);
    expect(await cancel.exists(), isFalse);
  });

  test('cancela preparação se o atualizador não responde', () async {
    final directory = await Directory.systemTemp.createTemp('meukm-updater-timeout-');
    addTearDown(() => directory.delete(recursive: true));
    final ready = File('${directory.path}/ready');
    final result = File('${directory.path}/result');
    final cancel = File('${directory.path}/cancel');
    final log = File('${directory.path}/updater.log');

    await expectLater(
      AppUpdateService.waitForWindowsUpdaterReady(
        ready: ready,
        result: result,
        cancel: cancel,
        log: log,
        timeout: const Duration(milliseconds: 25),
        pollInterval: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(await cancel.readAsString(), 'cancel');
  });
}
