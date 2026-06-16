#!/usr/bin/env python3
"""
Linter for the allow list files (allowed-hosts.txt, allowed-cidrs.txt).

Terraform parses these files with compact(split(" ", ...)) and silently drops
any line that doesn't have a port spec.  Invalid hostnames, bad CIDRs, and
malformed port specs pass through unchecked — they become firewall rules that
GCP may reject at apply time, or worse, rules that match the wrong traffic.

This linter catches those problems early with clear error messages.

Usage
-----
    python3 lint_allowlists.py
    python3 lint_allowlists.py allowed-hosts.txt allowed-cidrs.txt

Line format
-----------
    <value> <ports> [# comment]

    value   FQDN or CIDR.  CIDR file only: prefix with - for exclusion (deny).
    ports   Required.  *, 443, 80,443, 8000-9000, 80,443,8000-9000
    #       Optional inline comment.  Stripped before parsing.

Exit code
---------
    0  no errors (warnings are OK)
    1  one or more errors
"""

import ipaddress
import re
import sys
from collections import Counter
from pathlib import Path

# RFC 1123 hostname: 1-253 chars total, each label 1-63 chars,
# alphanumeric + hyphens, labels can't start/end with hyphen.
_HOSTNAME_RE = re.compile(
    r"^(?=.{1,253}$)"
    r"(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)"
    r"(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$"
)
_SINGLE = re.compile(r"^(\d{1,5})$")
_RANGE = re.compile(r"^(\d{1,5})-(\d{1,5})$")
MAX_PORT = 65535


def split_tokens(content):
    """Split on literal spaces, drop empties — mirrors Terraform's
    compact(split(" ", ...)).  Tab-separated values will NOT split."""
    return [t for t in content.split(" ") if t]


def validate_ports(spec):
    """Return a list of error strings for a port spec."""
    errors = []
    if spec == "*":
        return errors

    expanded = set()
    for part in spec.split(","):
        if not part:
            errors.append("empty token in comma list")
            continue
        if m := _SINGLE.match(part):
            p = int(m.group(1))
            if not 1 <= p <= MAX_PORT:
                errors.append(f"port out of range (1-{MAX_PORT}): {p}")
            if p in expanded:
                errors.append(f"duplicate port: {p}")
            expanded.add(p)
        elif m := _RANGE.match(part):
            lo, hi = int(m.group(1)), int(m.group(2))
            if lo > hi:
                errors.append(f"reversed range {lo}-{hi}")
            if not 1 <= lo <= MAX_PORT:
                errors.append(f"range start out of range: {lo}")
            if not 1 <= hi <= MAX_PORT:
                errors.append(f"range end out of range: {hi}")
            range_ports = set(range(lo, hi + 1))
            overlap = range_ports & expanded
            if overlap:
                errors.append(f"port range {lo}-{hi} overlaps already-specified ports: {sorted(overlap)}")
            expanded |= range_ports
        else:
            errors.append(f"invalid token: {part!r}")
    return errors


def lint_file(path, ftype):
    errors, warnings = [], []
    entries = []

    if not path.exists():
        return [f"file not found: {path}"], []

    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        hash_pos = raw.find("#")
        content = (raw[:hash_pos] if hash_pos != -1 else raw).strip()
        if not content:
            continue

        parts = split_tokens(content)
        if len(parts) < 2:
            errors.append(
                f"{path.name}:{lineno}: missing port spec — entry will be "
                f"dropped.  Use * for all ports, e.g.  {parts[0]}  *"
            )
            continue

        value, ports = parts[0], parts[1]
        is_deny = False
        check_val = value
        if ftype == "cidr" and value.startswith("-"):
            is_deny = True
            check_val = value[1:]

        if ftype == "fqdn":
            if check_val.startswith("*.") or "*" in check_val:
                errors.append(f"{path.name}:{lineno}: wildcards not supported: {check_val}")
            elif not _HOSTNAME_RE.match(check_val):
                errors.append(f"{path.name}:{lineno}: invalid hostname: {check_val}")
        else:
            try:
                net = ipaddress.ip_network(check_val, strict=False)
                if str(net) != check_val:
                    warnings.append(
                        f"{path.name}:{lineno}: host bits set — {check_val} "
                        f"normalised to {net}"
                    )
            except ValueError as e:
                errors.append(f"{path.name}:{lineno}: invalid CIDR: {check_val} ({e})")

        for err in validate_ports(ports):
            errors.append(f"{path.name}:{lineno}: {err}")

        if len(parts) > 2:
            warnings.append(
                f"{path.name}:{lineno}: extra text after port spec ignored: "
                f"{' '.join(parts[2:])}"
            )

        entries.append({
            "lineno": lineno,
            "value": check_val,
            "ports": ports,
            "deny": is_deny,
        })

    duplicates = [(e, n) for e, n in Counter(
        (e["value"], e["ports"], e["deny"]) for e in entries
    ).items() if n > 1]
    for (val, ports, deny), n in duplicates:
        warnings.append(f"{path.name}: duplicate entry ({n}x): {val} {ports}")

    if ftype == "cidr":
        cidr_warnings = lint_cidr_logic(entries, path.name)
        warnings.extend(cidr_warnings)

    return errors, warnings


def lint_cidr_logic(entries, filename):
    """Cross-entry checks for CIDR files: orphan exclusions and overlaps."""
    warnings = []

    allows = [e for e in entries if not e["deny"]]
    denies = [e for e in entries if e["deny"]]

    allow_networks = []
    for e in allows:
        try:
            allow_networks.append((e, ipaddress.ip_network(e["value"], strict=False)))
        except ValueError:
            pass

    deny_networks = []
    for e in denies:
        try:
            deny_networks.append((e, ipaddress.ip_network(e["value"], strict=False)))
        except ValueError:
            pass

    # Orphan exclusion: a deny not contained within any allow CIDR.
    # It's harmless (default-deny already blocks it) but likely a mistake.
    for d_entry, d_net in deny_networks:
        if not any(d_net.subnet_of(a_net) for _, a_net in allow_networks):
            warnings.append(
                f"{filename}:{d_entry['lineno']}: exclusion {d_entry['value']} "
                f"is not contained within any allow CIDR — it has no effect "
                f"(default deny already blocks it)"
            )

    # Overlapping allows: two allow CIDRs where one contains the other.
    # Redundant — the smaller is already covered by the larger.
    for i, (a_entry, a_net) in enumerate(allow_networks):
        for j, (b_entry, b_net) in enumerate(allow_networks):
            if i >= j:
                continue
            if a_net.subnet_of(b_net):
                warnings.append(
                    f"{filename}:{a_entry['lineno']}: {a_entry['value']} is "
                    f"contained within {b_entry['value']} (line {b_entry['lineno']}) "
                    f"— redundant"
                )
            elif b_net.subnet_of(a_net):
                warnings.append(
                    f"{filename}:{b_entry['lineno']}: {b_entry['value']} is "
                    f"contained within {a_entry['value']} (line {a_entry['lineno']}) "
                    f"— redundant"
                )

    return warnings


def main():
    script_dir = Path(__file__).parent
    hosts = Path(sys.argv[1]) if len(sys.argv) > 1 else script_dir / "allowed-hosts.txt"
    cidrs = Path(sys.argv[2]) if len(sys.argv) > 2 else script_dir / "allowed-cidrs.txt"

    all_errors, all_warnings = [], []
    parsed = {}

    for path, ftype in [(hosts, "fqdn"), (cidrs, "cidr")]:
        errs, warns = lint_file(path, ftype)
        all_errors.extend(errs)
        all_warnings.extend(warns)
        parsed[ftype] = _collect_entries(path, ftype)

    for w in all_warnings:
        print(f"  WARN  {w}")
    for e in all_errors:
        print(f" ERROR  {e}")

    if not all_errors:
        fqdn_specs = set(e["ports"] for e in parsed["fqdn"])
        cidr_allow_specs = set(e["ports"] for e in parsed["cidr"] if not e["deny"])
        cidr_deny_specs = set(e["ports"] for e in parsed["cidr"] if e["deny"])
        user_rules = len(fqdn_specs) + len(cidr_allow_specs) + len(cidr_deny_specs)
        # Must match the infra rule count in modules/firewall/main.tf
        total = user_rules + 7
        print(f"\n  Rules: {user_rules} user ({len(fqdn_specs)} FQDN, "
              f"{len(cidr_allow_specs)} CIDR allow, {len(cidr_deny_specs)} CIDR deny) "
              f"+ 7 infrastructure = {total} / 256 GCP limit")

        if not parsed["fqdn"] and not [e for e in parsed["cidr"] if not e["deny"]]:
            all_warnings.append(
                "both allow lists are empty — all user egress is blocked "
                "by the default deny rule"
            )
            print(f"  WARN  {all_warnings[-1]}")

    print(f"\n{len(all_errors)} error(s), {len(all_warnings)} warning(s)")
    sys.exit(1 if all_errors else 0)


def _collect_entries(path, ftype):
    entries = []
    if not path.exists():
        return entries
    for raw in path.read_text().splitlines():
        hash_pos = raw.find("#")
        content = (raw[:hash_pos] if hash_pos != -1 else raw).strip()
        if not content:
            continue
        parts = split_tokens(content)
        if len(parts) < 2:
            continue
        value, ports = parts[0], parts[1]
        is_deny = ftype == "cidr" and value.startswith("-")
        check_val = value[1:] if is_deny else value
        entries.append({"value": check_val, "ports": ports, "deny": is_deny})
    return entries


if __name__ == "__main__":
    main()
