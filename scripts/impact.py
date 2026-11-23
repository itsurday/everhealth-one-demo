"""Downstream impact of a field: every component in source that references it.

Usage: python scripts/impact.py Account.Lifecycle_Stage__c
Prints a Markdown report grouped by component type. Exit 2 on bad input.
Text-based (not a compiler), so Apex hits are marked "possible": review them.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eh_metadata as md  # noqa: E402

KINDS = [
    ("objects/{o}/fields/", "Field definition"),
    ("objects/{o}/validationRules/", "Validation rule"),
    ("objects/{o}/listViews/", "List view"),
    ("objects/", "Formula on another object"),
    ("layouts/", "Page layout"),
    ("flows/", "Flow"),
    ("approvalProcesses/", "Approval process"),
    ("workflows/", "Workflow field update"),
    ("reports/", "Report"),
    ("reportTypes/", "Report type"),
    ("dashboards/", "Dashboard"),
    ("customMetadata/Field_Mapping.", "GTM field mapping"),
    ("permissionsets/", "Permission set"),
    ("profiles/", "Profile"),
    ("classes/", "Apex (possible)"),
    ("triggers/", "Apex trigger (possible)"),
]


def _token(name):
    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", re.IGNORECASE)


def _references(rel, text, obj, field):
    """Return the component kind if this file references obj.field, else None."""
    tok = _token(field)
    if not tok.search(text):
        return None
    qualified = re.search(rf"(?<![A-Za-z0-9_]){re.escape(obj)}[.$]{re.escape(field)}(?![A-Za-z0-9_])", text, re.IGNORECASE)
    own = rel.startswith(f"objects/{obj}/")
    if rel.startswith("objects/"):
        if own and rel == f"objects/{obj}/fields/{field}.field-meta.xml":
            return "Field definition"
        if own and "/validationRules/" in rel:
            return "Validation rule"
        if own and "/listViews/" in rel:
            return "List view"
        if own and "/fields/" in rel:
            return "Formula on same object"
        return "Formula on another object" if qualified else None
    if rel.startswith("layouts/"):
        return "Page layout" if rel.startswith(f"layouts/{obj}-") and f"<field>{field}</field>".lower() in text.lower() else None
    if rel.startswith("flows/"):
        return "Flow" if qualified or f"<object>{obj}</object>" in text else None
    if rel.startswith(("approvalProcesses/", "workflows/", "quickActions/")):
        kind = {"approvalProcesses/": "Approval process", "workflows/": "Workflow field update", "quickActions/": "Quick action"}
        return next(v for k, v in kind.items() if rel.startswith(k)) if os.path.basename(rel).startswith(obj + ".") else None
    if rel.startswith("reportTypes/"):
        return "Report type" if f"<baseObject>{obj}</baseObject>" in text else None
    if rel.startswith(("reports/", "dashboards/")):
        return ("Report" if rel.startswith("reports/") else "Dashboard") if qualified else None
    if rel.startswith("customMetadata/Field_Mapping."):
        return "GTM field mapping" if re.search(rf">{re.escape(obj)}<", text) and re.search(rf">{re.escape(field)}<", text) else None
    if rel.startswith(("permissionsets/", "profiles/")):
        return ("Permission set" if rel.startswith("permissionsets/") else "Profile") if qualified else None
    if rel.startswith(("classes/", "triggers/")) and rel.endswith((".cls", ".trigger")):
        if qualified or _token(obj).search(text):
            return "Apex test (possible)" if re.search(r"@IsTest", text, re.IGNORECASE) else "Apex (possible)"
    return None


def find(obj, field, src=md.DEFAULT_SRC):
    """[(kind, component, relative path, first matching line)]"""
    hits = []
    tok = _token(field)
    for rel, text in md.iter_source_files(src):
        kind = _references(rel, text, obj, field)
        if kind:
            line_no = next((i for i, line in enumerate(text.splitlines(), 1) if tok.search(line)), 0)
            component = os.path.basename(rel).split(".")[0] if not rel.startswith("customMetadata/") else os.path.basename(rel)[:-len(".md-meta.xml")]
            hits.append((kind, component, rel, line_no))
    return hits


def render(obj, field, hits):
    out = [f"# Impact: `{obj}.{field}`\n", f"{len(hits)} reference(s) in force-app.\n"]
    if not hits:
        out.append("\nNo references found. Check the API name, or the field may be unused.\n")
        return "".join(out)
    by_kind = {}
    for kind, component, rel, line in hits:
        by_kind.setdefault(kind, []).append((component, rel, line))
    for kind in sorted(by_kind):
        out.append(f"\n## {kind} ({len(by_kind[kind])})\n\n| Component | File |\n|---|---|\n")
        for component, rel, line in sorted(by_kind[kind]):
            out.append(f"| {component} | `force-app/main/default/{rel}:{line}` |\n")
    external = [c for k, c, _, _ in hits if k == "GTM field mapping"]
    if external:
        out.append(f"\n**External systems affected:** {', '.join(sorted(external))}. Coordinate the change with the tool owners (docs/SYNC_RULES.md).\n")
    return "".join(out)


def main(argv):
    if len(argv) != 1 or not re.fullmatch(r"[A-Za-z0-9_]+\.[A-Za-z0-9_]+", argv[0]):
        print("Usage: python scripts/impact.py <Object.Field>   e.g. Account.Lifecycle_Stage__c")
        return 2
    obj, field = argv[0].split(".")
    print(render(obj, field, find(obj, field)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
