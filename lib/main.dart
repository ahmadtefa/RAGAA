import 'dart:convert';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RagaaApp());
}

class Outlet {
  final String id;
  final String name;
  final int shiftCount;
  const Outlet(this.id, this.name, this.shiftCount);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shiftCount': shiftCount,
      };

  factory Outlet.fromJson(Map<String, dynamic> j) {
    final rawShiftCount = (j['shiftCount'] as int?) ?? 2;
    final normalizedShifts =
        (rawShiftCount == 2 || rawShiftCount == 3) ? rawShiftCount : 2;
    return Outlet(j['id'] as String, j['name'] as String, normalizedShifts);
  }
}

class Collection {
  final String outletId;
  final String day; // Operational date, strict yyyy-MM-dd.
  final int shift; // 1, 2, or 3.
  final int piastres; // Integer money avoids floating-point rounding.
  const Collection(this.outletId, this.day, this.shift, this.piastres);

  String get key => '$outletId|$day|$shift';

  Map<String, dynamic> toJson() => {
        'outletId': outletId,
        'day': day,
        'shift': shift,
        'piastres': piastres,
      };

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        j['outletId'] as String,
        j['day'] as String,
        j['shift'] as int,
        j['piastres'] as int,
      );
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool isValidOperationalDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final parsed = DateTime(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day;
}

String normalizeDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final idx1 = arabicIndic.indexOf(ch);
    if (idx1 != -1) {
      buffer.write(idx1);
      continue;
    }
    final idx2 = easternArabic.indexOf(ch);
    if (idx2 != -1) {
      buffer.write(idx2);
      continue;
    }
    if (ch == '٫' || ch == ',') {
      buffer.write('.');
      continue;
    }
    if (ch == '٬' || ch == ' ') {
      continue;
    }
    buffer.write(ch);
  }
  return buffer.toString();
}

int? tryParsePiastres(String raw) {
  final cleaned = normalizeDigits(raw.trim());
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final pounds = int.tryParse(parts[0]);
  if (pounds == null) return null;
  final fraction =
      parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return pounds * 100 + fraction;
}

String money(int piastres) => (piastres / 100).toStringAsFixed(2);

String shiftArabicLabel(int shift) {
  switch (shift) {
    case 1:
      return 'الوردية الأولى';
    case 2:
      return 'الوردية الثانية';
    case 3:
      return 'الوردية الثالثة';
    default:
      return 'الوردية $shift';
  }
}

class RagaaStore extends ChangeNotifier {
  final List<Outlet> outlets = [];
  final List<Collection> collections = [];
  bool ready = false;
  static const _outletsKey = 'ragaa_outlets_v1';
  static const _collectionsKey = 'ragaa_collections_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loadedOutlets =
        ((jsonDecode(prefs.getString(_outletsKey) ?? '[]')) as List)
            .map((e) => Outlet.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    final loadedCollections =
        ((jsonDecode(prefs.getString(_collectionsKey) ?? '[]')) as List)
            .map(
              (e) => Collection.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
    outlets
      ..clear()
      ..addAll(loadedOutlets);
    collections
      ..clear()
      ..addAll(loadedCollections);
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _outletsKey,
      jsonEncode(outlets.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      _collectionsKey,
      jsonEncode(collections.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> addOutlet(String name, int shiftCount) async {
    if (shiftCount != 2 && shiftCount != 3) {
      throw const FormatException('عدد الورديات يجب أن يكون 2 أو 3');
    }
    final clean = name.trim();
    if (clean.isEmpty ||
        outlets.any((o) => o.name.toLowerCase() == clean.toLowerCase())) {
      throw const FormatException('اسم المنفذ فارغ أو مكرر');
    }
    outlets.add(
      Outlet(
        DateTime.now().microsecondsSinceEpoch.toString(),
        clean,
        shiftCount,
      ),
    );
    await _save();
  }

  Future<void> saveCollection(Collection record) async {
    final outletIndex = outlets.indexWhere((o) => o.id == record.outletId);
    if (outletIndex == -1 ||
        record.shift < 1 ||
        record.shift > outlets[outletIndex].shiftCount ||
        record.piastres < 0 ||
        !isValidOperationalDate(record.day)) {
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
      collections.where(
        (c) =>
            c.day.compareTo(start) >= 0 &&
            c.day.compareTo(end) <= 0 &&
            (shift == null || c.shift == shift),
      );
}

class RagaaApp extends StatelessWidget {
  const RagaaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RAGAA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          // ignore: deprecated_member_use
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          // ignore: deprecated_member_use
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
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
  DateTime from = dateOnly(DateTime.now());
  DateTime to = dateOnly(DateTime.now());
  int? shift;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
    store.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_refresh);
    store.dispose();
    super.dispose();
  }

  Future<void> _addOutlet() async {
    final result = await showDialog<({String name, int shiftCount})>(
      context: context,
      builder: (_) => const _AddOutletDialog(),
    );
    if (result == null) return;
    try {
      await store.addOutlet(result.name, result.shiftCount);
    } on FormatException catch (e) {
      _error(e.message);
    } catch (e) {
      _error(e.toString());
    }
  }

  Future<void> _addCollection() async {
    if (store.outlets.isEmpty) {
      _error('أضف منفذًا أولًا');
      return;
    }
    final result = await showDialog<Collection>(
      context: context,
      builder: (_) => _AddCollectionDialog(outlets: store.outlets),
    );
    if (result == null) return;
    final exists = store.collections.any((c) => c.key == result.key);
    if (exists && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تحصيل مسجل بالفعل'),
          content:
              const Text('هذه الوردية مسجلة. هل تريد استبدال المبلغ السابق؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استبدال'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await store.saveCollection(result);
    } on FormatException catch (e) {
      _error(e.message);
    } catch (e) {
      _error(e.toString());
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickDate(bool start) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null) {
      setState(() {
        if (start) {
          from = dateOnly(chosen);
        } else {
          to = dateOnly(chosen);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!store.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final invalidRange = dateOnly(from).isAfter(dateOnly(to));
    final rows = invalidRange
        ? <Collection>[]
        : store.filtered(dateKey(from), dateKey(to), shift).toList();
    final total = rows.fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftOne =
        rows.where((c) => c.shift == 1).fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftTwo =
        rows.where((c) => c.shift == 2).fold<int>(0, (sum, c) => sum + c.piastres);
    final shiftThree =
        rows.where((c) => c.shift == 3).fold<int>(0, (sum, c) => sum + c.piastres);
    final names = {for (final o in store.outlets) o.id: o.name};

    return Scaffold(
      appBar: AppBar(title: const Text('RAGAA | إدارة التحصيل')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _addOutlet,
                icon: const Icon(Icons.add_business),
                label: const Text('إضافة منفذ'),
              ),
              FilledButton.icon(
                onPressed: _addCollection,
                icon: const Icon(Icons.payments),
                label: const Text('تسجيل تحصيل'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => _pickDate(true),
                child: Text('من: ${dateKey(from)}'),
              ),
              OutlinedButton(
                onPressed: () => _pickDate(false),
                child: Text('إلى: ${dateKey(to)}'),
              ),
              DropdownButton<int?>(
                value: shift,
                hint: const Text('كل الورديات'),
                items: const [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('كل الورديات'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 1,
                    child: Text('الوردية الأولى'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 2,
                    child: Text('الوردية الثانية'),
                  ),
                  DropdownMenuItem<int?>(
                    value: 3,
                    child: Text('الوردية الثالثة'),
                  ),
                ],
                onChanged: (v) => setState(() => shift = v),
              ),
            ],
          ),
          if (invalidRange)
            const Text(
              'تاريخ البداية يجب ألا يكون بعد تاريخ النهاية',
              style: TextStyle(color: Colors.red),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric('إجمالي التحصيل', '${money(total)} ج.م'),
              _Metric('الوردية الأولى', '${money(shiftOne)} ج.م'),
              _Metric('الوردية الثانية', '${money(shiftTwo)} ج.م'),
              _Metric('الوردية الثالثة', '${money(shiftThree)} ج.م'),
              _Metric('عدد المنافذ', '${store.outlets.length}'),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'تفاصيل التحصيل',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد بيانات في الفترة المحددة'),
            ),
          ...rows.map(
            (c) => Card(
              child: ListTile(
                title: Text(names[c.outletId] ?? 'منفذ غير معروف'),
                subtitle: Text('${c.day} — ${shiftArabicLabel(c.shift)}'),
                trailing: Text('${money(c.piastres)} ج.م'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOutletDialog extends StatefulWidget {
  const _AddOutletDialog();
  @override
  State<_AddOutletDialog> createState() => _AddOutletDialogState();
}

class _AddOutletDialogState extends State<_AddOutletDialog> {
  final _nameController = TextEditingController();
  int _shiftCount = 2;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إضافة منفذ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم المنفذ'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _shiftCount,
              decoration:
                  const InputDecoration(labelText: 'عدد الورديات يوميًا'),
              items: const [
                DropdownMenuItem(value: 2, child: Text('ورديتان')),
                DropdownMenuItem(value: 3, child: Text('3 ورديات')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _shiftCount = v);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (name: _nameController.text, shiftCount: _shiftCount),
            ),
            child: const Text('حفظ'),
          ),
        ],
      );
}

class _AddCollectionDialog extends StatefulWidget {
  final List<Outlet> outlets;
  const _AddCollectionDialog({required this.outlets});

  @override
  State<_AddCollectionDialog> createState() => _AddCollectionDialogState();
}

class _AddCollectionDialogState extends State<_AddCollectionDialog> {
  late String _outletId = widget.outlets.first.id;
  int _selectedShift = 1;
  DateTime _day = dateOnly(DateTime.now());
  final _amountController = TextEditingController();
  String? _validationError;

  int _shiftCountFor(String id) =>
      widget.outlets.firstWhere((o) => o.id == id).shiftCount;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftCount = _shiftCountFor(_outletId);
    return AlertDialog(
      title: const Text('تسجيل تحصيل وردية'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _outletId,
              decoration: const InputDecoration(labelText: 'المنفذ'),
              items: widget.outlets
                  .map(
                    (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _outletId = v;
                    if (_selectedShift > _shiftCountFor(v)) {
                      _selectedShift = 1;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('$_outletId-$shiftCount-$_selectedShift'),
              initialValue: _selectedShift,
              decoration: const InputDecoration(labelText: 'الوردية'),
              items: List.generate(
                shiftCount,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(shiftArabicLabel(i + 1)),
                ),
              ),
              onChanged: (v) {
                if (v != null) setState(() => _selectedShift = v);
              },
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() => _day = dateOnly(picked));
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: Text('تاريخ الوردية: ${dateKey(_day)}'),
            ),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'التحصيل بالجنيه',
                hintText: '0.00',
                errorText: _validationError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final piastres = tryParsePiastres(_amountController.text);
            if (piastres == null) {
              setState(() {
                _validationError = 'أدخل مبلغًا صحيحًا بحد أقصى رقمين عشريين';
              });
              return;
            }
            Navigator.pop(
              context,
              Collection(_outletId, dateKey(_day), _selectedShift, piastres),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String title;
  final String value;
  const _Metric(this.title, this.value);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
}
