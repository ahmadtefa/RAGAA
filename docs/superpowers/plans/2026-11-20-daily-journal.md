# Daily Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely capture and export the paper daily journal's financial fields.

**Architecture:** Add immutable integer-piastre monetary fields and a schema-v2 migration; use one central derived formula; project records into a dynamic daily journal consumed by the entry UI, PDF, and Excel exports.

**Tech Stack:** Flutter Desktop, Dart, SQLite, `pdf`, `excel`, Flutter tests.

**Spec:** `docs/superpowers/specs/2026-11-20-daily-journal-design.md`

## Global Constraints

- `scales = general total - total fees`; total fees is independently entered.
- NFC/VISA default to zero and are already components of general total.
- Never delete or overwrite legacy records; migration defaults added values to zero.

## Review Focus

- Migration of an existing v1 database retains its old total as general total.
- Empty NFC/VISA are valid zero values.
- Editing total fees or general total immediately changes derived scales.
- Shift and daily totals do not count payment methods twice.
- A two-shift outlet never gains a fabricated third-shift entry.

### Task 1: Monetary domain model and migration

**Files:** `lib/models/collection_amounts.dart`, `lib/models/collection_record.dart`, `lib/data/app_database.dart`, repository tests.

- [ ] Write failing tests for the mandatory formula, optional payment values, and v1 migration.
- [ ] Add the value object and schema v2 columns with a forward-only migration.
- [ ] Run the targeted tests and commit.

### Task 2: Repository and entry workflow

**Files:** `lib/data/ragaa_repository.dart`, `lib/state/ragaa_controller.dart`, `lib/ui/widgets/collection_form_dialog.dart`, repository tests.

- [ ] Write failing tests for creating/updating all seven fields and audit snapshots.
- [ ] Thread `CollectionAmounts` through persistence, query, controller, and form UI.
- [ ] Run targeted and full tests and commit.

### Task 3: Daily journal report and exports

**Files:** report models, repository, PDF/Excel services, export tests.

- [ ] Write failing tests for shift, outlet-daily, and grand totals.
- [ ] Build a dynamic journal projection and render it in landscape RTL PDF/Excel.
- [ ] Generate sample exports, inspect their bytes/sheets, run full verification, and commit.
