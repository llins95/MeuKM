import 'package:flutter/material.dart';

import '../../services/app_controller.dart';
import '../../services/app_update_service.dart';

class AccountSettingsDialog extends StatelessWidget {
  const AccountSettingsDialog({required this.controller, required this.onLogin, super.key});

  final AppController controller;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final signedIn = controller.signedIn;
    final email = controller.user?.email ?? '';
    return AlertDialog(
      title: const Text('Configuração de conta'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(signedIn ? email : 'Nenhuma conta conectada', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(signedIn ? controller.syncStatus : 'Entre para manter os mesmos dados no celular e no computador.'),
            ),
            const SizedBox(height: 10),
            if (signedIn) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  await controller.sync();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('Sincronizar agora'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await controller.signOut();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sair da conta'),
              ),
            ] else
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onLogin();
                },
                icon: const Icon(Icons.login),
                label: const Text('Entrar ou cadastrar'),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final _service = AppUpdateService();
  bool _busy = true;
  bool _installing = false;
  String _status = 'Verificando atualização…';
  String _currentVersion = '';
  dynamic _update;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      if (!await _service.isSupported()) {
        if (mounted) setState(() { _busy = false; _status = 'A atualização automática está disponível no Android e no Windows.'; });
        return;
      }
      final installed = await _service.getCurrentVersion();
      final latest = await _service.fetchLatestRelease();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentVersion = installed.name;
        if (latest == null) {
          _status = 'Nenhuma versão publicada foi encontrada.';
        } else if (!latest.isNewerThan(installed)) {
          _status = 'Seu MeuKM já está atualizado.';
        } else {
          _update = latest;
          _status = 'Nova versão ${latest.versionName} disponível.';
        }
      });
    } catch (error) {
      if (mounted) setState(() { _busy = false; _status = 'Não foi possível verificar agora.\n$error'; });
    }
  }

  Future<void> _install() async {
    final update = _update;
    if (update == null) return;
    setState(() { _installing = true; _status = 'Baixando e preparando a atualização…'; });
    try {
      await _service.downloadAndInstall(update);
      if (mounted) setState(() { _status = 'Atualização preparada. Siga a tela do sistema para concluir.'; });
    } catch (error) {
      if (mounted) setState(() { _installing = false; _status = 'Não foi possível atualizar.\n$error'; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Atualizar aplicativo'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentVersion.isNotEmpty) Text('Versão instalada: $_currentVersion'),
          if (_currentVersion.isNotEmpty) const SizedBox(height: 10),
          Text(_status),
          if (_busy || _installing) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
          if (_update != null && (_update.releaseNotes as String).isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Novidades', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_update.releaseNotes as String, maxLines: 8, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _installing ? null : () => Navigator.pop(context), child: const Text('Fechar')),
      if (!_busy && _update == null) TextButton(onPressed: _check, child: const Text('Verificar novamente')),
      if (_update != null) FilledButton.icon(onPressed: _installing ? null : _install, icon: const Icon(Icons.system_update_alt), label: Text(_installing ? 'Atualizando…' : 'Baixar e instalar')),
    ],
  );
}
