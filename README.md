# WEGA VIN Timer

WEGA VIN Timer to fundament produkcyjnej aplikacji mobilnej Flutter dla Androida i iOS, przeznaczonej do lokalnego monitorowania czasu aktywnych pojazdów po numerze VIN.

## Wymagania środowiska

- Flutter SDK 3.22 lub nowszy
- Dart SDK 3.4 lub nowszy
- Android SDK z API 35; aplikacja wspiera minimum Android API 24
- Xcode dla iOS; aplikacja wspiera minimum iOS 13

## Uruchomienie

```bash
flutter pub get
flutter run
```

## Testy i jakość

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

## Architektura katalogów

- `lib/core` — stałe biznesowe, walidacja VIN, routing, powiadomienia lokalne.
- `lib/domain` — encje i polityki domenowe niezależne od UI.
- `lib/application` — providery Riverpod i przypadki użycia.
- `lib/data` — lokalna baza Drift dla operatorów, aktywnych pojazdów, historii i audytu.
- `lib/presentation` — ekrany logowania, listy pojazdów, dodania VIN, szczegółów, historii i ustawień.
- `test` — testy jednostkowe reguł domenowych.

## Zakres v0.1.0

- Lokalne uproszczone logowanie operatora.
- Walidacja i normalizacja VIN.
- Reguły ostrzeżenia po 35 minutach, alarmu po 40 minutach i limitu 100 aktywnych pojazdów.
- Schemat lokalnej bazy danych z tabelami operatorów, aktywnych pojazdów, historii i dziennika audytowego.
- Konfiguracja GitHub Actions dla pobrania zależności, formatowania, analizy, testów i debug APK.

## Ograniczenia aktualnej wersji

Nie zaimplementowano jeszcze OCR, skanowania kodów, alarmów działających w tle, eksportu, serwera, panelu administratora ani synchronizacji. Ekrany są fundamentem UI i będą zasilane pełnymi repozytoriami danych w kolejnych iteracjach.
