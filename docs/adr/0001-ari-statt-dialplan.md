# 1. Anruflogik in Elixir über ARI, nicht im Asterisk-Wählplan

Status: entschieden, umgesetzt in M4/M5

## Worum es geht

Die Logik eines Anrufs — wer hat Dienst, wen rufe ich an, was passiert bei
Taste 2, wann eskaliere ich — muss irgendwo leben. Asterisk bietet dafür zwei
Wege: den eigenen Wählplan (`extensions.conf`, notfalls mit AGI-Skripten) oder
die Steuerung von außen über die Asterisk REST Interface (ARI).

## Entscheidung

Die gesamte Logik liegt als Elixir-Code in Hermes. Asterisk führt nur aus, was
ihm gesagt wird: Kanal erzeugen, wählen, Ansage abspielen, zwei Kanäle
verbinden. Der Wählplan umfasst am Ende weniger als zehn Zeilen und reicht den
Anruf direkt an die Anwendung weiter.

## Warum

- **Testbarkeit.** Die Anruflogik läuft in Tests gegen einen Mock von Asterisk.
  Alle Wege — Taste 1, 2, 3, Mobilbox, besetzt, Anrufer legt auf, zwei Anrufe
  gleichzeitig — sind ohne Telefonanlage prüfbar. Im Wählplan wäre davon
  nichts automatisiert testbar.
- **Der Dienstplan ist Anwendungslogik.** Schichten, Ausnahmen, Zeitumstellung:
  Das gehört in eine Programmiersprache mit Datenbank, nicht in Makros.
- **Ein Prozess je Anruf.** Elixir gibt jedem Anruf einen eigenen Prozess mit
  eigenem Zustand. Stürzt einer ab, laufen die anderen weiter. Belegte Personen
  und Leitungskanäle werden über eine Registry reserviert, die beim Prozessende
  automatisch freigibt — kein Aufräum-Job, keine hängenden Reservierungen.
- **Fehler sind sichtbar.** Ein fehlgeschlagener ARI-Aufruf ist ein Rückgabewert,
  auf den reagiert wird, statt einer stillen Verzweigung im Wählplan.

## Womit wir leben

- Hermes muss laufen, damit Anrufe angenommen werden. Fällt die Anwendung aus,
  klingelt niemand. Deshalb überwacht `Hermes.Telephony.Monitor` die Verbindung
  und zeigt den Zustand in der Oberfläche; für den Notfall schaltet
  `HERMES_CALL_MODE=test` Asterisk auf eine eigene Ansage um, ganz ohne App.
- Zwei Systeme statt einem. Dafür ist jedes davon einfach.
