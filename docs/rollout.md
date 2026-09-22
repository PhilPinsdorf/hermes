# Installation beim Kunden

Eine Hermes-Installation gehört zu einem Kunden und einer Festnetznummer.
Diese Anleitung führt von einem leeren Linux-Rechner bis zum ersten echten
Anruf. Rechne mit einer Stunde, der Löwenanteil ist das Warten auf Downloads.

## 1. Was vorhanden sein muss

- **Rechner**: ein kleiner Linux-Rechner (Mini-PC, NUC, alter Laptop) im selben
  Netz wie die Fritz!Box, per Kabel angeschlossen, dauerhaft eingeschaltet.
  2 GB RAM und 10 GB Plattenplatz reichen.
- **Feste Adresse**: dem Rechner in der Fritz!Box eine feste IP zuweisen
  (*Heimnetz → Netzwerk → Gerät → „Immer die gleiche IPv4-Adresse zuweisen"*).
- **Docker** und **Docker Compose**.
- **Zugang zur Fritz!Box** als Administrator.
- **Die Rufnummer**, unter der die Bereitschaft erreichbar sein soll.
- Die **Handynummern** der Personen, die Dienst haben werden.

## 2. Hermes installieren

```sh
sudo mkdir -p /opt/hermes && sudo chown "$USER" /opt/hermes
git clone <repository> /opt/hermes && cd /opt/hermes
bin/setup
```

`bin/setup` legt `.env` mit frisch erzeugten Passwörtern an. Die Datei enthält
alle Geheimnisse der Installation, ist nur für den Besitzer lesbar und gehört
**nicht** ins Git. Sichere sie in einem Passwortmanager.

## 3. Fritz!Box einrichten

Siehe **[fritzbox.md](fritzbox.md)**: IP-Telefon anlegen, Rufnummer für
ankommende und ausgehende Anrufe zuweisen, Benutzername und Kennwort in `.env`
eintragen.

Zur Erinnerung die Stolperfalle: Die Fritz!Box vergibt oft einen **eigenen
Benutzernamen** (aus `hermes` wird `hermes-1`). Es zählt der Name, der nach dem
Speichern unter *Anmeldedaten* steht.

## 4. Zugang zur Weboberfläche festlegen

In `.env`:

| Eintrag | Bedeutung |
|---|---|
| `PHX_HOST` | Name oder IP, unter der die Oberfläche aufgerufen wird |
| `PHX_URL_SCHEME` | `http` oder `https` |
| `PHX_URL_PORT` | Port in der Adresse (`4000` bzw. `443`) |
| `HTTP_BIND` | Auf welcher Adresse der Port lauscht |

Drei übliche Varianten:

**a) Nur über Tailscale (empfohlen, kein Port im Netz offen)**

```sh
HTTP_BIND=100.x.y.z      # die Tailscale-Adresse dieses Rechners
PHX_HOST=hermes.dein-tailnet.ts.net
PHX_URL_SCHEME=http
PHX_URL_PORT=4000
```

**b) Im lokalen Netz**

```sh
HTTP_BIND=0.0.0.0
PHX_HOST=192.168.178.91
PHX_URL_SCHEME=http
PHX_URL_PORT=4000
```

**c) Öffentlich über einen Cloudflare Tunnel (empfohlen für Kunden)**

Der Tunnel baut die Verbindung von innen nach außen auf. Es muss also **kein
Port im Router freigegeben** werden, und auf dem Rechner selbst muss nichts
lauschen. TLS und Zertifikat liegen bei Cloudflare, ein eigener Reverse Proxy
ist nicht nötig.

1. Im Cloudflare-Dashboard unter *Zero Trust → Networks → Tunnels* einen Tunnel
   anlegen, als Public Hostname die gewünschte Adresse eintragen und als
   Service `http://app:4000`.

   > **`app` ist ein Docker-Name, kein Rechnername.** Er wird nur von
   > Containern im selben Compose-Netz aufgelöst — deshalb muss `cloudflared`
   > über das Profil unten mitlaufen. Wer den Tunnel stattdessen nach Anleitung
   > des Dashboards als Dienst auf dem Rechner installiert (`cloudflared
   > service install …`) oder als einzelnen `docker run`-Container startet, für
   > den existiert `app` nicht: Cloudflare antwortet dann mit *Bad Gateway* und
   > „Origin DNS error" (Fehler 1016). Siehe „Wenn etwas nicht geht".
2. Den angezeigten Token in `.env` eintragen:

```sh
TUNNEL_TOKEN=eyJhIjoi…
HTTP_BIND=127.0.0.1        # nichts im LAN nötig; nur lokal zum Debuggen
PHX_HOST=hermes.kunde.de   # die öffentliche Adresse
PHX_URL_SCHEME=https
PHX_URL_PORT=443
```

3. Starten:

```sh
docker compose --profile tunnel up -d
```

Sobald `PHX_URL_SCHEME=https` gesetzt ist, kennzeichnet Hermes das
Sitzungs-Cookie als `Secure` und sendet HSTS. Umgeleitet wird von Cloudflare.

> Wer mag, legt in Cloudflare Access noch eine zweite Anmeldung davor. Die
> Anmeldung in Hermes bleibt davon unberührt.

**d) Hinter einem anderen Reverse Proxy** (Traefik, nginx, Caddy, Nginx Proxy
Manager)

Hermes läuft hinter jedem davon. Der Proxy muss nur:

- auf `app:4000` weiterleiten (bzw. auf den veröffentlichten Port),
- **WebSockets** durchlassen — ohne sie bleibt die Oberfläche stumm,
- `X-Forwarded-Proto` setzen.

In `.env` wie bei Variante c die öffentliche Adresse und `https` eintragen.
Setzt der Proxy `X-Forwarded-Proto` **nicht**, entsteht eine Umleitungsschleife;
dann zusätzlich `HTTPS_REDIRECT=false` setzen, womit das Umleiten dem Proxy
überlassen wird und nur Cookie-Schutz und HSTS aktiv bleiben.

> Egal welche Variante: **Port 5060 und die RTP-Ports gehören niemals ins
> Internet.** Sie dürfen nur aus dem lokalen Netz erreichbar sein.

## 5. Starten

> **Vorher: Es darf keine zweite Instanz mit denselben Zugangsdaten laufen.**
> Die Fritz!Box lässt ein IP-Telefon mehrfach anmelden und schickt eingehende
> Anrufe an **alle** Anmeldungen gleichzeitig. Wer zuerst annimmt, bekommt das
> Gespräch; alle anderen erhalten ein `CANCEL` mit `text="Call completed
> elsewhere"` und legen auf. Das trifft jede Kopie der `.env` — den
> Entwicklungsrechner, einen alten Testaufbau, ein Softphone mit denselben
> Daten. Vor dem Start dort abschalten:
>
> ```sh
> docker compose down        # auf jedem anderen Rechner, der die .env hat
> ```
>
> Wer parallel entwickeln muss, legt sich in der Fritz!Box ein **eigenes
> IP-Telefon** mit eigenen Zugangsdaten an, ohne Rufnummer unter „Ankommende
> Anrufe" — siehe [fritzbox.md](fritzbox.md), Abschnitt 5.

```sh
docker compose pull
docker compose up -d
docker compose ps
```

Die Images baut GitHub bei jedem Push nach `main` und legt sie in der
GitHub-Registry ab (siehe `.github/workflows/images.yml`). Der Rechner beim
Kunden lädt sie nur noch herunter, statt Asterisk selbst aus dem Quellcode zu
übersetzen — das spart je nach Maschine zehn Minuten und einiges an RAM.

> **Sind die Pakete privat**, meldet `docker compose pull` „denied". Dann
> entweder in GitHub unter *Packages → Package settings* die Sichtbarkeit auf
> öffentlich stellen, oder sich auf dem Rechner einmal anmelden — mit einem
> Token, das nur `read:packages` darf:
>
> ```sh
> echo "$GITHUB_TOKEN" | docker login ghcr.io -u DEIN-GITHUB-NAME --password-stdin
> ```

Welche Version läuft, steht als `HERMES_TAG` in `.env`: `latest` folgt dem
Stand von `main`, ein Release-Tag (`v1.2.3`) bleibt stehen, bis man ihn ändert.
Beim Kunden ist ein fester Tag die ruhigere Wahl.

**Ohne Registry**, etwa für eine Änderung, die noch nicht veröffentlicht ist:

```sh
docker compose up -d --build
```

Dann wird lokal gebaut; der erste Durchlauf dauert einige Minuten, weil
Asterisk aus dem Quellcode entsteht und die Sprachausgabe geladen wird.

Prüfen:

```sh
curl -s localhost:4000/healthz
docker compose exec asterisk asterisk -rx "pjsip show registrations"   # Registered
```

## 6. Ersten Benutzer anlegen

```sh
docker compose exec -it app bin/create_admin technik@kunde.de
```

Das Passwort wird abgefragt und nicht angezeigt. Weitere Benutzer legt man
danach in der Oberfläche an.

## 7. In der Oberfläche einrichten

Die Übersichtsseite führt durch die offenen Schritte:

1. **Einstellungen**: angezeigte Rufnummer eintragen (die Festnetznummer),
   Anzeigename prüfen, Klingeldauer und Reihenfolge festlegen.
2. **Personen**: alle anlegen, die Dienst haben können. Statt einer Handynummer
   geht auch eine interne Nebenstelle der Fritz!Box (`**621`).
3. **Wochenplan**: Schichten aufziehen. Ausnahmen für Urlaub oder Tausch unter
   „Ausnahmen".
4. **Kontakt verteilen**: Unter Einstellungen die Datei `hermes-kontakt.vcf`
   herunterladen und an alle Personen schicken. Jede importiert sie einmal,
   danach steht bei jedem weitergeleiteten Anruf der vereinbarte Name im
   Display statt einer nackten Nummer.
5. **Ansagen anhören** und die Texte anpassen, falls gewünscht.

## 8. Abnahme

Diese Punkte einmal durchgehen:

- [ ] Anruf aufs Festnetz → das Handy der diensthabenden Person klingelt mit
      der Festnetznummer als Absender
- [ ] Bestätigungsansage ist zu hören; nach der **1** steht das Gespräch in
      beide Richtungen
- [ ] **2** gibt an die nächste Person weiter, **3** beendet den Anruf
- [ ] Handy ausschalten, sodass die Mobilbox abhebt → der Anrufer landet
      **nicht** dort, sondern wird weitergereicht
- [ ] Schicht löschen → Anruf → Ansage „niemand erreichbar"
- [ ] Der Anruf steht unter **Anrufe** mit dem richtigen Ergebnis
- [ ] Auf dem Handy des Angerufenen erscheint **nie** die Nummer des Anrufers

## 9. Absichern

**Firewall** (Beispiel für firewalld, im Zweifel an die Distribution anpassen):

```sh
# SIP und RTP nur aus dem lokalen Netz
sudo firewall-cmd --permanent --new-zone=hermes-lan 2>/dev/null || true
sudo firewall-cmd --permanent --zone=hermes-lan --add-source=192.168.178.0/24
sudo firewall-cmd --permanent --zone=hermes-lan --add-port=5060/udp
sudo firewall-cmd --permanent --zone=hermes-lan --add-port=10000-10200/udp
sudo firewall-cmd --reload
```

Was ohnehin schon gilt, ohne dass man etwas tun muss:

- SIP lauscht nur auf der LAN-Adresse, nicht auf allen Schnittstellen.
- Asterisk akzeptiert SIP ausschließlich von der Fritz!Box-Adresse. Es gibt
  keinen anonymen Zugang.
- Es existiert kein Wählplan, über den von außen nach außen telefoniert werden
  könnte — ein Missbrauch zum Telefonieren auf fremde Kosten ist damit
  ausgeschlossen.
- ARI, die Steuerschnittstelle, lauscht nur auf der Docker-Bridge.
- Die Verwaltungsschnittstelle AMI von Asterisk ist ausgeschaltet.

**Im Router**: keine Portfreigabe auf diesen Rechner einrichten. Insbesondere
nicht 5060, nicht die RTP-Ports und nicht 8088.

**Fehlversuche beobachten**:

```sh
docker compose logs asterisk | grep -i "failed\|rejected"
```

Wiederholte Anmeldeversuche von fremden Adressen dürfen gar nicht erst
auftauchen, weil nur die Fritz!Box akzeptiert wird. Tauchen sie doch auf, ist
vermutlich doch ein Port freigegeben.

## 10. Backups

```sh
bin/backup
```

Sichert Datenbank und Ansagen nach `backups/`, älteres als die letzten 14 wird
gelöscht. Nächtlich per Cron (`crontab -e`):

```
15 3 * * * cd /opt/hermes && bin/backup >> /var/log/hermes-backup.log 2>&1
```

Die Sicherungen liegen auf demselben Rechner. Kopiere sie regelmäßig woanders
hin, sonst sind sie beim Plattenausfall mit weg.

**Zurückspielen:**

```sh
bin/restore backups/hermes-db-2026-09-21_031500.sql.gz
```

Ansagen (nur nötig, wenn eigene Aufnahmen hochgeladen wurden):

```sh
docker compose exec -T app tar xz -C /var/lib/asterisk/sounds \
  < backups/hermes-sounds-2026-09-21_031500.tar.gz
```

**`.env` gehört nicht in das Backup**, sondern in einen Passwortmanager. Ohne
sie lässt sich eine Sicherung zwar einspielen, aber die Anmeldungen an
Fritz!Box und Datenbank stimmen dann nicht mehr.

## 11. Updates

```sh
cd /opt/hermes
bin/backup
git pull
bin/setup              # ergänzt neue Einträge in .env, ändert keine vorhandenen
docker compose pull
docker compose up -d   # Migrationen laufen beim Start automatisch
```

`git pull` holt dabei nur `compose.yaml`, die Skripte und die Doku — der Code
steckt im Image. Steht in `.env` ein fester `HERMES_TAG`, muss der vorher auf
die neue Version gesetzt werden, sonst ändert `docker compose pull` nichts.

Wer ohne Registry arbeitet, nimmt weiterhin `docker compose up -d --build`.

## Wenn etwas nicht geht

| Symptom | Wo nachsehen |
|---|---|
| Übersicht sagt „Telefonanlage getrennt" | `docker compose logs asterisk`, läuft der Container? |
| Übersicht sagt „Amt nicht erreichbar" | Fritz!Box-Anmeldung prüfen, siehe [fritzbox.md](fritzbox.md) |
| Anruf kommt nicht an | In der Fritz!Box beim IP-Telefon „Ankommende Anrufe" prüfen |
| Anruf kommt an, aber kein Ton | RTP-Ports 10000–10200/UDP aus dem lokalen Netz erreichbar? |
| Handy klingelt nicht | Nummer der Person prüfen; unter **Anrufe** steht das Ergebnis je Versuch |
| Anrufer landet auf einer Mailbox | Sollte nicht passieren — Ergebnis des Anrufs unter **Anrufe** prüfen und melden |
| Anruf bricht nach Millisekunden ab | Läuft dieselbe Installation noch woanders? Siehe unten |
| Nichts hilft | `HERMES_CALL_MODE=test` in `.env`, `docker compose up -d asterisk`: Kommt die Testansage, liegt es an Hermes, sonst an der Leitung |

### Anrufe brechen sofort ab („Call completed elsewhere")

Im Anrufprotokoll steht als Ergebnis **aufgelegt**, und im Log liegen zwischen
„calling …" und „caller hung up" nur Millisekunden:

```
15:33:10.877 [info] call 1790091190.2: calling Max
15:33:10.890 [info] call 1790091190.2: caller hung up
```

So schnell legt kein Mensch auf. Der SIP-Mitschnitt zeigt, wer abräumt:

```sh
docker compose exec asterisk asterisk -rx "pjsip set logger on"
# Testanruf, danach:
docker compose logs asterisk --since 3m | grep -B5 -A10 -iE "^CANCEL|Reason:"
docker compose exec asterisk asterisk -rx "pjsip set logger off"
```

Steht dort

```
CSeq: 39 CANCEL
Reason: SIP; cause=200; text="Call completed elsewhere"
```

dann hat **ein anderes Gerät den Anruf angenommen**. Zwei Ursachen:

1. **Eine zweite Hermes-Instanz mit derselben `.env`** — ein
   Entwicklungsrechner, ein alter Testaufbau, eine zweite Installation. Die
   Fritz!Box verteilt den Anruf an beide Anmeldungen; die andere Instanz hat
   meist keinen Wochenplan, ist deshalb sofort bei „niemand im Dienst", nimmt
   an und spielt ihre Ansage — daher die Millisekunden. Auf dem anderen
   Rechner `docker compose down`, dann einige Minuten warten, bis die
   Anmeldung an der Fritz!Box abgelaufen ist.
2. **Ein anderes Telefon an derselben Rufnummer** — DECT-Mobilteil, analoges
   Telefon oder der Anrufbeantworter der Fritz!Box mit 0 Sekunden Verzögerung.
   Unter *Telefonie → Telefoniegeräte* bei allen Geräten außer Hermes die
   Rufnummer unter „Ankommende Anrufe" abwählen.

Welche der beiden es war, steht in der Fritz!Box unter *Telefonie → Anrufe*:
Dort ist vermerkt, welches Gerät den Anruf angenommen hat.

### Cloudflare zeigt „Bad Gateway" / „Origin DNS error"

`cloudflared` kommt nicht an Hermes heran. Fast immer läuft es nicht im selben
Docker-Netz wie `app`. Erst feststellen, wo es überhaupt läuft:

```sh
cd /opt/hermes
docker compose ps -a | grep cloudflared    # im Stack?
systemctl status cloudflared               # oder als Dienst auf dem Rechner?
docker ps --filter ancestor=cloudflare/cloudflared --format '{{.Names}}\t{{.Networks}}'
```

Was `cloudflared` tatsächlich versucht, steht in seinem Log — die Zeile
„Updated to new configuration" zeigt die Service-URL, die es aus dem Dashboard
geholt hat:

```sh
docker compose logs cloudflared | grep -E "Updated to new configuration|originService"
```

**`service` steht auf `https://app:4000`** — der häufigste Fehler, weil das
Dashboard den Typ gern auf HTTPS vorbelegt. `cloudflared` beginnt dann einen
TLS-Handshake, Hermes spricht im Container aber nur Klartext-HTTP, liest das
ClientHello als kaputte Anfrage und trennt. Im Log:

```
originService=https://app:4000 … read: connection reset by peer
```

Beheben: im Public Hostname den Service-Typ auf **HTTP** stellen. Der Tunnel
übernimmt das von selbst, ein Neustart ist nicht nötig.

**Im Stack** (`hermes-cloudflared-1`, Netz `hermes_default`) — dann ist
`http://app:4000` richtig. Prüfen, ob der Name aus dem Netz heraus antwortet:

```sh
docker run --rm --network hermes_default curlimages/curl \
  -s -o /dev/null -w '%{http_code}\n' http://app:4000/healthz
```

Erwartet wird **301** (bei `PHX_URL_SCHEME=https`) beziehungsweise **200** (bei
`http`). Beides heißt: `app` ist erreichbar und antwortet. Die 301 ist kein
Fehler — curl schickt kein `X-Forwarded-Proto: https`, also leitet Hermes auf
die öffentliche Adresse um; der Tunnel schickt den Header und bekommt die
Seite. Nur `connection refused` oder gar keine Antwort wären ein Problem.

**Nicht im Stack** — dann kennt `cloudflared` den Namen `app` nicht. Zwei Wege:

- Den Tunnel in den Stack holen: den Host-Dienst abschalten
  (`sudo systemctl disable --now cloudflared`) beziehungsweise den einzelnen
  Container entfernen, `TUNNEL_TOKEN` in `.env` eintragen und
  `docker compose --profile tunnel up -d` starten. Das ist der Weg, den dieses
  Projekt vorsieht.
- Oder den Tunnel lassen, wo er ist, und die Service-URL anpassen: bei einem
  Dienst auf dem Rechner `http://localhost:4000`, bei einem eigenen Container
  entweder `--network hermes_default` mitgeben und bei `http://app:4000`
  bleiben, oder die LAN-Adresse des Rechners eintragen — dann muss `HTTP_BIND`
  in `.env` auf diese Adresse (oder `0.0.0.0`) stehen statt auf `127.0.0.1`.

Dass `curl http://app:4000/healthz` **auf dem Rechner selbst** nicht geht, ist
übrigens kein Fehler: `app` ist ein Docker-interner Name. Von außerhalb der
Container prüft man mit `curl -s localhost:4000/healthz`.
