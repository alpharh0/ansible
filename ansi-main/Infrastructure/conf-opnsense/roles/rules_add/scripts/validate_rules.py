#!/usr/bin/env python3
import sys
import json
import ipaddress
import xml.etree.ElementTree as ET


VALID_ACTIONS = {"pass", "block", "reject"}
VALID_PROTOCOLS = {"TCP", "UDP", "ICMP", "any"}
VALID_DIRECTIONS = {"in", "out"}
SPECIAL_NETS = {"any", "(self)"}


def is_ip_or_network(value: str) -> bool:
    try:
        if "/" in value:
            ipaddress.ip_network(value, strict=False)
        else:
            ipaddress.ip_address(value)
        return True
    except Exception:
        return False


def find_alias_names(root):
    names = set()
    for alias in root.findall(".//aliases/alias"):
        name = alias.findtext("name")
        if name:
            names.add(name.strip())
    return names


def find_gateway_names(root):
    names = set()

    # Common config.xml locations
    for path in [
        ".//gateways/gateway_item",
        ".//gateways/gateway",
        ".//OPNsense/routing/gateways/gateway_item",
        ".//OPNsense/routing/gateways/gateway",
    ]:
        for gw in root.findall(path):
            name = gw.findtext("name")
            if name:
                names.add(name.strip())

    return names


def find_interface_names(root):
    names = set()

    # Standard interface nodes
    interfaces_node = root.find("./interfaces")
    if interfaces_node is not None:
        for child in interfaces_node:
            if child.tag:
                names.add(child.tag.strip())

    # Also include interface labels/descriptions if present
    for path in [".//interfaces/*/if", ".//interfaces/*/descr"]:
        for node in root.findall(path):
            if node.text:
                names.add(node.text.strip())

    return names


def parse_rules(rules_root):
    parsed = []
    for rule in rules_root.findall("./rule"):
        item = {}
        for child in rule:
            item[child.tag] = (child.text or "").strip()
        parsed.append(item)
    return parsed


def validate_rule(rule, aliases, gateways, interfaces, seen_descriptions, seen_sequences):
    errors = []

    description = rule.get("description", "").strip()
    if not description:
        errors.append("missing description")

    enabled = rule.get("enabled", "")
    if enabled and enabled not in {"0", "1"}:
        errors.append(f"invalid enabled value: {enabled}")

    sequence = rule.get("sequence", "").strip()
    if not sequence:
        errors.append("missing sequence")
    else:
        if not sequence.isdigit():
            errors.append(f"invalid sequence: {sequence}")
        elif sequence in seen_sequences:
            errors.append(f"duplicate sequence: {sequence}")

    action = rule.get("action", "").strip()
    if action not in VALID_ACTIONS:
        errors.append(f"invalid action: {action}")

    protocol = rule.get("protocol", "").strip()
    if protocol not in VALID_PROTOCOLS:
        errors.append(f"invalid protocol: {protocol}")

    direction = rule.get("direction", "").strip()
    if direction not in VALID_DIRECTIONS:
        errors.append(f"invalid direction: {direction}")

    interface = rule.get("interface", "").strip()
    if not interface:
        errors.append("missing interface")
    elif interface not in interfaces:
        errors.append(f"interface not found in config.xml: {interface}")

    source_net = rule.get("source_net", "").strip()
    if not source_net:
        errors.append("missing source_net")
    elif source_net not in SPECIAL_NETS and source_net not in aliases and not is_ip_or_network(source_net):
        errors.append(f"source_net not found as alias/IP/network: {source_net}")

    destination_net = rule.get("destination_net", "").strip()
    if not destination_net:
        errors.append("missing destination_net")
    elif destination_net not in SPECIAL_NETS and destination_net not in aliases and not is_ip_or_network(destination_net):
        errors.append(f"destination_net not found as alias/IP/network: {destination_net}")

    destination_port = rule.get("destination_port", "").strip()
    if destination_port:
        if not destination_port.isdigit() and destination_port not in aliases:
            errors.append(f"destination_port not numeric or alias: {destination_port}")

    gateway = rule.get("gateway", "").strip()
    if gateway and gateway not in gateways:
        errors.append(f"gateway not found in config.xml: {gateway}")

    if description:
        if description in seen_descriptions:
            errors.append(f"duplicate description: {description}")
        seen_descriptions.add(description)

    if sequence and sequence.isdigit():
        seen_sequences.add(sequence)

    return errors


def main():
    if len(sys.argv) != 3:
        print("Usage: validate_rules.py <config.xml> <rules.xml>", file=sys.stderr)
        sys.exit(2)

    config_path = sys.argv[1]
    rules_path = sys.argv[2]

    try:
        config_root = ET.parse(config_path).getroot()
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"failed to parse config.xml: {e}"}))
        sys.exit(1)

    try:
        rules_root = ET.parse(rules_path).getroot()
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"failed to parse rules.xml: {e}"}))
        sys.exit(1)

    aliases = find_alias_names(config_root)
    gateways = find_gateway_names(config_root)
    interfaces = find_interface_names(config_root)

    rules = parse_rules(rules_root)
    if not rules:
        print(json.dumps({"ok": False, "error": "no <rule> entries found in rules.xml"}))
        sys.exit(1)

    errors = []
    valid_rules = []
    seen_descriptions = set()
    seen_sequences = set()

    for idx, rule in enumerate(rules, start=1):
        rule_errors = validate_rule(
            rule,
            aliases=aliases,
            gateways=gateways,
            interfaces=interfaces,
            seen_descriptions=seen_descriptions,
            seen_sequences=seen_sequences,
        )
        if rule_errors:
            errors.append({
                "rule_index": idx,
                "description": rule.get("description", ""),
                "errors": rule_errors,
            })
        else:
            valid_rules.append(rule)

    result = {
        "ok": len(errors) == 0,
        "valid_rules": valid_rules,
        "errors": errors,
        "summary": {
            "rule_count": len(rules),
            "valid_count": len(valid_rules),
            "error_count": len(errors),
            "aliases_found": sorted(list(aliases)),
            "gateways_found": sorted(list(gateways)),
            "interfaces_found": sorted(list(interfaces)),
        }
    }

    print(json.dumps(result, indent=2))
    sys.exit(0 if len(errors) == 0 else 1)


if __name__ == "__main__":
    main()