"""Reads EverHealth One SFDX source (force-app) for the doc generator and /impact. Standard library only."""
import os
import xml.etree.ElementTree as ET

NS = {"m": "http://soap.sforce.com/2006/04/metadata"}
DEFAULT_SRC = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "force-app", "main", "default"))


def _text(el, path):
    found = el.find(path, NS)
    return (found.text or "").strip() if found is not None else ""


def _root(path):
    return ET.parse(path).getroot()


def _files(src, folder, suffix):
    base = os.path.join(src, folder)
    if not os.path.isdir(base):
        return []
    return sorted(os.path.join(base, f) for f in os.listdir(base) if f.endswith(suffix))


def fields(src=DEFAULT_SRC):
    """Custom fields of every object folder, incl. sensitivity labels."""
    out = []
    objects_dir = os.path.join(src, "objects")
    for obj in sorted(os.listdir(objects_dir)) if os.path.isdir(objects_dir) else []:
        for path in _files(os.path.join(objects_dir, obj), "fields", ".field-meta.xml"):
            r = _root(path)
            out.append({
                "object": obj,
                "api": _text(r, "m:fullName"),
                "label": _text(r, "m:label"),
                "type": _text(r, "m:type"),
                "sensitivity": _text(r, "m:securityClassification"),
                "compliance": _text(r, "m:complianceGroup"),
                "description": _text(r, "m:description"),
                "external_id": _text(r, "m:externalId") == "true",
                "unique": _text(r, "m:unique") == "true",
            })
    return out


def flows(src=DEFAULT_SRC):
    out = []
    for path in _files(src, "flows", ".flow-meta.xml"):
        r = _root(path)
        trigger = _text(r, "m:start/m:triggerType") or ("Screen" if _text(r, "m:processType") == "Flow" else "Autolaunched")
        detail = _text(r, "m:start/m:recordTriggerType")
        if trigger == "Scheduled":
            detail = f"{_text(r, 'm:start/m:schedule/m:frequency')} {_text(r, 'm:start/m:schedule/m:startTime')[:5]} org time"
        out.append({
            "name": os.path.basename(path).replace(".flow-meta.xml", ""),
            "label": _text(r, "m:label"),
            "trigger": trigger,
            "detail": detail,
            "object": _text(r, "m:start/m:object"),
            "status": _text(r, "m:status"),
            "description": _text(r, "m:description"),
        })
    return out


def approval_processes(src=DEFAULT_SRC):
    out = []
    for path in _files(src, "approvalProcesses", ".approvalProcess-meta.xml"):
        r = _root(path)
        name = os.path.basename(path).replace(".approvalProcess-meta.xml", "")
        out.append({"name": name, "label": _text(r, "m:label"), "object": name.split(".")[0],
                    "active": _text(r, "m:active"), "description": _text(r, "m:description")})
    return out


def triggers(src=DEFAULT_SRC):
    out = []
    for path in _files(src, "triggers", ".trigger"):
        with open(path, encoding="utf-8") as f:
            header = f.readline().strip()
        out.append({"name": os.path.basename(path)[:-len(".trigger")], "header": header})
    return out


def reports(src=DEFAULT_SRC):
    out = []
    reports_dir = os.path.join(src, "reports")
    for folder in sorted(os.listdir(reports_dir)) if os.path.isdir(reports_dir) else []:
        for path in _files(reports_dir, folder, ".report-meta.xml"):
            r = _root(path)
            out.append({"folder": folder, "name": _text(r, "m:name"), "report_type": _text(r, "m:reportType"),
                        "description": _text(r, "m:description"),
                        "groupings": [g.text for g in r.findall("m:groupingsDown/m:field", NS)]})
    return out


def dashboards(src=DEFAULT_SRC):
    out = []
    dash_dir = os.path.join(src, "dashboards")
    for folder in sorted(os.listdir(dash_dir)) if os.path.isdir(dash_dir) else []:
        for path in _files(dash_dir, folder, ".dashboard-meta.xml"):
            r = _root(path)
            comps = [(_text(c, "m:header"), _text(c, "m:componentType"), _text(c, "m:report"))
                     for c in r.iter("{%s}components" % NS["m"])]
            out.append({"title": _text(r, "m:title"), "description": _text(r, "m:description"), "components": comps})
    return out


def field_mappings(src=DEFAULT_SRC):
    """Field_Mapping__mdt records as dicts of field -> value."""
    out = []
    for path in _files(src, "customMetadata", ".md-meta.xml"):
        if not os.path.basename(path).startswith("Field_Mapping."):
            continue
        r = _root(path)
        rec = {"name": os.path.basename(path)[len("Field_Mapping."):-len(".md-meta.xml")]}
        for v in r.findall("m:values", NS):
            rec[_text(v, "m:field")] = _text(v, "m:value")
        out.append(rec)
    return out


def iter_source_files(src=DEFAULT_SRC):
    """(path relative to src, text) for every metadata/source file."""
    for dirpath, _, names in os.walk(src):
        for name in sorted(names):
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="replace") as f:
                yield os.path.relpath(path, src).replace(os.sep, "/"), f.read()
