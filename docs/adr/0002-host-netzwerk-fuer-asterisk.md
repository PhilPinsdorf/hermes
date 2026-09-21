# 2. Asterisk läuft im Host-Netzwerk

Status: entschieden, umgesetzt in M3

## Worum es geht

Alle anderen Container (App, Datenbank) liegen in einem eigenen Docker-Netz.
Für Asterisk wäre das naheliegend, funktioniert aber schlecht.

## Entscheidung

Der Asterisk-Container nutzt `network_mode: host`. SIP bindet dabei nur an die
LAN-Adresse des Rechners, die Steuerschnittstelle ARI nur an die
Docker-Bridge-Adresse.

## Warum

SIP und RTP vertragen sich schlecht mit NAT: In den SIP-Nachrichten stehen
IP-Adressen, und wenn Docker die Adressen umschreibt, bleiben Gesprächsdaten an
der falschen Stelle hängen. Das typische Ergebnis ist Einweg-Audio, bei dem
eine Seite die andere hört, aber nicht umgekehrt. Man kann das mit
`external_media_address`, festen Portbereichen und Weiterleitungen einfangen,
aber jede dieser Einstellungen ist eine Fehlerquelle bei jedem Rollout.

Im Host-Netz entfällt das Problem ersatzlos: Asterisk sieht dieselben Adressen
wie die Fritz!Box.

## Womit wir leben

- Die Ports des Containers liegen direkt auf dem Rechner. Deshalb bindet SIP
  ausdrücklich nur auf die LAN-Adresse, und die Firewall-Regeln stehen in
  `docs/rollout.md`.
- ARI ist von der App nur über die Docker-Bridge erreichbar
  (`host.docker.internal`), nicht aus dem lokalen Netz. `http.conf` kennt keine
  Zugriffslisten, deshalb wird über die Bindeadresse abgegrenzt statt über
  einen Filter.
