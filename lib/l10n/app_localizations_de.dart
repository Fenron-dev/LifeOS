// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'LifeOS';

  @override
  String get openVault => 'Vault öffnen';

  @override
  String get createVault => 'Neuer Vault';

  @override
  String get recentVaults => 'Zuletzt geöffnet';

  @override
  String get vaultName => 'Vault-Name';

  @override
  String get vaultPath => 'Speicherort';

  @override
  String get vaultSelectFolder => 'Ordner auswählen';

  @override
  String get navItems => 'Artikel';

  @override
  String get navInventory => 'Inventar';

  @override
  String get navRecipes => 'Rezepte';

  @override
  String get navTasks => 'Aufgaben';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get itemsTitle => 'Artikel';

  @override
  String get addItem => 'Artikel hinzufügen';

  @override
  String get editItem => 'Artikel bearbeiten';

  @override
  String get deleteItem => 'Artikel löschen';

  @override
  String get itemName => 'Name';

  @override
  String get itemBrand => 'Marke';

  @override
  String get itemEan => 'EAN / Barcode';

  @override
  String get itemNotes => 'Notizen';

  @override
  String get itemPhotos => 'Fotos';

  @override
  String get itemProductType => 'Produkttyp';

  @override
  String get productTypeReadyToEat => 'Fertiggericht / Konserve / TK';

  @override
  String get productTypeNeedsCooking => 'Muss zubereitet werden';

  @override
  String get productTypeIngredient => 'Zutat / Gewürz';

  @override
  String get itemAlwaysConsumedFully => 'Immer komplett verbraucht';

  @override
  String get itemOpenedFlag => 'Bleibt nach Öffnen vorhanden';

  @override
  String get inventoryTitle => 'Inventar';

  @override
  String get quantity => 'Menge';

  @override
  String get unit => 'Einheit';

  @override
  String get location => 'Lagerort';

  @override
  String get expiryDate => 'Ablaufdatum';

  @override
  String get state => 'Zustand';

  @override
  String get stateFresh => 'Frisch';

  @override
  String get stateFrozen => 'Eingefroren';

  @override
  String get stateThawed => 'Aufgetaut';

  @override
  String get recipesTitle => 'Rezepte';

  @override
  String get addRecipe => 'Rezept hinzufügen';

  @override
  String get recipeIngredients => 'Zutaten';

  @override
  String get recipeSteps => 'Zubereitung';

  @override
  String get recipeNutrition => 'Nährwerte';

  @override
  String get recipeVideo => 'Video';

  @override
  String get importFromMealie => 'Aus Mealie importieren';

  @override
  String get tasksTitle => 'Aufgaben';

  @override
  String get addTask => 'Aufgabe hinzufügen';

  @override
  String get taskRecurring => 'Wiederkehrend';

  @override
  String get wishlistTitle => 'Wunschliste';

  @override
  String get addWish => 'Wunsch hinzufügen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsTheme => 'Design';

  @override
  String get themeSystem => 'Systemstandard';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get scanBarcode => 'Barcode scannen';

  @override
  String get searchOpenFoodFacts => 'OpenFoodFacts durchsuchen';

  @override
  String get consumeItem => 'Verbrauch erfassen';

  @override
  String get consumeViaMeal => 'Standard-Mahlzeit wählen';

  @override
  String get addPurchase => 'Kauf erfassen';

  @override
  String get stocktake => 'Inventur';

  @override
  String get tags => 'Tags';

  @override
  String get addTag => 'Tag hinzufügen';

  @override
  String get automationTitle => 'Automatisierungen';

  @override
  String get addAutomation => 'Neue Regel';

  @override
  String get triggerManual => 'Manuell';

  @override
  String get triggerScheduled => 'Zeit-basiert';

  @override
  String get triggerEvent => 'Ereignis';

  @override
  String get triggerThreshold => 'Schwellwert';

  @override
  String get save => 'Speichern';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get add => 'Hinzufügen';

  @override
  String get search => 'Suchen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get errorGeneric => 'Ein Fehler ist aufgetreten';

  @override
  String get noItemsFound => 'Keine Einträge gefunden';

  @override
  String get loading => 'Wird geladen...';

  @override
  String get expiryNotificationTitle => 'Ablaufdatum';

  @override
  String expiryNotificationBodyExpired(String itemName) {
    return '$itemName ist abgelaufen!';
  }

  @override
  String expiryNotificationBodySoon(String itemName, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tagen',
      one: '1 Tag',
    );
    return '$itemName läuft in $_temp0 ab.';
  }
}
