# RAGAA Daily Journal Design

## Intent

Extend the existing single-total collection record into the seven financial
fields used by the paper daily journal, while preserving every existing record,
its duplicate guard, audit history, reporting, and backup behavior.

## Goals

- Store manual fees, automatic fees, independently entered total fees, general
  total, optional NFC and VISA, and derived scales total as integer piastres.
- Derive scales total centrally as `generalTotal - totalFees`; never add NFC or
  VISA to a total a second time.
- Export a dynamic, RTL daily-journal layout grouped by shifts and then by each
  outlet's daily total, with the paper form's yellow total rows and bordered
  cells. Exclude delivery/remainder fields and the green five-outlet block.
- Safely migrate legacy records: their recorded amount becomes general total;
  new values default to zero.

## Constraints

- Work only in the existing RAGAA repository and `feature/phase-2-complete`.
- Preserve existing data, audit logs, duplicate prevention, reports, backups,
  Arabic RTL, and exports.
- Use SQLite forward-only migration and integer piastres for all money.

## Approach

Keep the existing `collections` identity and scheduling snapshots, add monetary
columns in schema version 2, and retain `amount_piastres` as a compatibility
mirror of `general_total_piastres`. A `CollectionAmounts` value object owns
validation and the approved derived formula. Repository and controller APIs
accept that object; the form shows each amount explicitly. A dedicated daily
journal report projection is shared by PDF and Excel exporters.

## Non-goals

No delivery, administrative receipt, supervisory receipt, remainder, or
paper-form green subtotal workflow is introduced.
