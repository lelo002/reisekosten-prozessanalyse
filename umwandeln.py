"""Wandelt DomesticDeclarations.xes.gz in zwei CSV-Dateien um.

event_log.csv : eine Zeile pro Ereignis
cases.csv     : eine Zeile pro Antrag
Aufruf im Terminal:  python3 umwandeln.py
Benötigt nur Python, keine Zusatzpakete.
"""
import csv, gzip, pathlib, sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ORDNER = pathlib.Path(__file__).parent / "daten"
treffer = sorted(ORDNER.glob("*.xes.gz")) + sorted(ORDNER.glob("*.xes"))
if not treffer:
    sys.exit(f"Keine .xes.gz oder .xes Datei gefunden in {ORDNER}")
quelle = treffer[0]
oeffnen = gzip.open if quelle.suffix == ".gz" else open

def name(tag):                       # XML-Namensraum entfernen
    return tag.rsplit("}", 1)[-1]

def werte(knoten):                   # Attribute eines Falls oder Ereignisses
    return {k.get("key"): k.get("value") for k in knoten if k.get("key")}

def utc(text):                       # alle Zeiten einheitlich in UTC
    t = datetime.fromisoformat(text.replace("Z", "+00:00"))
    return t.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S+00")

ereignisse, faelle = [], []
with oeffnen(quelle, "rb") as f:
    for _, el in ET.iterparse(f, events=("end",)):
        if name(el.tag) != "trace":
            continue
        fall = werte([k for k in el if name(k.tag) != "event"])
        case_id = fall.get("concept:name")
        for nr, ev in enumerate((k for k in el if name(k.tag) == "event"), start=1):
            w = werte(ev)
            ereignisse.append([case_id, nr, w.get("concept:name"), utc(w["time:timestamp"]),
                               w.get("org:resource"), w.get("org:role")])
        faelle.append([case_id, fall.get("Amount"), fall.get("BudgetNumber")])
        el.clear()                   # Speicher sparen

def schreibe(datei, kopf, zeilen):
    with open(ORDNER / datei, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows([kopf, *zeilen])
    print(f"{datei}: {len(zeilen)} Zeilen")

schreibe("event_log.csv", ["case_id", "event_nr", "activity", "event_time", "resource", "role"], ereignisse)
schreibe("cases.csv", ["case_id", "amount", "budget_number"], faelle)
