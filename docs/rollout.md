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

**c) Mit TLS über einen eigenen Namen**

Dafür muss der Name öffentlich auf diesen Anschluss zeigen und die Ports 80 und
443 müssen erreichbar sein:

```sh
HTTP_BIND=127.0.0.1
PHX_HOST=hermes.kunde.de
PHX_URL_SCHEME=https
PHX_URL_PORT=443
ACME_EMAIL=technik@kunde.de
```

Danach mit TLS-Profil starten: `docker compose --profile tls up -d`.
Caddy holt das Zertifikat selbst.

> Egal welche Variante: **Port 5060 und die RTP-Ports gehören niemals ins
> Internet.** Sie dürfen nur aus dem lokalen Netz erreichbar sein.

## 5. Starten

```sh
docker compose up -d --build
docker compose ps
```

Der erste Build dauert einige Minuten: Asterisk wird aus dem Quellcode gebaut
und die Sprachausgabe heruntergeladen.

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
bin/setup                     # ergänzt neue Einträge in .env, ändert keine vorhandenen
docker compose up -d --build  # Migrationen laufen beim Start automatisch
```

## Wenn etwas nicht geht

| Symptom | Wo nachsehen |
|---|---|
| Übersicht sagt „Telefonanlage getrennt" | `docker compose logs asterisk`, läuft der Container? |
| Übersicht sagt „Amt nicht erreichbar" | Fritz!Box-Anmeldung prüfen, siehe [fritzbox.md](fritzbox.md) |
| Anruf kommt nicht an | In der Fritz!Box beim IP-Telefon „Ankommende Anrufe" prüfen |
| Anruf kommt an, aber kein Ton | RTP-Ports 10000–10200/UDP aus dem lokalen Netz erreichbar? |
| Handy klingelt nicht | Nummer der Person prüfen; unter **Anrufe** steht das Ergebnis je Versuch |
| Anrufer landet auf einer Mailbox | Sollte nicht passieren — Ergebnis des Anrufs unter **Anrufe** prüfen und melden |
| Nichts hilft | `HERMES_CALL_MODE=test` in `.env`, `docker compose up -d asterisk`: Kommt die Testansage, liegt es an Hermes, sonst an der Leitung |
