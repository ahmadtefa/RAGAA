import 'package:flutter/widgets.dart';
import 'package:printing/printing.dart';

import '../../models/daily_journal.dart';
import '../../services/daily_journal_pdf_service.dart';

class DailyJournalPreview extends StatelessWidget {
  final DailyJournal journal;

  const DailyJournalPreview({super.key, required this.journal});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (!journal.hasData)
        Text('لا توجد تحصيلات مسجّلة في ${journal.operationalDate}'),
      Expanded(child: PdfPreview(
        key: ObjectKey(journal),
        initialPageFormat: DailyJournalPdfService.pageFormat,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: 'RAGAA-${journal.operationalDate}.pdf',
        build: (_) => DailyJournalPdfService().buildJournalPdfBytes(journal),
      )),
    ]);
  }
}
