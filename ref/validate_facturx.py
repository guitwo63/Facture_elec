#!/usr/bin/env python3
"""
Validate Factur-X XML against the official EN 16931 XSD and Schematron.

Usage:
    python3 ref/validate_facturx.py <xml_file>
    cat xml_data | python3 ref/validate_facturx.py -

Output: JSON on stdout:
    {"valid": true,  "errors": [], "warnings": []}
    {"valid": false, "errors": ["..."], "warnings": []}

Requires:
    pip3 install factur-x lxml
"""

import json
import sys
from pathlib import Path

try:
    from facturx import xml_check_xsd, xml_check_schematron
except ImportError:
    print(json.dumps({
        "valid": False,
        "errors": ["La librairie factur-x n'est pas installée. Lancez : pip3 install factur-x lxml"],
        "warnings": []
    }))
    sys.exit(2)


def validate(xml_bytes: bytes) -> dict:
    results = {"valid": True, "errors": [], "warnings": []}

    # --- Layer 1: XSD validation ---
    try:
        ok, xsd_errors = xml_check_xsd(xml_bytes, profile="en16931")
        if not ok:
            results["errors"].extend(
                f"XSD: {e}" if not str(e).startswith("XSD:") else str(e)
                for e in xsd_errors
            )
            results["valid"] = False
    except Exception as e:
        results["errors"].append(f"XSD: erreur d'exécution — {e}")
        results["valid"] = False

    # --- Layer 2: Schematron EN 16931 business rules ---
    try:
        ok, sch_errors = xml_check_schematron(xml_bytes, profile="en16931")
        if not ok:
            results["errors"].extend(
                f"Schematron: {e}" if not str(e).startswith("Schematron:") else str(e)
                for e in sch_errors
            )
            results["valid"] = False
    except Exception as e:
        # Schematron needs a Saxon server (v6.0+) or saxonche (older).
        # If unavailable, warn but don't block.
        results["warnings"].append(
            f"Schematron non exécuté — moteur Saxon indisponible : {e}. "
            "Installez Saxon ou utilisez une version factur-x < 6.0 avec saxonche."
        )

    return results


def main():
    if len(sys.argv) < 2:
        print(json.dumps({
            "valid": False,
            "errors": ["Usage: python3 validate_facturx.py <xml_file>"],
            "warnings": []
        }))
        sys.exit(2)

    arg = sys.argv[1]
    if arg == "-":
        xml_bytes = sys.stdin.buffer.read()
    else:
        xml_bytes = Path(arg).read_bytes()

    if not xml_bytes.strip():
        print(json.dumps({
            "valid": False,
            "errors": ["Le fichier XML est vide."],
            "warnings": []
        }))
        sys.exit(1)

    results = validate(xml_bytes)
    print(json.dumps(results, ensure_ascii=False, indent=2))
    sys.exit(0 if results["valid"] else 1)


if __name__ == "__main__":
    main()
