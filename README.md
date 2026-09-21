# Hermes

Anrufe auf eine Festnetznummer landen automatisch beim Handy der Person, die
gerade Bereitschaft hat — ohne dass der Anrufer deren Nummer je zu sehen bekommt.
Wer wann Dienst hat, wird in einem Wochenplan im Browser gepflegt. Ist niemand
eingetragen oder nimmt niemand ab, hört der Anrufer eine gesprochene Ansage
statt ins Leere zu laufen.

Hermes läuft als `docker compose`-Stack auf einem kleinen Linux-Rechner im
selben Netz wie die Fritz!Box. Eine Installation gehört zu einem Kunden;
konfiguriert wird alles über die Weboberfläche.

## Wie ein Anruf abläuft

1. Jemand ruft die Festnetznummer an. Die Fritz!Box lässt Hermes klingeln, das
   dort als IP-Telefon angemeldet ist.
2. Hermes schaut im Wochenplan nach, wer gerade Dienst hat, und ruft deren
   Handy an — als Absender erscheint die Festnetznummer.
3. Der Anrufer hört währenddessen nur Rufton. Sein Anruf wird bewusst noch
   nicht angenommen.
4. Nimmt die Person ab, hört **nur sie** eine kurze Ansage:
   - **1** — annehmen, das Gespräch wird verbunden
   - **2** — weitergeben, die nächste Person wird sofort gerufen
   - **3** — abweisen, der Anruf endet für alle
5. Drückt niemand eine Taste (typisch, wenn die Mobilbox abhebt), geht es zur
   nächsten Person. Sind alle durch, kommt die Ansage.

Dass erst eine Taste gedrückt werden muss, ist der Kern: Eine Mobilbox drückt
keine Taste. Deshalb landet ein Anrufer nie auf der privaten Mailbox einer
diensthabenden Person.

## Erste Installation

Voraussetzungen: Linux-Rechner mit Docker und Docker Compose, im selben Netz
wie die Fritz!Box.

```sh
git clone <repository> hermes && cd hermes
bin/setup                          # legt .env mit frischen Passwörtern an
# Fritz!Box-Zugangsdaten in .env eintragen, siehe docs/fritzbox.md
docker compose up -d --build
docker compose exec -it app bin/create_admin du@example.com
```

Danach die Weboberfläche öffnen (standardmäßig <http://localhost:4000>) und
der Reihe nach einrichten: angezeigte Rufnummer, Personen, Wochenplan. Die
Übersichtsseite führt durch diese Schritte.

Ausführlich: **[docs/rollout.md](docs/rollout.md)** für eine komplette
Installation beim Kunden, **[docs/fritzbox.md](docs/fritzbox.md)** für die
Fritz!Box.

## Die Weboberfläche

| Seite | Wofür |
|---|---|
| Übersicht | Wer hat jetzt Dienst, nächster Wechsel, Zustand der Telefonanlage |
| Wochenplan | Schichten ziehen; Ausnahmen für Urlaub und Tausch |
| Anrufe | Was aus jedem Anruf wurde, mit jedem einzelnen Versuch |
| Personen | Wer angerufen werden kann (Handy oder interne Nebenstelle) |
| Einstellungen | Angezeigte Rufnummer, Klingeln, Ansagen, Aufbewahrungsfrist |
| Benutzer | Wer sich anmelden darf |

## Betrieb

```sh
docker compose ps                              # läuft alles?
docker compose logs -f app                     # Anrufe mitverfolgen
docker compose exec asterisk asterisk -rx "pjsip show registrations"
curl -s localhost:4000/healthz                 # Zustand als JSON
bin/backup                                     # Datenbank + Ansagen sichern
bin/restore backups/hermes-db-….sql.gz         # zurückspielen
docker compose exec -it app bin/create_admin …     # Benutzer anlegen
docker compose exec -it app bin/reset_password …   # Passwort zurücksetzen
```

Die Systemseite unter `/system` zeigt Prozesse, Speicher und Metriken der
laufenden Anwendung (nur nach Anmeldung erreichbar).

## Aufbau

```
  Anrufer ──PSTN──▶ Fritz!Box ──SIP──▶ Asterisk ──ARI──▶ Hermes (Phoenix)
                                   (Medien)            ├── Wochenplan
                                                       ├── ein Prozess je Anruf
                                                       └── Weboberfläche
                                                              │
                                                         PostgreSQL
```

Asterisk ist nur die Medienschicht: Es hält die SIP-Verbindung und die
Sprachkanäle. Die gesamte Logik — Dienstplan, Klingelreihenfolge, Eskalation,
Ansagen — liegt als Elixir-Code in Hermes und ist damit ohne Telefonanlage
testbar. Warum das so ist, steht in [docs/adr/](docs/adr/).

## Entwicklung

```sh
docker compose -f compose.dev.yaml up -d       # Postgres für die Entwicklung
mix setup
mix phx.server                                 # http://localhost:4000
mix precommit                                  # Compiler, Format, Credo, Tests
```

Die Anruflogik läuft in Tests gegen einen Mock von Asterisk, der Dienstplan-
Resolver ganz ohne Datenbank. Beides braucht keine Telefonanlage.
