import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RagaaApp());

class Outlet {
  final String id;
  final String name;
  final int shiftCount;
  const Outlet(this.id, this.name, this.shiftCount);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'shiftCount': shiftCount};
  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(j['id'] as String, j['name'] as String, (j['shiftCount'] as int?) ?? 2);
}

class Collection {
  final String outletId;
  final String day; // Operational date, yyyy-MM-dd.
  final int shift; // 1 or 2.
  final int piastres; // Integer money avoids floating-point rounding.
  const Collection(this.outletId, this.day, this.shift, this.piastres);
  String get key => '$outletId|$day|$shift';
  Map<String, dynamic> toJson() => {'outletId': outletId, 'day': day, 'shift': shift, 'piastres': piastres};
  factory Collection.fromJson(Map<String, dynamic> j) => Collection(j['outletId'] as String, j['day'] as String, j['shift'] as int, j['piastres'] as int);
}

class RagaaStore extends ChangeNotifier {
  final List<Outlet> outlets = [];
  final List<Collection> collections = [];
  bool ready = false;
  static const _outletsKey = 'ragaa_outlets_v1';
  static const _collectionsKey = 'ragaa_collections_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    outlets.addAll(((jsonDecode(prefs.getString(_outletsKey) ?? '[]')) as List)
        .map((e) => Outlet.fromJson(Map<String, dynamic>.from(e as Map))));
    collections.addAll(((jsonDecode(prefs.getString(_collectionsKey) ?? '[]')) as List)
        .map((e) => Collection.fromJson(Map<String, dynamic>.from(e as Map))));
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outletsKey, jsonEncode(outlets.map((e) => e.toJson()).toList()));
    await prefs.setString(_collectionsKey, jsonEncode(collections.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> addOutlet(String name, int shiftCount) async {
    if (shiftCount != 2 && shiftCount != 3) throw const FormatException('عدد الورديات يجب أن يكون 2 أو 3');
    final clean = name.trim();
    if (clean.isEmpty || outlets.any((o) => o.name.toLowerCase() == clean.toLowerCase())) {
      throw const FormatException('اسم المنفذ فارغ أو مكرر');
    }
    outlets.add(Outlet(DateTime.now().microsecondsSinceEpoch.toString(), clean, shiftCount));
    await _save();
  }

  Future<void> saveCollection(Collection record) async {
    if (!outlets.any((o) => o.id == record.outletId) ||
        record.shift < 1 || record.shift > outlets.firstWhere((o) => o.id == record.outletId).shiftCount || record.piastres < 0 ||
        DateTime.tryParse(record.day) == null) {
      throw const FormatException('بيانات التحصيل غير صحيحة');
    }
    final index = collections.indexWhere((c) => c.key == record.key);
    if (index == -1) {
      collections.add(record);
    } else {
      collections[index] = record;
    }
    await _save();
  }

  Iterable<Collection> filtered(String start, String end, int? shift) =>
      collections.where((c) => c.day.compareTo(start) >= 0 &&
          c.day.compareTo(end) <= 0 && (shift == null || c.shift == shift));
}

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String money(int piastres) => (piastres / 100).toStringAsFixed(2);

class RagaaApp extends StatelessWidget {
  const RagaaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RAGAA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    locale: const Locale('ar'),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final store = RagaaStore();
  DateTime from = DateTime.now();
  DateTime to = DateTime.now();
  int? shift;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
    store.load();
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() {
    store.removeListener(_refresh);
    store.dispose();
    super.dispose();
  }

  Future<void> _addOutlet() async {
    final controller = TextEditingController();
    int shiftCount = 2;
    final name = await showDialog<String>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(title: const Text('إضافة منفذ'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'اسم المنفذ')),
        DropdownButtonFormField<int>(initialValue: shiftCount, decoration: const InputDecoration(labelText: 'عدد الورديات يوميًا'), items: const [DropdownMenuItem(value: 2, child: Text('ورديتان')), DropdownMenuItem(value: 3, child: Text('3 ورديات'))], onChanged: (v) { if (v != null) update(() => shiftCount = v); }),
      ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('حفظ'))])));
    controller.dispose();
    if (name == null) return;
    try { await store.addOutlet(name, shiftCount); } catch (e) { _error(e.toString()); }
  }

  Future<void> _addCollection() async {
    if (store.outlets.isEmpty) { _error('أضف منفذًا أولًا'); return; }
    String outletId = store.outlets.first.id;
    int selectedShift = 1;
    DateTime day = DateTime.now();
    final amount = TextEditingController();
    int countFor(String id) => store.outlets.firstWhere((o) => o.id == id).shiftCount;
    final result = await showDialog<Collection>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('تسجيل تحصيل وردية'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(initialValue: outletId, decoration: const InputDecoration(labelText: 'المنفذ'),
            items: store.outlets.map((o) => DropdownMenuItem(value: o.id, child: Text(o.name))).toList(),
            onChanged: (v) { if (v != null) update(() { outletId = v; if (selectedShift > countFor(v)) selectedShift = 1; }); }),
          DropdownButtonFormField<int>(initialValue: selectedShift, decoration: const InputDecoration(labelText: 'الوردية'),
            items: List.generate(countFor(outletId), (i) => DropdownMenuItem(value: i + 1, child: Text('الوردية ${i + 1}'))),
            onChanged: (v) { if (v != null) update(() => selectedShift = v); }),
          TextButton.icon(onPressed: () async {
            final picked = await showDatePicker(context: ctx, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null) update(() => day = picked);
          }, icon: const Icon(Icons.calendar_month), label: Text('تاريخ الوردية: ${dateKey(day)}')),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'التحصيل بالجنيه', hintText: '0.00')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final input = amount.text.trim().replaceAll(',', '.');
            if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(input)) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صحيحًا بحد أقصى رقمين عشريين')));
              return;
            }
            final parts = input.split('.');
            final piastres = int.parse(parts[0]) * 100 + (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
            Navigator.pop(ctx, Collection(outletId, dateKey(day), selectedShift, piastres));
          }, child: const Text('حفظ')),
        ],
      )));
    amount.dispose();
    if (result == null) return;
    final exists = store.collections.any((c) => c.key == result.key);
    if (exists && mounted) {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('تحصيل مسجل بالفعل'),
        content: const Text('هذه الوردية مسجلة. هل تريد استبدال المبلغ السابق؟'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استبدال'))]));
      if (confirmed != true) return;
    }
    try { await store.saveCollection(result); } catch (e) { _error(e.toString()); }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate(bool start) async {
    final chosen = await showDatePicker(context: context, initialDate: start ? from : to,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (chosen != null) setState(() { if (start) { from = chosen; } else { to = chosen; } });
  }

  @override
  Widget build(BuildContext context) {
    if (!store.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final rows = from.isAfter(to) ? <Collection>[] : store.filtered(dateKey(from), dateKey(to), shift).toList();
    final total = rows.fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftOne = rows.where((c) => c.shift == 1).fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftTwo = rows.where((c) => c.shift == 2).fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftThree = rows.where((c) => c.shift == 3).fold<int>(0, (sum, c) => sum + c.piastres);
    final names = {for (final o in store.outlets) o.id: o.name};
    return Scaffold(
      appBar: AppBar(title: const Text('RAGAA | إدارة التحصيل')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _addOutlet, icon: const Icon(Icons.add_business), label: const Text('إضافة منفذ')),
          FilledButton.icon(onPressed: _addCollection, icon: const Icon(Icons.payments), label: const Text('تسجيل تحصيل')),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton(onPressed: () => _pickDate(true), child: Text('من: ${dateKey(from)}')),
          OutlinedButton(onPressed: () => _pickDate(false), child: Text('إلى: ${dateKey(to)}')),
          DropdownButton<int?>(value: shift, hint: const Text('كل الورديات'),
            items: const [DropdownMenuItem<int?>(value: null, child: Text('كل الورديات')),
              DropdownMenuItem<int?>(value: 1, child: Text('الوردية الأولى')),
              DropdownMenuItem<int?>(value: 2, child: Text('الوردية الثانية')),
              DropdownMenuItem<int?>(value: 3, child: Text('الوردية الثالثة'))],
            onChanged: (v) => setState(() => shift = v)),
        ]),
        if (from.isAfter(to)) const Text('تاريخ البداية يجب ألا يكون بعد تاريخ النهاية', style: TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Metric('إجمالي التحصيل', '${money(total)} ج.م'),
          _Metric('الوردية الأولى', '${money(shiftOne)} ج.م'),
          _Metric('الوردية الثانية', '${money(shiftTwo)} ج.م'),
          _Metric('الوردية الثالثة', '${money(shiftThree)} ج.م'),
          _Metric('عدد المنافذ', '${store.outlets.length}'),
        ]),
        const SizedBox(height: 20),
        const Text('تفاصيل التحصيل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات في الفترة المحددة')),
        ...rows.map((c) => Card(child: ListTile(
          title: Text(names[c.outletId] ?? 'منفذ غير معروف'),
          subtitle: Text('${c.day} — الوردية ${c.shift == 1 ? 'الأولى' : c.shift == 2 ? 'الثانية' : 'الثالثة'}'),
          trailing: Text('${money(c.piastres)} ج.م'),
        ))),
        const SizedBox(height: 16),
        const Text('المرحلة الأولى: تخزين محلي على الجهاز. التصدير إلى PDF وExcel في المرحلة التالية.'),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final String value;
  const _Metric(this.title, this.value);
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title), const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
    ]),
  ));
}
