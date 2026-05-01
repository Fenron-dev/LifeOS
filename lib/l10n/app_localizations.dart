import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// App name
  ///
  /// In de, this message translates to:
  /// **'LifeOS'**
  String get appName;

  /// No description provided for @openVault.
  ///
  /// In de, this message translates to:
  /// **'Vault öffnen'**
  String get openVault;

  /// No description provided for @createVault.
  ///
  /// In de, this message translates to:
  /// **'Neuer Vault'**
  String get createVault;

  /// No description provided for @recentVaults.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt geöffnet'**
  String get recentVaults;

  /// No description provided for @vaultName.
  ///
  /// In de, this message translates to:
  /// **'Vault-Name'**
  String get vaultName;

  /// No description provided for @vaultPath.
  ///
  /// In de, this message translates to:
  /// **'Speicherort'**
  String get vaultPath;

  /// No description provided for @vaultSelectFolder.
  ///
  /// In de, this message translates to:
  /// **'Ordner auswählen'**
  String get vaultSelectFolder;

  /// No description provided for @navItems.
  ///
  /// In de, this message translates to:
  /// **'Artikel'**
  String get navItems;

  /// No description provided for @navInventory.
  ///
  /// In de, this message translates to:
  /// **'Inventar'**
  String get navInventory;

  /// No description provided for @navRecipes.
  ///
  /// In de, this message translates to:
  /// **'Rezepte'**
  String get navRecipes;

  /// No description provided for @navTasks.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get navTasks;

  /// No description provided for @navSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get navSettings;

  /// No description provided for @itemsTitle.
  ///
  /// In de, this message translates to:
  /// **'Artikel'**
  String get itemsTitle;

  /// No description provided for @addItem.
  ///
  /// In de, this message translates to:
  /// **'Artikel hinzufügen'**
  String get addItem;

  /// No description provided for @editItem.
  ///
  /// In de, this message translates to:
  /// **'Artikel bearbeiten'**
  String get editItem;

  /// No description provided for @deleteItem.
  ///
  /// In de, this message translates to:
  /// **'Artikel löschen'**
  String get deleteItem;

  /// No description provided for @itemName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get itemName;

  /// No description provided for @itemBrand.
  ///
  /// In de, this message translates to:
  /// **'Marke'**
  String get itemBrand;

  /// No description provided for @itemEan.
  ///
  /// In de, this message translates to:
  /// **'EAN / Barcode'**
  String get itemEan;

  /// No description provided for @itemNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get itemNotes;

  /// No description provided for @itemPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get itemPhotos;

  /// No description provided for @itemProductType.
  ///
  /// In de, this message translates to:
  /// **'Produkttyp'**
  String get itemProductType;

  /// No description provided for @productTypeReadyToEat.
  ///
  /// In de, this message translates to:
  /// **'Fertiggericht / Konserve / TK'**
  String get productTypeReadyToEat;

  /// No description provided for @productTypeNeedsCooking.
  ///
  /// In de, this message translates to:
  /// **'Muss zubereitet werden'**
  String get productTypeNeedsCooking;

  /// No description provided for @productTypeIngredient.
  ///
  /// In de, this message translates to:
  /// **'Zutat / Gewürz'**
  String get productTypeIngredient;

  /// No description provided for @itemAlwaysConsumedFully.
  ///
  /// In de, this message translates to:
  /// **'Immer komplett verbraucht'**
  String get itemAlwaysConsumedFully;

  /// No description provided for @itemOpenedFlag.
  ///
  /// In de, this message translates to:
  /// **'Bleibt nach Öffnen vorhanden'**
  String get itemOpenedFlag;

  /// No description provided for @inventoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Inventar'**
  String get inventoryTitle;

  /// No description provided for @quantity.
  ///
  /// In de, this message translates to:
  /// **'Menge'**
  String get quantity;

  /// No description provided for @unit.
  ///
  /// In de, this message translates to:
  /// **'Einheit'**
  String get unit;

  /// No description provided for @location.
  ///
  /// In de, this message translates to:
  /// **'Lagerort'**
  String get location;

  /// No description provided for @expiryDate.
  ///
  /// In de, this message translates to:
  /// **'Ablaufdatum'**
  String get expiryDate;

  /// No description provided for @state.
  ///
  /// In de, this message translates to:
  /// **'Zustand'**
  String get state;

  /// No description provided for @stateFresh.
  ///
  /// In de, this message translates to:
  /// **'Frisch'**
  String get stateFresh;

  /// No description provided for @stateFrozen.
  ///
  /// In de, this message translates to:
  /// **'Eingefroren'**
  String get stateFrozen;

  /// No description provided for @stateThawed.
  ///
  /// In de, this message translates to:
  /// **'Aufgetaut'**
  String get stateThawed;

  /// No description provided for @recipesTitle.
  ///
  /// In de, this message translates to:
  /// **'Rezepte'**
  String get recipesTitle;

  /// No description provided for @addRecipe.
  ///
  /// In de, this message translates to:
  /// **'Rezept hinzufügen'**
  String get addRecipe;

  /// No description provided for @recipeIngredients.
  ///
  /// In de, this message translates to:
  /// **'Zutaten'**
  String get recipeIngredients;

  /// No description provided for @recipeSteps.
  ///
  /// In de, this message translates to:
  /// **'Zubereitung'**
  String get recipeSteps;

  /// No description provided for @recipeNutrition.
  ///
  /// In de, this message translates to:
  /// **'Nährwerte'**
  String get recipeNutrition;

  /// No description provided for @recipeVideo.
  ///
  /// In de, this message translates to:
  /// **'Video'**
  String get recipeVideo;

  /// No description provided for @importFromMealie.
  ///
  /// In de, this message translates to:
  /// **'Aus Mealie importieren'**
  String get importFromMealie;

  /// No description provided for @tasksTitle.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get tasksTitle;

  /// No description provided for @addTask.
  ///
  /// In de, this message translates to:
  /// **'Aufgabe hinzufügen'**
  String get addTask;

  /// No description provided for @taskRecurring.
  ///
  /// In de, this message translates to:
  /// **'Wiederkehrend'**
  String get taskRecurring;

  /// No description provided for @wishlistTitle.
  ///
  /// In de, this message translates to:
  /// **'Wunschliste'**
  String get wishlistTitle;

  /// No description provided for @addWish.
  ///
  /// In de, this message translates to:
  /// **'Wunsch hinzufügen'**
  String get addWish;

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In de, this message translates to:
  /// **'Design'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In de, this message translates to:
  /// **'Systemstandard'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeDark;

  /// No description provided for @scanBarcode.
  ///
  /// In de, this message translates to:
  /// **'Barcode scannen'**
  String get scanBarcode;

  /// No description provided for @searchOpenFoodFacts.
  ///
  /// In de, this message translates to:
  /// **'OpenFoodFacts durchsuchen'**
  String get searchOpenFoodFacts;

  /// No description provided for @consumeItem.
  ///
  /// In de, this message translates to:
  /// **'Verbrauch erfassen'**
  String get consumeItem;

  /// No description provided for @consumeViaMeal.
  ///
  /// In de, this message translates to:
  /// **'Standard-Mahlzeit wählen'**
  String get consumeViaMeal;

  /// No description provided for @addPurchase.
  ///
  /// In de, this message translates to:
  /// **'Kauf erfassen'**
  String get addPurchase;

  /// No description provided for @stocktake.
  ///
  /// In de, this message translates to:
  /// **'Inventur'**
  String get stocktake;

  /// No description provided for @tags.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @addTag.
  ///
  /// In de, this message translates to:
  /// **'Tag hinzufügen'**
  String get addTag;

  /// No description provided for @automationTitle.
  ///
  /// In de, this message translates to:
  /// **'Automatisierungen'**
  String get automationTitle;

  /// No description provided for @addAutomation.
  ///
  /// In de, this message translates to:
  /// **'Neue Regel'**
  String get addAutomation;

  /// No description provided for @triggerManual.
  ///
  /// In de, this message translates to:
  /// **'Manuell'**
  String get triggerManual;

  /// No description provided for @triggerScheduled.
  ///
  /// In de, this message translates to:
  /// **'Zeit-basiert'**
  String get triggerScheduled;

  /// No description provided for @triggerEvent.
  ///
  /// In de, this message translates to:
  /// **'Ereignis'**
  String get triggerEvent;

  /// No description provided for @triggerThreshold.
  ///
  /// In de, this message translates to:
  /// **'Schwellwert'**
  String get triggerThreshold;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @search.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get search;

  /// No description provided for @confirm.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get confirm;

  /// No description provided for @yes.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get no;

  /// No description provided for @errorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Ein Fehler ist aufgetreten'**
  String get errorGeneric;

  /// No description provided for @noItemsFound.
  ///
  /// In de, this message translates to:
  /// **'Keine Einträge gefunden'**
  String get noItemsFound;

  /// No description provided for @loading.
  ///
  /// In de, this message translates to:
  /// **'Wird geladen...'**
  String get loading;

  /// Title for expiry-warning local notifications
  ///
  /// In de, this message translates to:
  /// **'Ablaufdatum'**
  String get expiryNotificationTitle;

  /// Body shown when an item is already past its expiry date
  ///
  /// In de, this message translates to:
  /// **'{itemName} ist abgelaufen!'**
  String expiryNotificationBodyExpired(String itemName);

  /// Body shown when an item is about to expire
  ///
  /// In de, this message translates to:
  /// **'{itemName} läuft in {days, plural, =1{1 Tag} other{{days} Tagen}} ab.'**
  String expiryNotificationBodySoon(String itemName, int days);

  /// No description provided for @quickActionAddInventory.
  ///
  /// In de, this message translates to:
  /// **'Einlagern'**
  String get quickActionAddInventory;

  /// No description provided for @quickActionConsumeInventory.
  ///
  /// In de, this message translates to:
  /// **'Ausbuchen'**
  String get quickActionConsumeInventory;

  /// No description provided for @quickActionAddTask.
  ///
  /// In de, this message translates to:
  /// **'Aufgabe'**
  String get quickActionAddTask;

  /// No description provided for @quickActionAddWishlist.
  ///
  /// In de, this message translates to:
  /// **'Wunschliste'**
  String get quickActionAddWishlist;

  /// No description provided for @quickActionAddRecipe.
  ///
  /// In de, this message translates to:
  /// **'Rezept'**
  String get quickActionAddRecipe;

  /// No description provided for @quickActionScanBarcode.
  ///
  /// In de, this message translates to:
  /// **'Barcode scannen'**
  String get quickActionScanBarcode;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
