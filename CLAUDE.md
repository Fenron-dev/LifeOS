# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LifeOS** is a local-first household & life management system (Flutter/Dart) for managing groceries, inventory, recipes, appliances, tasks, and wish lists. Full specification: [Projektkonzept - Local-First Household & Life Management System.md](Projektkonzept%20-%20Local-First%20Household%20%26%20Life%20Management%20System.md).

## Development Commands

```bash
# Setup (after cloning)
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Run
flutter run -d linux          # Desktop (Linux)
flutter run -d macos          # Desktop (macOS)
flutter run                   # Auto-detect (Android/emulator)

# Code generation (after schema changes in lib/db/database.dart)
dart run build_runner build --delete-conflicting-outputs

# Build
flutter build linux --release
flutter build macos --release --no-tree-shake-icons --enable-experiment=native-assets
flutter build windows --release --no-tree-shake-icons   # requires Windows machine
flutter build apk --release

# Run single test
flutter test test/path/to/test_file.dart
```

## Tech Stack

- **Flutter + Dart** — single codebase for Android + Linux/Windows/macOS
- **Drift ORM** — SQLite with type-safe queries and migrations
- **Riverpod 2** — state management (code-gen providers via `@riverpod`)
- **go_router** — navigation
- **shelf** — optional local HTTP server (Desktop acts as sync server)
- **mobile_scanner** — barcode/EAN scanning
- **flutter_local_notifications** — expiry and stock alerts

## Architecture

### Vault System (critical concept)
A **Vault** = a folder on disk. The entire app state lives in that folder:
```
~/lifeos-haushalt/
├── lifeos.db     ← all data
├── photos/       ← UUID-named photo files
├── exports/      ← JSON exports, PDFs
└── cache/        ← thumbnails (disposable, no backup needed)
```
- `lib/core/vault_manager.dart` — opens/switches vaults, exposes DB path
- `vaultProvider` (Riverpod) — current vault path; cascades to `databaseProvider`
- Backup = copy folder. No special backup feature needed for the folder itself.

### Data Flow
```
Drift Tables → DAOs → Repository → Riverpod Providers → UI Widgets
```
- `lib/db/database.dart` — all table definitions and migrations (single source of truth)
- `lib/db/daos/` — one DAO per domain (items, events, recipes, tasks...)
- `lib/providers/` — Riverpod providers, one file per domain
- `lib/screens/` — screens organized by feature
- `lib/widgets/` — reusable widgets

### Event-Sourcing Pattern
- All inventory changes are **Events** (immutable, append-only): purchases, consumption, stocktakes, state changes
- `item_states` table is a **materialized projection** of events (for fast queries) — always recomputable from events
- Every event has `device_id` + `synced_at` for future sync support

### Core Domain Tables
| Table | Purpose |
|-------|---------|
| `items` | All objects (products, appliances, wish list entries) |
| `item_events` | Immutable event log (purchases, consumption, etc.) |
| `item_states` | Materialized projection for fast reads |
| `item_groups` | Logical groupings with min-stock rules |
| `locations` | Hierarchical storage locations |
| `tag_definitions` | Tags scoped per category (food tags ≠ electronics tags) |
| `item_tags` | Many-to-many items ↔ tags |
| `category_definitions` | Custom user categories (Phase 4) |
| `item_properties` | Values for custom category fields (Phase 4) |
| `recipes` | Recipe entries with ingredients and steps |
| `standard_meals` | Consumption templates (e.g., "Breakfast = ...") |
| `automation_rules` | If→Then automation rules |

### Adaptive Shell
- `lib/widgets/adaptive_shell.dart` — single entry point for all layouts
- Mobile < 600px: `BottomNavigationBar`
- Tablet 600–1200px: `NavigationRail` + content + split-view for recipes
- Desktop ≥ 1200px: 3-panel (Sidebar | Main | Detail) + MenuBar + keyboard shortcuts

### Sync Architecture
Desktop app optionally runs an HTTP server (Dart `shelf`). Android syncs events via WiFi:
- Pull: `GET /events?since=<timestamp>&device_id=<id>`
- Push: `POST /events` (batch)
- Conflict: last-event-wins per item (by `created_at`)

## Key Design Decisions

- **Vault portability**: photo paths are always relative to vault root — never absolute
- **Category-scoped tags**: tags belong to a `category_id`; never mix food tags with electronics tags
- **productType enum**: `readyToEat` | `needsCooking` | `ingredient` — drives consumption UI behavior
- **alwaysConsumedFully**: if true, scanning consumption marks item fully consumed
- **openedFlag**: "is product still countable when opened?" — affects min-stock calculation
- **Smart tara**: `containerItemId` on item → auto-links default container on "open" event

## MVP Development Phases

| Phase | Scope |
|-------|-------|
| 0 | Vault system, Drift schema, Adaptive Shell, i18n |
| 1 | Products + barcode, inventory, expiration, events, backup |
| 2 | Groups + min-stock, consumption templates, smart tara, tags, shopping list |
| 3 | Recipes + Mealie import, nutrition, tablet split-view, wish list |
| 4 | Custom categories, If→Then automation, vault cross-links |
| 5 | Desktop-as-server sync for Android |

## i18n

- Primary language: German (`l10n/app_de.arb`)
- Secondary: English (`l10n/app_en.arb`)
- Always use `AppLocalizations.of(context)!.someKey` — never hardcode German strings

## Reusable Code from Sister Projects

- **Barcode scanner**: copy from `../pomtechflow_mobile/lib/screens/scanner/barcode_scanner_screen.dart`
- **Notification service**: copy from `../pomtechflow_mobile/lib/services/notification_service.dart`
- **Backup service pattern**: `../pomtechflow_mobile/lib/services/backup_service.dart`
- **Thumbnail isolate**: copy from `../MediaShelf/lib/data/thumbnailer/thumbnailer.dart`
- **Vault/library open pattern**: `../MediaShelf/lib/providers/` (`libraryPathProvider`, `databaseProvider`)
- **Adaptive shell pattern**: `../pomtechflow_mobile/lib/widgets/adaptive_shell.dart`
