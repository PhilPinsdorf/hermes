# Fritz!Box einrichten

Hermes meldet sich an der Fritz!Box wie ein ganz normales IP-Telefon an. Die Fritz!Box
lässt dieses „Telefon“ bei Anrufen auf die Festnetznummer klingeln; Hermes nimmt ab und
leitet weiter. Weitergeleitete Anrufe gehen über dieselbe Fritz!Box wieder hinaus – mit der
Festnetznummer als Absender.

Die Menüpfade gelten für FRITZ!OS 7.x/8.x; bei älteren Versionen heißen sie leicht anders.

## 1. IP-Telefon anlegen

1. `http://fritz.box` öffnen und anmelden.
2. **Telefonie → Telefoniegeräte → Neues Gerät einrichten**.
3. **Telefon (mit und ohne Anrufbeantworter)** → Weiter.
4. **LAN/WLAN (IP-Telefon)** wählen, Name z. B. `Hermes` → Weiter.
5. **Benutzername** und **Kennwort** festlegen und notieren.
   - Kennwort: lang und zufällig (mind. 16 Zeichen), es verlässt nie das lokale Netz.
   - **Achtung:** Die Fritz!Box vergibt oft einen eigenen Benutzernamen und hängt dem
     eingegebenen z. B. `-1` an (aus `hermes_user` wird `hermes-user-1`). Nach dem Speichern
     unter *Bearbeiten → Anmeldedaten* nachsehen, welcher Name wirklich dort steht – genau
     dieser gehört in `.env` als `FRITZBOX_SIP_USER`.
6. **Ausgehende Anrufe:** die Festnetznummer wählen, deren Anrufe Hermes übernehmen soll.
   Diese Nummer sehen die Angerufenen später auf dem Handy (= „angezeigte Rufnummer“
   in den Hermes-Einstellungen).
7. **Ankommende Anrufe:** „nur auf folgende Rufnummern reagieren“ → dieselbe
   Festnetznummer. Andere Nummern (Fax, zweite Leitung) nicht anhaken.
8. Übernehmen.

Danach unter **Telefonie → Telefoniegeräte** beim neuen Gerät prüfen:

- **„Anmeldung aus dem Internet erlauben“ muss AUS sein.** Hermes steht im selben LAN.
- Die interne Rufnummer (z. B. `**620`) ist für Hermes egal.

> **Andere Telefone an derselben Nummer:** Klingeln weitere Geräte auf dieselbe
> Festnetznummer (DECT, analoge Telefone), klingeln sie parallel zu Hermes. Wer zuerst
> abnimmt, hat das Gespräch. Soll nur Hermes annehmen, bei den anderen Geräten unter
> „Ankommende Anrufe“ diese Nummer abwählen.

## 2. Zugangsdaten in `.env` eintragen

Auf dem Hermes-Host im Projektverzeichnis:

```sh
bin/setup          # ergänzt fehlende Einträge in .env, ändert keine vorhandenen
```

Dann in `.env`:

```sh
FRITZBOX_HOST=192.168.178.1       # Adresse der Fritz!Box
FRITZBOX_SIP_USER=…               # Benutzername aus Schritt 1.5
FRITZBOX_SIP_PASSWORD=…           # Kennwort aus Schritt 1.5
HERMES_CALL_MODE=test             # erst Leitungstest, siehe unten
```

`.env` ist nur für den Besitzer lesbar (`chmod 600`) und gehört nicht ins Git.

## 3. Starten und Anmeldung prüfen

```sh
docker compose up -d --build
docker compose exec asterisk asterisk -rx "pjsip show registrations"
```

Erwartet:

```
 fritzbox/sip:192.168.178.1          fritzbox-auth          Registered
```

In der Fritz!Box steht das IP-Telefon unter **Telefonie → Telefoniegeräte** jetzt mit
grünem Punkt („registriert“).

## 4. Leitungstest

Mit `HERMES_CALL_MODE=test` nimmt Hermes jeden Anruf selbst an und spielt eine
englische Testansage („Congratulations …“) – ganz ohne Weboberfläche und Wochenplan.

Vom Handy die Festnetznummer anrufen → die Ansage muss zu hören sein.

Danach `HERMES_CALL_MODE=stasis` setzen und `docker compose up -d` – ab dann übernimmt
Hermes die Anrufe (ab Meilenstein M4).

## Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| `Rejected` bei `pjsip show registrations` | Benutzername oder Kennwort falsch – meist weicht der Benutzername von dem ab, den man eingegeben hat (siehe 1.5). In `.env` korrigieren, `docker compose up -d asterisk`. |
| Gar keine Antwort der Fritz!Box (`No response received`, auch `ping` von Hand hilft nicht weiter) | Nach mehreren Fehlanmeldungen sperrt die Fritz!Box den Absender eine Zeit lang und verwirft SIP-Pakete still. Zugangsdaten korrigieren und warten, oder die Fritz!Box neu starten. |
| `Unregistered` / keine Antwort | `FRITZBOX_HOST` falsch oder Host nicht im LAN der Fritz!Box. `docker compose logs asterisk` zeigt, auf welcher IP SIP lauscht. |
| Container `asterisk` startet neu, Log „fehlende Einstellungen“ | `FRITZBOX_SIP_USER` / `FRITZBOX_SIP_PASSWORD` fehlen in `.env`. |
| Registriert, aber Anruf kommt nicht an | In der Fritz!Box beim IP-Telefon „Ankommende Anrufe“ prüfen. Live mitschauen: `docker compose exec asterisk asterisk -rvvv`. |
| Anruf kommt an, aber keine Ansage zu hören | RTP (UDP 10000–10200) wird von der Host-Firewall blockiert. Die Ports müssen aus dem LAN erreichbar sein. |

## Sicherheit

- SIP lauscht nur auf der LAN-Adresse des Hosts, nie auf allen Interfaces.
- Asterisk akzeptiert SIP ausschließlich von der Fritz!Box-IP; es gibt keinen anonymen
  Zugang und keinen Wählplan, über den von außen nach außen telefoniert werden könnte.
- ARI (die Steuerschnittstelle für Hermes) lauscht nur auf der Docker-Bridge, nicht im LAN.
- **Niemals** Port 5060 oder die RTP-Ports im Router nach außen freigeben.
