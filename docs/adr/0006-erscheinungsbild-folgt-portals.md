# 6. Das Erscheinungsbild folgt dem Projekt portals

Status: entschieden, umgesetzt beim Angleichen der Oberfläche

## Worum es geht

Hermes und portals werden von denselben Leuten betrieben und nebeneinander
benutzt. Zwei eigene Gestaltungen nebeneinander kosten bei jeder Änderung
zweimal Nachdenken – und wer zwischen beiden wechselt, muss sich zweimal
zurechtfinden.

Zusätzlich war die Akzentfarbe bisher pro Installation wählbar: sechs gedeckte
Töne in den Einstellungen, gespeichert in der Datenbank und als `<style>` in den
Seitenkopf geschrieben.

## Entscheidung

Die Palette von portals gilt auch in Hermes: Tailwinds Grautöne für Flächen und
Text, das Mint `#22948c` (Hover `#00b5ad`) als einzige Akzentfarbe. Karten sind
gefüllt und werfen einen Schatten, die Kopfzeile trägt Unterstrich-Reiter, die
Tabellen haben einen ruhigen Kopf und Haarlinien statt Zebrastreifen.

Die Akzentwahl entfällt ersatzlos. Die Farben stehen in `assets/css/app.css`,
die Spalte `settings.accent` ist per Migration entfernt.

Gleich geblieben ist daisyUI als Komponentenbasis. Die Angleichung passiert
über dessen Theme-Tokens und ein paar eigene Regeln, nicht durch neu
geschriebene Komponenten – die Oberfläche ist an einer Stelle beschrieben statt
in fünfzehn LiveViews verstreut.

## Warum

- **Ein Blick, zwei Anwendungen.** Wer portals kennt, findet sich in Hermes
  sofort zurecht.
- **Eine Farbe kann nicht falsch gewählt werden.** Bei freier Wahl entsteht
  früher oder später eine Kombination, die in einem der beiden Themes schlecht
  lesbar ist. Was es nicht gibt, muss auch nicht geprüft werden.
- **Weniger Zustand.** Die Farbe war ein Datenbankfeld, ein Formularfeld, ein
  `<style>`-Block im Seitenkopf und ein Testfall. Jetzt ist sie eine Zeile CSS.

## Womit wir leben

- Eine Installation lässt sich nicht mehr an der Farbe auseinanderhalten. Dafür
  bleiben Name und Logo, die den Kunden ohnehin deutlicher kennzeichnen.
- Inter wird **nicht** geladen, obwohl portals das tut. Eine Installation steht
  im LAN des Kunden und hat womöglich gar keinen Weg ins Internet; die
  Schriftliste nennt Inter zuerst und fällt sonst auf die Systemschrift zurück.
- Der Theme-Schalter kennt nur noch hell und dunkel, wie in portals. Bis jemand
  wählt, gilt weiterhin die Einstellung des Browsers.
