import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/vehicle_record.dart';
import '../../services/analytics_service.dart';
import '../../services/app_controller.dart';
import '../../services/report_exporter.dart';

class MeuKmShell extends StatefulWidget {
  const MeuKmShell({required this.controller, super.key});

  final AppController controller;

  @override
  State<MeuKmShell> createState() => _MeuKmShellState();
}

class _MeuKmShellState extends State<MeuKmShell> {
  int _index = 0;
  final _analyticsService = const AnalyticsService();

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Histórico'),
    NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Relatórios'),
    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais'),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _addRecord() async {
    final type = await showModalBottomSheet<VehicleRecordType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('O que deseja adicionar?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ListTile(leading: const Icon(Icons.local_gas_station), title: const Text('Abastecimento'), onTap: () => Navigator.pop(context, VehicleRecordType.fuel)),
            ListTile(leading: const Icon(Icons.build), title: const Text('Manutenção'), onTap: () => Navigator.pop(context, VehicleRecordType.maintenance)),
            ListTile(leading: const Icon(Icons.receipt), title: const Text('Outra despesa'), onTap: () => Navigator.pop(context, VehicleRecordType.expense)),
          ]),
        ),
      ),
    );
    if (type == null || !mounted) return;
    final record = await showDialog<VehicleRecord>(
      context: context,
      builder: (_) => RecordDialog(type: type, vehicle: widget.controller.data.currentVehicle),
    );
    if (record != null) {
      await widget.controller.addRecord(record);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro salvo e preparado para sincronização.')));
    }
  }

  Future<void> _openAuth() async {
    await showDialog<void>(context: context, builder: (_) => AuthDialog(controller: widget.controller));
  }

  Future<void> _deleteData() async {
    final confirmation = TextEditingController();
    var enabled = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: const Text('Apagar todos os dados?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Esta ação será sincronizada com os outros aparelhos. Sua conta de acesso será mantida.'),
            const SizedBox(height: 16),
            TextField(
              controller: confirmation,
              decoration: const InputDecoration(labelText: 'Digite APAGAR para confirmar', border: OutlineInputBorder()),
              onChanged: (value) => setDialogState(() => enabled = value.trim().toUpperCase() == 'APAGAR'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: enabled ? () => Navigator.pop(context, true) : null, child: const Text('Apagar definitivamente')),
          ],
        );
      }),
    );
    confirmation.dispose();
    if (confirmed == true) {
      await widget.controller.deleteAllData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados apagados.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final vehicle = controller.data.currentVehicle;
    final analytics = _analyticsService.calculate(vehicle.records);
    final prediction = _analyticsService.predict(vehicle);
    final pages = [
      HomePage(vehicle: vehicle, analytics: analytics, prediction: prediction),
      HistoryPage(records: vehicle.records),
      ReportsPage(vehicle: vehicle, analytics: analytics),
      MorePage(controller: controller, onLogin: _openAuth, onDeleteData: _deleteData),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 860;
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0759D6),
          foregroundColor: Colors.white,
          toolbarHeight: 76,
          title: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.asset('assets/icon.png', width: 48, height: 48)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CONTROLE DO VEÍCULO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              Text('MeuKM', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
            ]),
          ]),
          actions: [Padding(padding: const EdgeInsets.only(right: 18), child: Center(child: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w700))))],
        ),
        body: Row(children: [
          if (desktop)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations.map((item) => NavigationRailDestination(icon: item.icon, selectedIcon: item.selectedIcon, label: Text(item.label))).toList(),
            ),
          Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: pages[_index]))),
        ]),
        bottomNavigationBar: desktop ? null : NavigationBar(selectedIndex: _index, destinations: _destinations, onDestinationSelected: (value) => setState(() => _index = value)),
        floatingActionButton: _index < 2 ? FloatingActionButton.extended(onPressed: _addRecord, icon: const Icon(Icons.add), label: const Text('Adicionar')) : null,
      );
    });
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({required this.title, required this.subtitle, required this.children, super.key});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(subtitle.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
      const SizedBox(height: 5),
      Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 22),
      ...children,
    ],
  );
}

class HomePage extends StatelessWidget {
  const HomePage({required this.vehicle, required this.analytics, required this.prediction, super.key});
  final VehicleData vehicle;
  final VehicleAnalytics analytics;
  final FuelPrediction? prediction;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Visão geral',
    subtitle: vehicle.name,
    children: [
      Card(child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF081F3A), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gasto registrado', style: TextStyle(color: Color(0xFFCCE7FF))),
          const SizedBox(height: 8),
          Text(money(analytics.total), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${vehicle.records.length} registros • ${vehicle.odometer.round()} km', style: const TextStyle(color: Color(0xFFCCE7FF))),
        ]),
      )),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 4 ? 1.6 : 1.35,
          children: [
            MetricCard(label: 'Consumo médio', value: analytics.consumption > 0 ? '${decimal(analytics.consumption)} km/L' : '—'),
            MetricCard(label: 'Custo por km', value: money(analytics.costPerKm)),
            MetricCard(label: 'Distância', value: '${analytics.distance.round()} km'),
            MetricCard(label: 'Odômetro', value: '${vehicle.odometer.round()} km'),
          ],
        );
      }),
      const SizedBox(height: 14),
      Card(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PRÓXIMO ABASTECIMENTO', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Text(prediction == null ? 'Ainda sem previsão' : prediction!.remainingKm <= 0 ? 'Abastecimento provável em breve' : 'Daqui a aproximadamente ${prediction!.remainingKm.round()} km', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(prediction == null ? 'Registre dois tanques completos para começar.' : 'Estimativa para ${prediction!.odometer.round()} km, com média de ${prediction!.averageIntervalKm.round()} km por tanque.'),
        ]),
      )),
    ],
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 10),
      FittedBox(child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
    ]),
  ));
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.records, super.key});
  final List<VehicleRecord> records;

  @override
  Widget build(BuildContext context) {
    final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
    return PageFrame(
      title: 'Histórico',
      subtitle: 'Todos os registros',
      children: sorted.isEmpty
          ? [const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('Nenhum registro encontrado.')))]
          : sorted.map((record) {
              final icon = switch (record.type) {
                VehicleRecordType.fuel => Icons.local_gas_station,
                VehicleRecordType.maintenance => Icons.build,
                VehicleRecordType.expense => Icons.receipt,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  leading: CircleAvatar(child: Icon(icon)),
                  title: Text(record.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${dateText(record.date)} • ${record.odometer.round()} km'),
                  trailing: Text(money(record.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                )),
              );
            }).toList(),
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({required this.vehicle, required this.analytics, super.key});
  final VehicleData vehicle;
  final VehicleAnalytics analytics;

  Future<void> _export(BuildContext context, bool png) async {
    try {
      const exporter = ReportExporter();
      if (png) {
        await exporter.exportPng(vehicle, analytics);
      } else {
        await exporter.exportPdf(vehicle, analytics);
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível exportar o relatório.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = VehicleRecordType.values.map((type) => vehicle.records.where((item) => item.type == type).fold<double>(0, (sum, item) => sum + item.total)).toList();
    return PageFrame(title: 'Relatórios', subtitle: 'Análise do veículo', children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 225, height: 110, child: MetricCard(label: 'Total gasto', value: money(analytics.total))),
        SizedBox(width: 225, height: 110, child: MetricCard(label: 'Custo por km', value: money(analytics.costPerKm))),
        SizedBox(width: 225, height: 110, child: MetricCard(label: 'Consumo médio', value: analytics.consumption > 0 ? '${decimal(analytics.consumption)} km/L' : '—')),
      ]),
      const SizedBox(height: 16),
      Card(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gastos por categoria', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          SizedBox(height: 260, child: CustomPaint(painter: CategoryChartPainter(categories), child: const SizedBox.expand())),
        ]),
      )),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(onPressed: () => _export(context, true), icon: const Icon(Icons.image_outlined), label: const Text('Exportar PNG')),
        FilledButton.icon(onPressed: () => _export(context, false), icon: const Icon(Icons.picture_as_pdf), label: const Text('Exportar PDF')),
      ]),
    ]);
  }
}

class CategoryChartPainter extends CustomPainter {
  CategoryChartPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final labels = ['Combustível', 'Manutenção', 'Outros'];
    final colors = [const Color(0xFFD96B00), const Color(0xFF476A57), const Color(0xFFB93A2F)];
    final maxValue = math.max(1.0, values.fold<double>(0, math.max));
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (var index = 0; index < values.length; index += 1) {
      final top = index * 82.0;
      label.text = TextSpan(text: labels[index], style: const TextStyle(color: Color(0xFF182428), fontSize: 14, fontWeight: FontWeight.w600));
      label.layout();
      label.paint(canvas, Offset(0, top));
      final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, top + 28, size.width, 22), const Radius.circular(11));
      canvas.drawRRect(track, Paint()..color = const Color(0xFFE3E9EB));
      final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, top + 28, size.width * values[index] / maxValue, 22), const Radius.circular(11));
      canvas.drawRRect(fill, Paint()..color = colors[index]);
      label.text = TextSpan(text: money(values[index]), style: const TextStyle(color: Color(0xFF182428), fontSize: 13, fontWeight: FontWeight.w800));
      label.layout();
      label.paint(canvas, Offset(size.width - label.width, top));
    }
  }

  @override
  bool shouldRepaint(covariant CategoryChartPainter oldDelegate) => oldDelegate.values != values;
}

class MorePage extends StatelessWidget {
  const MorePage({required this.controller, required this.onLogin, required this.onDeleteData, super.key});
  final AppController controller;
  final VoidCallback onLogin;
  final VoidCallback onDeleteData;

  @override
  Widget build(BuildContext context) => PageFrame(title: 'Mais opções', subtitle: 'Organização', children: [
    SettingsCard(icon: Icons.person_outline, title: controller.signedIn ? (controller.user?.email ?? 'Conta MeuKM') : 'Entrar ou cadastrar', subtitle: controller.signedIn ? controller.syncStatus : 'Use a mesma conta no celular e no computador', onTap: controller.signedIn ? controller.sync : onLogin),
    const SizedBox(height: 10),
    SettingsCard(icon: Icons.cloud_sync, title: 'Sincronizar agora', subtitle: controller.syncStatus, onTap: controller.signedIn ? controller.sync : onLogin),
    const SizedBox(height: 10),
    if (controller.signedIn) ...[
      SettingsCard(icon: Icons.logout, title: 'Sair da conta', subtitle: 'Os dados continuam salvos neste aparelho', onTap: controller.signOut),
      const SizedBox(height: 10),
    ],
    const SettingsCard(icon: Icons.backup, title: 'Backup dos dados', subtitle: 'A importação e exportação local chegam na próxima etapa nativa'),
    const SizedBox(height: 10),
    SettingsCard(icon: Icons.delete_outline, title: 'Apagar dados', subtitle: 'Exige confirmação e sincroniza a exclusão', color: Theme.of(context).colorScheme.error, onTap: onDeleteData),
    const SizedBox(height: 10),
    SettingsCard(icon: Icons.info_outline, title: 'MeuKM nativo', subtitle: 'Beta Flutter para Android e Windows • versão 0.2.0', color: Theme.of(context).colorScheme.primary),
  ]);
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.icon, required this.title, required this.subtitle, this.color, this.onTap, super.key});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    leading: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  ));
}

class AuthDialog extends StatefulWidget {
  const AuthDialog({required this.controller, super.key});
  final AppController controller;

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.length < 6 || (_register && _name.text.trim().length < 2)) {
      setState(() => _message = 'Preencha os campos e use uma senha com pelo menos 6 caracteres.');
      return;
    }
    setState(() { _busy = true; _message = ''; });
    try {
      if (_register) {
        final active = await widget.controller.signUp(name: _name.text, email: _email.text, password: _password.text);
        if (!active) {
          setState(() { _message = 'Cadastro criado. Confirme o e-mail recebido e depois entre.'; _register = false; _busy = false; });
          return;
        }
      } else {
        await widget.controller.signIn(email: _email.text, password: _password.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { _message = 'Não foi possível entrar. Confira o e-mail, a senha e a conexão.'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conta MeuKM'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Entrar')), ButtonSegment(value: true, label: Text('Cadastrar'))],
          selected: {_register},
          onSelectionChanged: (value) => setState(() { _register = value.first; _message = ''; }),
        ),
        const SizedBox(height: 18),
        if (_register) TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
        if (_register) const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder())),
        if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Aguarde…' : _register ? 'Criar conta' : 'Entrar')),
    ],
  );
}

class RecordDialog extends StatefulWidget {
  const RecordDialog({required this.type, required this.vehicle, super.key});
  final VehicleRecordType type;
  final VehicleData vehicle;

  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  late final TextEditingController _odometer;
  final _total = TextEditingController();
  final _liters = TextEditingController();
  final _price = TextEditingController();
  final _place = TextEditingController();
  late final TextEditingController _label;
  DateTime _date = DateTime.now();
  bool _fullTank = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _odometer = TextEditingController(text: widget.vehicle.odometer.round().toString());
    _label = TextEditingController(text: switch (widget.type) {
      VehicleRecordType.fuel => 'Gasolina comum',
      VehicleRecordType.maintenance => 'Troca de óleo',
      VehicleRecordType.expense => 'Outra despesa',
    });
  }

  @override
  void dispose() {
    _odometer.dispose();
    _total.dispose();
    _liters.dispose();
    _price.dispose();
    _place.dispose();
    _label.dispose();
    super.dispose();
  }

  double _value(TextEditingController controller) => double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;

  void _save() {
    final total = _value(_total);
    final odometer = _value(_odometer);
    final liters = _value(_liters);
    if (odometer <= 0 || total < 0 || (widget.type == VehicleRecordType.fuel && liters <= 0)) {
      setState(() => _message = 'Informe o odômetro e os valores obrigatórios.');
      return;
    }
    final now = DateTime.now().toUtc();
    Navigator.pop(context, VehicleRecord(
      id: 'native-${now.microsecondsSinceEpoch}',
      vehicleId: widget.vehicle.id,
      type: widget.type,
      date: _date,
      odometer: odometer,
      total: total,
      label: _label.text.trim().isEmpty ? 'Registro' : _label.text.trim(),
      updatedAt: now,
      liters: widget.type == VehicleRecordType.fuel ? liters : null,
      pricePerLiter: widget.type == VehicleRecordType.fuel ? _value(_price) : null,
      fullTank: widget.type == VehicleRecordType.fuel && _fullTank,
      place: _place.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.type) {
      VehicleRecordType.fuel => 'Novo abastecimento',
      VehicleRecordType.maintenance => 'Nova manutenção',
      VehicleRecordType.expense => 'Nova despesa',
    };
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Data: ${dateText(_date)}')),
            TextButton(onPressed: () async {
              final selected = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _date);
              if (selected != null) setState(() => _date = selected);
            }, child: const Text('Alterar')),
          ]),
          TextField(controller: _odometer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Odômetro (km)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          if (widget.type == VehicleRecordType.fuel) ...[
            TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Preço por litro', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _liters, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Litros', border: OutlineInputBorder())),
            const SizedBox(height: 12),
          ],
          TextField(controller: _total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor total', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _place, decoration: const InputDecoration(labelText: 'Local ou estabelecimento', border: OutlineInputBorder())),
          if (widget.type == VehicleRecordType.fuel) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tanque completo'), subtitle: const Text('Necessário para calcular km/L'), value: _fullTank, onChanged: (value) => setState(() => _fullTank = value)),
          if (_message.isNotEmpty) Text(_message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

String money(double value) => 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
String decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
String dateText(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
