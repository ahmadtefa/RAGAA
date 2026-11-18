import '../models/collection_record.dart';

/// Base domain exception carrying an Arabic user-facing message.
class RagaaException implements Exception {
  final String message;
  const RagaaException(this.message);

  @override
  String toString() => message;
}

/// Thrown when user input or domain invariants fail validation.
class ValidationException extends RagaaException {
  const ValidationException(super.message);
}

/// Thrown when attempting to insert a collection for an already-recorded
/// (outlet, operationalDate, shiftNumber) tuple.
class DuplicateCollectionException extends RagaaException {
  final CollectionRecord existing;

  const DuplicateCollectionException(
    this.existing, [
    super.message = 'يوجد تحصيل مسجل بالفعل لهذا المنفذ والوردية والتاريخ التشغيلي',
  ]);
}

/// Thrown when a backup file fails integrity, checksum, or schema validation.
class BackupIntegrityException extends RagaaException {
  const BackupIntegrityException(super.message);
}
