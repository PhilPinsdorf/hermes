# 5. HTTPS wird zur Laufzeit erzwungen, nicht beim Bauen

Status: entschieden, umgesetzt beim Aufsetzen des Hostings

## Worum es geht

Hermes wird auf mehreren Wegen erreicht (siehe `docs/rollout.md`): öffentlich
über einen Cloudflare Tunnel, schlicht im lokalen Netz oder über Tailscale. Nur
der öffentliche Weg hat TLS. Getestet wird aber immer mit **demselben Image**,
das später beim Kunden läuft — ein zweites Image nur zum Testen würde den Test
wertlos machen.

Die Voreinstellung von Phoenix (`force_ssl` in `config/prod.exs`) ist eine
Einstellung zur Übersetzungszeit. Mit ihr leitet dieselbe Anwendung jeden
Zugriff, der nicht über `localhost` kommt, auf `https://` um — also auch den
Test im lokalen Netz, wo kein Zertifikat existiert und nichts antwortet.

## Entscheidung

`force_ssl` ist aus `config/prod.exs` entfernt. Stattdessen entscheidet
`HermesWeb.Https` **zur Laufzeit** anhand der konfigurierten Adresse
(`PHX_URL_SCHEME` in `.env`):

| `PHX_URL_SCHEME` | Verhalten |
|---|---|
| `https` | Umleitung von http auf https, HSTS-Header, Sitzungs-Cookie mit `Secure` |
| alles andere | keine Umleitung, Cookie ohne `Secure` |

Anfragen, die der Tunnel oder ein Proxy bereits per TLS entgegengenommen hat,
kommen mit `X-Forwarded-Proto: https` an und werden durchgelassen. `localhost`
ist ausgenommen, damit der Health-Check im Container weiter funktioniert — sonst
würde Docker einen gesunden Container für krank halten.

Setzt ein Proxy diesen Header nicht, entstünde eine Umleitungsschleife. Dafür
gibt es `HTTPS_REDIRECT=false`: Das Umleiten übernimmt dann der Proxy, Cookie
und HSTS bleiben.

## Warum kein eigener Reverse Proxy im Projekt?

Ein Cloudflare Tunnel beendet TLS, bringt das Zertifikat mit und braucht keine
Portfreigabe, weil er von innen nach außen verbindet. Caddy, Traefik oder
nginx würden dasselbe noch einmal tun. Das Projekt liefert deshalb nur das
Tunnel-Profil mit; wer ohnehin einen Proxy betreibt, stellt ihn davor — Hermes
verlangt davon nur zwei Dinge: WebSockets durchlassen und `X-Forwarded-Proto`
setzen.

Zwei Dinge kann ein vorgelagerter Proxy allerdings **nicht** übernehmen, und
deshalb gibt es diesen Plug überhaupt:

- Wer im lokalen Netz versehentlich direkt Port 4000 aufruft, umgeht den Proxy.
- Das Sitzungs-Cookie kann nur die Anwendung selbst als `Secure` kennzeichnen.

## Womit wir leben

Die Sitzungsoptionen werden je Anfrage zusammengebaut statt einmal beim
Übersetzen. Das kostet praktisch nichts und ist der Preis dafür, dass ein Image
für alle Betriebsarten reicht.
