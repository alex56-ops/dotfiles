#!/usr/bin/env python3
"""
Filtert einen Bitwarden JSON-Export auf einen bestimmten Ordner.
Nutzung: python3 filter_bitwarden.py <export.json> <ordner-name-oder-id> [output.json]
"""

import json
import sys
import os


def main():
    if len(sys.argv) < 3:
        print("Nutzung: python3 filter_bitwarden.py <export.json> <ordner> [output.json]")
        print()
        print("  <export.json>  Pfad zur exportierten Bitwarden JSON-Datei")
        print("  <ordner>       Ordnername (z.B. 'IT/H&B') oder Ordner-ID (UUID)")
        print("  [output.json]  Ausgabedatei (optional, Standard: export_filtered.json)")
        sys.exit(1)

    input_file = os.path.abspath(os.path.expanduser(sys.argv[1]))
    folder_filter = sys.argv[2]
    if len(sys.argv) > 3:
        output_file = os.path.abspath(os.path.expanduser(sys.argv[3]))
    else:
        output_file = os.path.join(os.path.dirname(input_file), "export_filtered.json")

    if not os.path.exists(input_file):
        print(f"Fehler: Datei '{input_file}' nicht gefunden.")
        sys.exit(1)

    with open(input_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    if data.get("encrypted"):
        print("Fehler: Die Datei ist verschlüsselt. Bitte einen unverschlüsselten Export verwenden.")
        sys.exit(1)

    # Ordner finden — nach Name oder ID
    folder_id = None
    folder_name = None
    for folder in data.get("folders", []):
        if folder["id"] == folder_filter or folder["name"] == folder_filter:
            folder_id = folder["id"]
            folder_name = folder["name"]
            break

    if not folder_id:
        print(f"Fehler: Ordner '{folder_filter}' nicht gefunden.")
        print()
        print("Verfügbare Ordner:")
        for folder in data.get("folders", []):
            print(f"  - {folder['name']}  ({folder['id']})")
        sys.exit(1)

    # Items filtern
    all_items = data.get("items", [])
    filtered_items = [item for item in all_items if item.get("folderId") == folder_id]

    # Ausgabe zusammenbauen
    output = {
        "encrypted": False,
        "folders": [{"id": folder_id, "name": folder_name}],
        "items": filtered_items,
    }

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"Fertig! {len(filtered_items)} von {len(all_items)} Einträgen aus Ordner '{folder_name}' exportiert.")
    print(f"Ausgabedatei: {output_file}")


if __name__ == "__main__":
    main()
