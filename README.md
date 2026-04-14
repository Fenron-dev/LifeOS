# LifeOS

**Local-First Household & Life Management System**

A Flutter application for managing groceries, inventory, recipes, appliances, tasks, and wish lists — across Android and Linux/Windows desktops with optional WiFi sync.

## Features

- **Inventory management** — track products with quantity, unit, expiry date, and storage location
- **Barcode scanning** — EAN lookup via OpenFoodFacts, instant product identification
- **Event sourcing** — immutable event log (purchases, consumption, stocktakes) with materialized state
- **Recipes** — manage recipes with ingredients and steps, Mealie import (Phase 3)
- **Tasks & wish list** — household todos and shopping wish list
- **Vault system** — entire app state lives in a folder; backup = copy folder
- **Adaptive UI** — BottomNav (mobile) / NavigationRail (tablet) / 3-panel sidebar (desktop)
- **WiFi sync** — desktop acts as HTTP server; Android syncs events over local network (Phase 5)

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter + Material 3 |
| State | Riverpod 2 (code-gen) |
| Database | Drift ORM (SQLite, WAL mode) |
| Navigation | go_router |
| Sync server | shelf (optional, desktop only) |
| Barcode | mobile_scanner |
| Notifications | flutter_local_notifications |

## Getting Started

```bash
# 1. Install dependencies
flutter pub get

# 2. Generate Drift query code (after schema changes)
dart run build_runner build --delete-conflicting-outputs

# 3. Run
flutter run -d linux          # Desktop (Linux)
flutter run                   # Android / auto-detect
```

## Build

```bash
flutter build apk --release   # Android APK
flutter build linux --release # Linux bundle
```

## Architecture

### Vault System

All app state lives in a single folder on disk:

```
~/lifeos-haushalt/
├── lifeos.db     ← all data (Drift/SQLite)
├── photos/       ← UUID-named image files
├── exports/      ← JSON exports, PDFs
└── cache/        ← thumbnails (disposable)
```

Backup = copy folder. No special export needed.

### Event Sourcing

All inventory changes are **events** (append-only, immutable):

```
item_events  →  (projection)  →  item_states
(source of truth)                (fast read cache)
```

### Data Flow

```
Drift Tables → AppDatabase methods → Riverpod Providers → UI Widgets
```

## Development Phases

| Phase | Status | Scope |
|---|---|---|
| 0 | ✅ Done | Vault, schema, adaptive shell, i18n |
| 1 | ✅ Done | Products, barcode, EAN lookup, inventory CRUD |
| 2 | ✅ Done | Event log, stock operations, locations, item detail |
| 3 | 🔄 Next | Recipes, nutrition, item groups, standard meals |
| 4 | ⏳ Planned | Custom categories, If→Then automation |
| 5 | ⏳ Planned | Desktop-as-server WiFi sync |

## i18n

Primary language: **German** (`lib/l10n/app_de.arb`)
Secondary: **English** (`lib/l10n/app_en.arb`)

## License

MIT
