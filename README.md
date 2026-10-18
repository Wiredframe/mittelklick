<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# Mittelklick

Mittelklick per Trackpad für macOS, angelehnt an Middle. Eine Menüleisten-App ohne Fenster, ohne Netzwerk, ohne Konto.

## Was es kann

- **Tippen mit drei oder vier Fingern** auf dem Trackpad (eingebaut oder Magic Trackpad) löst einen Mittelklick an der Zeigerposition aus. Standard sind vier Finger.
- **Fn und Linksklick** als Mittelklick, auch zum Ziehen (abschaltbar, standardmäßig aus).
- Menüleiste: Fingeranzahl, Fn-Klick, Beim Anmelden starten, Symbol ausblenden. Ein ausgeblendetes Symbol holt ein erneuter Start von Mittelklick im Finder zurück.

Drei Finger vertragen sich nicht mit „Nachschlagen: Mit drei Fingern tippen“ und „Mit drei Fingern bewegen“ in den Trackpad-Einstellungen von macOS. Vier Finger sind frei.

## Wie es funktioniert

1. Das private `MultitouchSupport.framework` von macOS liefert die rohen Kontakte des Trackpads, Frame für Frame (`MTDeviceCreateList`, `MTRegisterContactFrameCallbackWithRefcon`, `MTDeviceStart`). Mittelklick lädt es zur Laufzeit per `dlopen` (siehe `Sources/MTBridge`).
2. `TapRecognizer` wertet das als Tippen, wenn genau die eingestellte Zahl Finger aufsetzt, sich kaum bewegt (höchstens 4 % der Fläche) und nach spätestens 0,3 s wieder abhebt.
3. `Clicks.middleClick()` erzeugt `otherMouseDown` und `otherMouseUp` mit der mittleren Taste als `CGEvent` und schickt sie ins System.
4. Für Fn und Linksklick schreibt ein `CGEventTap` Linksklicks mit gedrückter Fn-Taste in Mittelklicks um.

Wird ein Magic Trackpad verbunden oder getrennt oder wacht der Mac auf, baut Mittelklick die Geräteliste neu auf.

## Berechtigung

Mittelklick braucht **Bedienungshilfen** (Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen), um Klicks zu senden und Fn-Klicks umzuschreiben. Beim ersten Start fragt macOS danach, sonst steht „Bedienungshilfen erlauben …“ im Menü.

## Privatsphäre

Mittelklick enthält keinen Netzwerkcode:

```sh
otool -L ~/Applications/Mittelklick.app/Contents/MacOS/Mittelklick        # kein CFNetwork, kein Network.framework
nm -u ~/Applications/Mittelklick.app/Contents/MacOS/Mittelklick | grep -i urlsession   # leer
```

Vom Trackpad werden nur Position und Zustand der Kontakte gelesen und sofort verworfen.

## Installation

```sh
brew install --cask wiredframe/tap/mittelklick
```

Oder `Mittelklick-<Version>.zip` unter [Releases](../../releases) laden, entpacken und `Mittelklick.app` nach `/Applications` ziehen. Die App ist signiert, aber nicht notarisiert. Blockiert macOS den ersten Start, hilft „Trotzdem öffnen“ unter Datenschutz & Sicherheit oder:

```sh
xattr -dr com.apple.quarantine /Applications/Mittelklick.app
```

Läuft noch Middle oder eine ähnliche App mit derselben Geste, kommt jeder Mittelklick doppelt an. Dann die andere App beenden und dort „Start beim Login“ abschalten.

## Fehlersuche

Ein Protokoll jeder Geste (Fingerzahl, Dauer, Ergebnis) schaltet man so ein und liest es mit:

```sh
defaults write de.wiredframe.mittelklick debug -bool true   # danach Mittelklick neu starten
log stream --predicate 'subsystem == "de.wiredframe.mittelklick"'
defaults delete de.wiredframe.mittelklick debug             # wieder aus
```

## Bauen

```sh
./build.sh            # baut build/Mittelklick.app (Universal)
./build.sh --install  # zusätzlich nach ~/Applications und starten
./build.sh --zip      # zusätzlich build/Mittelklick-<Version>.zip
```

Ist ein Zertifikat „Developer ID Application“ im Schlüsselbund, signiert `build.sh` damit, sonst ad hoc. Mit fester Signatur bleibt die Bedienungshilfen-Freigabe über Neubauten erhalten, ad hoc muss sie nach jedem Bau neu erteilt werden.

Voraussetzung: Xcode bzw. Swift 5.10+, macOS 14+.

## Lizenz

MIT
