class InstalledAppVersion {
  const InstalledAppVersion({required this.name, required this.code});
  final String name;
  final int code;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUri,
    required this.apkChecksumUri,
    required this.windowsPackageUri,
    required this.windowsChecksumUri,
    required this.releaseNotes,
  });

  final String versionName;
  final int versionCode;
  final Uri apkUri;
  final Uri apkChecksumUri;
  final Uri? windowsPackageUri;
  final Uri? windowsChecksumUri;
  final String releaseNotes;

  bool isNewerThan(InstalledAppVersion installed) => versionCode > installed.code;

  factory AppUpdateInfo.fromGitHubRelease(Map<String, dynamic> release) {
    final tag = release['tag_name'];
    final assets = release['assets'];
    if (tag is! String || assets is! List) {
      throw const FormatException('Release do MeuKM inválida.');
    }
    final match = RegExp(r'^v(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(tag.trim());
    if (match == null) throw const FormatException('Tag de versão do MeuKM inválida.');

    Uri? asset(String name) {
      for (final item in assets) {
        if (item is Map && item['name'] == name && item['browser_download_url'] is String) {
          final uri = Uri.tryParse(item['browser_download_url'] as String);
          if (uri != null && uri.scheme == 'https') return uri;
        }
      }
      return null;
    }

    final apk = asset('MeuKM.apk');
    final apkSha = asset('MeuKM.apk.sha256');
    if (apk == null || apkSha == null) {
      throw const FormatException('A release não contém o APK e o checksum esperados.');
    }
    return AppUpdateInfo(
      versionName: match.group(1)!,
      versionCode: int.parse(match.group(2)!),
      apkUri: apk,
      apkChecksumUri: apkSha,
      windowsPackageUri: asset('MeuKM-Windows-x64.zip'),
      windowsChecksumUri: asset('MeuKM-Windows-x64.zip.sha256'),
      releaseNotes: (release['body'] as String?)?.trim() ?? '',
    );
  }
}
