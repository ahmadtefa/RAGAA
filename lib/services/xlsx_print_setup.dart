import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Result of an OOXML patch attempt.
class XlsxPrintSetupResult {
  final Uint8List bytes;

  /// `true` when the requested OOXML changes were actually injected.
  final bool applied;

  const XlsxPrintSetupResult({required this.bytes, required this.applied});
}

/// Post-processes a generated `.xlsx` package to add the pieces of OOXML that
/// the `excel` package does not expose:
///
/// - `fullCalcOnLoad` so Excel/LibreOffice recompute every formula on open
///   (the workbook is written without cached formula results);
/// - landscape orientation, fit-to-one-page-wide, a frozen header row and an
///   explicit print area for the daily journal sheet.
///
/// Every XML edit is conservative and guarded: if anything looks unexpected the
/// original bytes are returned untouched, so a produced workbook can never be
/// corrupted by this step. Callers additionally re-decode the patched bytes.
class XlsxPrintSetup {
  static const String _worksheetPath = 'xl/worksheets/sheet';
  static const String _workbookPath = 'xl/workbook.xml';
  static const String _workbookRelsPath = 'xl/_rels/workbook.xml.rels';
  static const String _calcPr = '<calcPr calcId="191029" fullCalcOnLoad="1"/>';

  /// Forces a full recalculation when the workbook is opened.
  static XlsxPrintSetupResult ensureFullRecalc(Uint8List bytes) {
    try {
      final files = _readZip(bytes);
      final workbookXml = _readText(files, _workbookPath);
      if (workbookXml == null || workbookXml.contains('fullCalcOnLoad')) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      final patched = _injectCalcPr(workbookXml);
      if (patched == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      files[_workbookPath] = utf8.encode(patched);
      final encoded = _writeZip(files);
      if (encoded == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      return XlsxPrintSetupResult(bytes: encoded, applied: true);
    } catch (_) {
      return XlsxPrintSetupResult(bytes: bytes, applied: false);
    }
  }

  /// Applies the printable page setup (landscape, fit-to-one-page-wide, frozen
  /// header rows, repeating header rows and an explicit print area) to the
  /// worksheet called [sheetName].
  ///
  /// [lastRow] and [lastColumn] are 0-based inclusive indexes of the used range;
  /// [freezeRows] is the number of header rows kept visible when scrolling and
  /// repeated when printing.
  static XlsxPrintSetupResult apply(
    Uint8List bytes, {
    required String sheetName,
    required int lastRow,
    required int lastColumn,
    int freezeRows = 3,
    bool landscape = true,
  }) {
    try {
      final files = _readZip(bytes);
      final workbookXml = _readText(files, _workbookPath);
      if (workbookXml == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      final sheetIndex = _sheetIndex(workbookXml, sheetName);
      if (sheetIndex == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      final sheetPath = _resolveSheetPath(files, workbookXml, sheetIndex);
      if (sheetPath == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      final sheetXml = _readText(files, sheetPath);
      if (sheetXml == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }

      var patchedSheet = _injectSheetProperties(sheetXml);
      patchedSheet = _injectFrozenPane(patchedSheet, freezeRows: freezeRows);
      patchedSheet = _injectPageSetup(patchedSheet, landscape: landscape);
      if (patchedSheet == sheetXml) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      files[sheetPath] = utf8.encode(patchedSheet);

      final printArea = '<definedNames>'
          '<definedName name="_xlnm.Print_Area" localSheetId="$sheetIndex">'
          "'${_escapeXml(sheetName)}'!\$A\$1:"
          '${_columnLetter(lastColumn)}\$${lastRow + 1}'
          '</definedName></definedNames>';
      var patchedWorkbook = _injectPrintArea(workbookXml, printArea) ??
          workbookXml;
      final withCalcPr = _injectCalcPr(patchedWorkbook);
      if (withCalcPr != null) patchedWorkbook = withCalcPr;
      files[_workbookPath] = utf8.encode(patchedWorkbook);

      final encoded = _writeZip(files);
      if (encoded == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      return XlsxPrintSetupResult(bytes: encoded, applied: true);
    } catch (_) {
      return XlsxPrintSetupResult(bytes: bytes, applied: false);
    }
  }

  /// Applies the same printable page setup to **every** worksheet of the
  /// workbook, deriving each print area from the sheet's own `<dimension>`
  /// element so no column or row is ever cut off when printing.
  static XlsxPrintSetupResult applyAll(
    Uint8List bytes, {
    int freezeRows = 3,
    bool landscape = true,
  }) {
    try {
      final files = _readZip(bytes);
      var workbookXml = _readText(files, _workbookPath);
      if (workbookXml == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }

      final sheetNames = <String>[];
      for (final match in RegExp(r'<sheet\b[^>]*>').allMatches(workbookXml)) {
        final nameMatch =
            RegExp(r'name="([^"]*)"').firstMatch(match.group(0)!);
        if (nameMatch != null) sheetNames.add(nameMatch.group(1)!);
      }
      if (sheetNames.isEmpty) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }

      final definitions = StringBuffer();
      var changed = false;
      for (var index = 0; index < sheetNames.length; index++) {
        final sheetPath = _resolveSheetPath(files, workbookXml, index);
        if (sheetPath == null) continue;
        final sheetXml = _readText(files, sheetPath);
        if (sheetXml == null) continue;

        var patched = _injectSheetProperties(sheetXml);
        patched = _injectFrozenPane(patched, freezeRows: freezeRows);
        patched = _injectPageSetup(patched, landscape: landscape);
        if (sheetNames[index] == 'اليومية') {
          patched = patched.replaceFirst(RegExp(r'<pageMargins\b[^>]*/>'),
              '<pageMargins left="0.28" right="0.28" top="0.23" bottom="0.23" header="0" footer="0"/>');
          final end = _lastCellRef(patched)?.replaceAll(r'$', '');
          if (end != null) {
            patched = patched.replaceFirst(RegExp(r'<dimension\b[^>]*/>'),
                '<dimension ref="A1:$end"/>');
          }
        }
        if (patched != sheetXml) {
          files[sheetPath] = utf8.encode(patched);
          changed = true;
        }

        if (sheetNames[index] == 'اليومية') {
          definitions.write('<definedName name="_xlnm.Print_Titles" localSheetId="$index">'
              "'اليومية'!\$1:\$3</definedName>");
        }
        final lastCell = _lastCellRef(patched) ?? 'A1';
        definitions.write(
          '<definedName name="_xlnm.Print_Area" localSheetId="$index">'
          "'${_escapeXml(sheetNames[index])}'!\$A\$1:$lastCell"
          '</definedName>',
        );
      }

      final withAreas =
          _injectDefinedNames(workbookXml, definitions.toString());
      if (withAreas != null) {
        workbookXml = withAreas;
        changed = true;
      }
      final withCalcPr = _injectCalcPr(workbookXml);
      if (withCalcPr != null) {
        workbookXml = withCalcPr;
        changed = true;
      }
      files[_workbookPath] = utf8.encode(workbookXml);

      if (!changed) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      final encoded = _writeZip(files);
      if (encoded == null) {
        return XlsxPrintSetupResult(bytes: bytes, applied: false);
      }
      return XlsxPrintSetupResult(bytes: encoded, applied: true);
    } catch (_) {
      return XlsxPrintSetupResult(bytes: bytes, applied: false);
    }
  }

  /// The Excel encoder may leave the template dimension at A1. Include actual
  /// cells and merged endpoints when computing the rectangle sent to print.
  static String? _lastCellRef(String sheetXml) {
    var maxColumn = -1;
    var maxRow = 0;
    final pattern = RegExp(
      r'<(?:c|mergeCell)\b[^>]*?\b(?:r|ref)="(?:[A-Z]+\d+:)?([A-Z]+)(\d+)"',
    );
    for (final cell in pattern.allMatches(sheetXml)) {
      final col = _columnIndex(cell.group(1)!);
      final row = int.parse(cell.group(2)!);
      if (col > maxColumn) maxColumn = col;
      if (row > maxRow) maxRow = row;
    }
    if (maxColumn < 0) return null;
    return '\$${_columnLetter(maxColumn)}\$$maxRow';
  }

  static int _columnIndex(String letters) {
    var value = 0;
    for (final unit in letters.codeUnits) {
      value = value * 26 + (unit - 64);
    }
    return value - 1;
  }

  // ---------------------------------------------------------------------------
  // ZIP helpers
  // ---------------------------------------------------------------------------

  static Map<String, List<int>> _readZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      files[file.name] = List<int>.from(file.content as List);
    }
    return files;
  }

  static Uint8List? _writeZip(Map<String, List<int>> files) {
    final rebuilt = Archive();
    files.forEach((name, content) {
      rebuilt.addFile(ArchiveFile(name, content.length, content));
    });
    final encoded = ZipEncoder().encode(rebuilt);
    if (encoded == null || encoded.isEmpty) return null;
    return Uint8List.fromList(encoded);
  }

  static String? _readText(Map<String, List<int>> files, String path) {
    final content = files[path];
    if (content == null) return null;
    return utf8.decode(content, allowMalformed: true);
  }

  // ---------------------------------------------------------------------------
  // Workbook.xml patches
  // ---------------------------------------------------------------------------

  static String? _injectCalcPr(String workbookXml) {
    if (workbookXml.contains('fullCalcOnLoad')) return null;
    // The `excel` package always writes an empty `<calcPr/>`; replace it rather
    // than appending a second element (which would be invalid OOXML).
    final existing = RegExp(r'<calcPr\b[^>]*/>').firstMatch(workbookXml);
    if (existing != null) {
      return workbookXml.replaceRange(existing.start, existing.end, _calcPr);
    }
    final closeIndex = workbookXml.lastIndexOf('</workbook>');
    if (closeIndex < 0) return null;
    return workbookXml.replaceRange(
      closeIndex,
      closeIndex,
      _calcPr,
    );
  }

  /// Finds the 0-based position of [sheetName] inside `workbook.xml`.
  static int? _sheetIndex(String workbookXml, String sheetName) {
    final sheetTags = RegExp(r'<sheet\b[^>]*>').allMatches(workbookXml).toList();
    for (var index = 0; index < sheetTags.length; index++) {
      final nameMatch =
          RegExp(r'name="([^"]*)"').firstMatch(sheetTags[index].group(0)!);
      if (nameMatch == null) continue;
      if (nameMatch.group(1) == sheetName) return index;
    }
    return null;
  }

  /// Resolves the worksheet part for [sheetIndex], preferring the canonical
  /// `sheetN.xml` names and falling back to the workbook relationships.
  static String? _resolveSheetPath(
    Map<String, List<int>> files,
    String workbookXml,
    int sheetIndex,
  ) {
    final canonical = '$_worksheetPath${sheetIndex + 1}.xml';
    if (files.containsKey(canonical)) return canonical;

    final sheetTags = RegExp(r'<sheet\b[^>]*>').allMatches(workbookXml).toList();
    if (sheetIndex >= sheetTags.length) return null;
    final relIdMatch =
        RegExp(r'r:id="([^"]*)"').firstMatch(sheetTags[sheetIndex].group(0)!);
    if (relIdMatch == null) return null;
    final relId = relIdMatch.group(1);
    final relsXml = _readText(files, _workbookRelsPath);
    if (relsXml == null) return null;
    for (final match in RegExp(r'<Relationship\b[^>]*>').allMatches(relsXml)) {
      final tag = match.group(0)!;
      final idMatch = RegExp(r'Id="([^"]*)"').firstMatch(tag);
      final targetMatch = RegExp(r'Target="([^"]*)"').firstMatch(tag);
      if (idMatch == null || targetMatch == null) continue;
      if (idMatch.group(1) != relId) continue;
      var target = targetMatch.group(1)!;
      if (target.startsWith('/')) {
        target = target.substring(1);
      } else if (!target.startsWith('xl/')) {
        target = 'xl/$target';
      }
      return files.containsKey(target) ? target : null;
    }
    return null;
  }

  /// Injects the print area `definedNames` block in schema order.
  static String? _injectPrintArea(String workbookXml, String printArea) {
    if (workbookXml.contains('_xlnm.Print_Area')) return null;
    // Drop the empty placeholders written by the `excel` package so the
    // workbook keeps a single legal `<definedNames>` element.
    var xml = workbookXml
        .replaceAll('<definedNames/>', '')
        .replaceAll('<definedNames></definedNames>', '');
    final inner = printArea
        .replaceFirst('<definedNames>', '')
        .replaceFirst('</definedNames>', '');
    final existing = xml.indexOf('<definedNames>');
    if (existing >= 0) {
      final close = xml.indexOf('</definedNames>', existing);
      if (close < 0) return null;
      return xml.replaceRange(close, close, inner);
    }
    // `<definedNames>` must precede `<calcPr>` in the workbook schema.
    final insertion = xml.contains('<calcPr')
        ? xml.indexOf('<calcPr')
        : xml.lastIndexOf('</workbook>');
    if (insertion < 0) return null;
    return xml.replaceRange(insertion, insertion, printArea);
  }

  /// Inserts the `<definedNames>` entries produced by [entries] (already
  /// serialised `<definedName>` elements) in the schema-correct position.
  static String? _injectDefinedNames(String workbookXml, String entries) {
    if (entries.isEmpty) return null;
    var xml = workbookXml
        .replaceAll('<definedNames/>', '')
        .replaceAll('<definedNames></definedNames>', '');
    final existing = xml.indexOf('<definedNames>');
    if (existing >= 0) {
      final close = xml.indexOf('</definedNames>', existing);
      if (close < 0) return null;
      // Never duplicate a print area that is already declared for that sheet.
      final body = xml.substring(existing, close);
      final missing = <String>[];
      for (final match in RegExp(r'<definedName\b[^>]*>.*?</definedName>')
          .allMatches(entries)) {
        final element = match.group(0)!;
        final localMatch =
            RegExp(r'localSheetId="(\d+)"').firstMatch(element);
        final marker = localMatch == null
            ? element
            : 'localSheetId="${localMatch.group(1)}"';
        if (localMatch != null && body.contains(marker)) continue;
        missing.add(element);
      }
      if (missing.isEmpty) return null;
      return xml.replaceRange(close, close, missing.join());
    }
    final insertion = xml.contains('<calcPr')
        ? xml.indexOf('<calcPr')
        : xml.lastIndexOf('</workbook>');
    if (insertion < 0) return null;
    return xml.replaceRange(
      insertion,
      insertion,
      '<definedNames>$entries</definedNames>',
    );
  }

  // ---------------------------------------------------------------------------
  // Worksheet.xml patches
  // ---------------------------------------------------------------------------

  /// `<sheetPr>` must be the first child of `<worksheet>`; it carries the
  /// "fit to page" switch.
  static String _injectSheetProperties(String sheetXml) {
    if (sheetXml.contains('<sheetPr')) return sheetXml;
    final openTag = RegExp(r'<worksheet\b[^>]*>').firstMatch(sheetXml);
    if (openTag == null) return sheetXml;
    const properties = '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>';
    return sheetXml.replaceRange(openTag.end, openTag.end, properties);
  }

  /// Freezes the header rows so they stay visible and are repeated on print.
  static String _injectFrozenPane(String sheetXml, {required int freezeRows}) {
    final paneRow = freezeRows + 1;
    final pane = '<pane ySplit="$freezeRows" topLeftCell="A$paneRow" '
        'activePane="bottomLeft" state="frozen"/>';

    final selfClosing = RegExp(r'<sheetView\b[^>]*/>').firstMatch(sheetXml);
    if (selfClosing != null) {
      final tag = selfClosing.group(0)!;
      final openTag = tag.substring(0, tag.length - 2);
      return sheetXml.replaceRange(
        selfClosing.start,
        selfClosing.end,
        '$openTag>$pane</sheetView>',
      );
    }
    if (sheetXml.contains('<pane ')) return sheetXml;
    final openMatch = RegExp(r'<sheetView\b[^>]*>').firstMatch(sheetXml);
    if (openMatch == null) return sheetXml;
    return sheetXml.replaceRange(openMatch.end, openMatch.end, pane);
  }

  /// Adds margins + page setup right before `</worksheet>` (page setup has to
  /// come after every other sheet element).
  static String _injectPageSetup(String sheetXml, {required bool landscape}) {
    if (sheetXml.contains('<pageSetup')) return sheetXml;
    final closeIndex = sheetXml.lastIndexOf('</worksheet>');
    if (closeIndex < 0) return sheetXml;
    final buffer = StringBuffer();
    if (!sheetXml.contains('<pageMargins')) {
      buffer.write('<pageMargins left="0.25" right="0.25" top="0.45" '
          'bottom="0.45" header="0.2" footer="0.2"/>');
    }
    buffer.write(
      '<pageSetup paperSize="9" scale="100" '
      'orientation="${landscape ? 'landscape' : 'portrait'}" '
      'horizontalDpi="300" verticalDpi="300" fitToWidth="1" fitToHeight="0"/>',
    );
    return sheetXml.replaceRange(closeIndex, closeIndex, buffer.toString());
  }

  static String _columnLetter(int index) {
    var current = index;
    final letters = StringBuffer();
    while (current >= 0) {
      letters.write(String.fromCharCode(65 + (current % 26)));
      current = (current ~/ 26) - 1;
    }
    return letters.toString().split('').reversed.join();
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
