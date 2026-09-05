import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_update.dart';

class AppUpdateService {
  AppUpdateService({HttpClient? httpClient}) : _httpClient = httpClient ?? HttpClient();

  static final Uri _releasesApi = Uri.https('api.github.com', '/repos/llins95/MeuKM/releases/latest');
  static const MethodChannel _androidChannel = MethodChannel('br.com.meukm/app_updates');
  static const int _maxMetadataBytes = 1024 * 1024;
  static const int _maxApkBytes = 250 * 1024 * 1024;
  static const int _maxWindowsPackageBytes = 500 * 1024 * 1024;

  final HttpClient _httpClient;

  Future<bool> isSupported() async => Platform.isAndroid || Platform.isWindows;

  Future<InstalledAppVersion> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber) ?? 0;
    return InstalledAppVersion(name: info.version, code: code);
  }

  Future<AppUpdateInfo?> fetchLatestRelease() async {
    final response = await _get(_releasesApi, acceptJson: true);
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('O GitHub respondeu com HTTP ${response.statusCode}.', uri: _releasesApi);
    }
    final text = await _readText(response, maxBytes: _maxMetadataBytes);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Resposta de atualização inválida.');
    return AppUpdateInfo.fromGitHubRelease(decoded);
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    return await _androidChannel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
  }

  Future<void> openInstallPermissionSettings() async {
    if (Platform.isAndroid) await _androidChannel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<void> downloadAndInstall(AppUpdateInfo update) async {
    if (Platform.isWindows) {
      await _downloadAndApplyWindows(update);
      return;
    }
    if (!Platform.isAndroid) throw UnsupportedError('Atualização automática não suportada nesta plataforma.');

    if (!await canRequestPackageInstalls()) {
      await openInstallPermissionSettings();
      throw const FileSystemException('Autorize o MeuKM a instalar atualizações e tente novamente.');
    }

    final expectedChecksum = await _fetchChecksum(update.apkChecksumUri);
    final temporaryDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory('${temporaryDirectory.path}${Platform.pathSeparator}updates');
    await updateDirectory.create(recursive: true);
    final apk = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-${update.versionCode}.apk');

    if (!await _matchesChecksum(apk, expectedChecksum)) {
      await _downloadPackage(update.apkUri, apk, maxBytes: _maxApkBytes, description: 'APK');
      if (!await _matchesChecksum(apk, expectedChecksum)) {
        if (await apk.exists()) await apk.delete();
        throw const FormatException('O APK baixado não passou na validação SHA-256.');
      }
    }

    final opened = await _androidChannel.invokeMethod<bool>('installApk', {'path': apk.path});
    if (opened != true) throw StateError('O instalador do Android não pôde ser aberto.');
  }

  Future<void> _downloadAndApplyWindows(AppUpdateInfo update) async {
    final packageUri = update.windowsPackageUri;
    final checksumUri = update.windowsChecksumUri;
    if (packageUri == null || checksumUri == null) {
      throw const FormatException('A release não contém o pacote de atualização do Windows.');
    }

    final expectedChecksum = await _fetchChecksum(checksumUri);
    final temporaryDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory('${temporaryDirectory.path}${Platform.pathSeparator}updates');
    await updateDirectory.create(recursive: true);
    final archive = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Windows-${update.versionCode}.zip');
    if (!await _matchesChecksum(archive, expectedChecksum)) {
      await _downloadPackage(packageUri, archive, maxBytes: _maxWindowsPackageBytes, description: 'pacote do Windows');
      if (!await _matchesChecksum(archive, expectedChecksum)) {
        if (await archive.exists()) await archive.delete();
        throw const FormatException('O pacote do Windows não passou na validação SHA-256.');
      }
    }

    final executable = File(Platform.resolvedExecutable);
    final installDirectory = executable.parent;
    await _verifyInstallDirectoryIsWritable(installDirectory);

    final script = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Updater-${update.versionCode}.ps1');
    final log = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Updater-${update.versionCode}.log');
    final ready = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Updater-${update.versionCode}.ready');
    final result = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Updater-${update.versionCode}.result');
    final cancel = File('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Updater-${update.versionCode}.cancel');
    final backup = Directory('${updateDirectory.path}${Platform.pathSeparator}MeuKM-Backup-${update.versionCode}');

    for (final marker in [ready, result, cancel, log]) {
      if (await marker.exists()) await marker.delete();
    }
    if (await backup.exists()) await backup.delete(recursive: true);

    final scriptContents = await rootBundle.loadString('assets/windows/meukm_updater.ps1');
    await script.writeAsString('\uFEFF$scriptContents', flush: true);

    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final powerShell = '$systemRoot${Platform.pathSeparator}System32${Platform.pathSeparator}WindowsPowerShell${Platform.pathSeparator}v1.0${Platform.pathSeparator}powershell.exe';

    final process = await Process.start(
      powerShell,
      [
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script.path,
        '-HostProcessId', pid.toString(),
        '-ArchivePath', archive.path,
        '-InstallDirectory', installDirectory.path,
        '-ExecutablePath', executable.path,
        '-ReadyPath', ready.path,
        '-ResultPath', result.path,
        '-CancelPath', cancel.path,
        '-BackupPath', backup.path,
        '-LogPath', log.path,
        '-ScriptPath', script.path,
      ],
      workingDirectory: installDirectory.path,
      mode: ProcessStartMode.normal,
    );

    final exitFuture = process.exitCode;
    await waitForWindowsUpdaterReady(ready: ready, result: result, cancel: cancel, log: log, updaterExitCode: exitFuture);
    Timer(const Duration(milliseconds: 500), () => exit(0));
  }

  @visibleForTesting
  static Future<void> waitForWindowsUpdaterReady({
    required File ready,
    required File result,
    required File cancel,
    required File log,
    Future<int>? updaterExitCode,
    Duration timeout = const Duration(seconds: 90),
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    int? observedExitCode;
    unawaited(updaterExitCode?.then<void>((value) => observedExitCode = value));
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await ready.exists()) return;
      if (await result.exists()) {
        final outcome = await result.readAsString();
        if (outcome.trimLeft().startsWith('failure')) {
          throw Exception('O atualizador não conseguiu preparar a instalação. O MeuKM continuará aberto. Registro: ${log.path}');
        }
      }
      if (observedExitCode != null) {
        throw Exception('O atualizador encerrou antes de iniciar (código $observedExitCode). O MeuKM continuará aberto. Registro: ${log.path}');
      }
      await Future<void>.delayed(pollInterval);
    }
    await cancel.writeAsString('cancel', flush: true);
    throw TimeoutException('O atualizador não respondeu dentro do tempo esperado. O MeuKM continuará aberto. Registro: ${log.path}');
  }

  Future<void> _verifyInstallDirectoryIsWritable(Directory directory) async {
    final probe = File('${directory.path}${Platform.pathSeparator}.meukm-update-write-test');
    try {
      await probe.writeAsString('MeuKM');
    } on FileSystemException {
      throw const FileSystemException('O MeuKM não tem permissão para atualizar esta pasta. Mova o aplicativo para uma pasta do seu usuário e tente novamente.');
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  Future<String> _fetchChecksum(Uri uri) async {
    final response = await _get(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('Não foi possível obter o checksum da atualização.', uri: uri);
    }
    final text = await _readText(response, maxBytes: 4096);
    final match = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(text);
    if (match == null) throw const FormatException('Checksum da atualização inválido.');
    return match.group(0)!.toLowerCase();
  }

  Future<void> _downloadPackage(Uri uri, File destination, {required int maxBytes, required String description}) async {
    final partial = File('${destination.path}.part');
    if (await partial.exists()) await partial.delete();
    final response = await _get(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('Não foi possível baixar o $description da atualização.', uri: uri);
    }
    IOSink? sink;
    try {
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (received > maxBytes) throw FileSystemException('O $description excede o tamanho máximo permitido.');
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
    } catch (_) {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<bool> _matchesChecksum(File file, String expected) async {
    if (!await file.exists()) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected;
  }

  Future<HttpClientResponse> _get(Uri uri, {bool acceptJson = false}) async {
    final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'MeuKM-App-Updater');
    if (acceptJson) {
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    }
    return request.close().timeout(const Duration(seconds: 30));
  }

  Future<String> _readText(HttpClientResponse response, {required int maxBytes}) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxBytes) throw const FormatException('Resposta de atualização muito grande.');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}
