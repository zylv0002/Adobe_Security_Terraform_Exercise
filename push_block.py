#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
push_block.py — Rapid emergency WAF rule push (minimal version)

Covers exercise requirements:
- Accept an IP/CIDR OR a URI regex and push a BLOCK rule into the target WebACL.
- Works for REGIONAL (ALB/APIGW) and CLOUDFRONT (uses us-east-1 endpoint).
- Idempotent upsert of one rule named "CLIBlock" with priority 1.
- Keeps code small and focused (no extra features).

Usage:
  python3 push_block.py --web-acl-arn <ARN> --scope REGIONAL --block-ip 203.0.113.10/32
  python3 push_block.py --web-acl-arn <ARN> --scope REGIONAL --block-uri-regex "^/admin.*$"
"""

import argparse
import re
import sys
import time
import boto3
from botocore.exceptions import ClientError


# ------------------ Args ------------------

def parse_args():
    ap = argparse.ArgumentParser(description="Quickly add a BLOCK rule to an AWS WAFv2 WebACL.")
    ap.add_argument("--web-acl-arn", required=True, help="WebACL ARN (wafv2)")
    ap.add_argument("--scope", required=True, choices=["REGIONAL", "CLOUDFRONT"],
                    help="WAF scope (REGIONAL for ALB/APIGW, CLOUDFRONT for CloudFront)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--block-ip", help="IP/CIDR to block, e.g. 198.51.100.10/32")
    g.add_argument("--block-uri-regex", help="Regex for URI path to block, e.g. ^/admin.*$")
    return ap.parse_args()


# ------------------ AWS helpers ------------------

def waf_client(scope: str):
    """
    Create a WAFv2 client for scope:
    - CLOUDFRONT must use us-east-1
    - REGIONAL uses current default region (None -> from env/config)
    """
    region = "us-east-1" if scope == "CLOUDFRONT" else None
    return boto3.client("wafv2", region_name=region)


def parse_web_acl_arn(arn: str):
    """
    Parse WebACL ARN to get (scope_from_arn, name, id).
    Format: arn:aws:wafv2:<region>:<acct>:<scope>/webacl/<name>/<id>
    """
    try:
        right = arn.split(":", 5)[-1]          # "<scope>/webacl/<name>/<id>"
        parts = right.split("/")
        scope_raw = parts[0].lower()           # "regional" or "global"
        name = parts[2]
        wid = parts[3]
        scope_from_arn = "CLOUDFRONT" if scope_raw == "global" else "REGIONAL"
        return scope_from_arn, name, wid
    except Exception as e:
        raise ValueError(f"Invalid WebACL ARN: {arn} ({e})")


# ------------------ Upserts ------------------

def upsert_ipset(client, scope: str, name: str, addresses):
    """
    Create or update an IPSet named `name` with given addresses.
    Returns the IPSet ARN. Simple, minimal idempotency.
    """
    if not all("/" in a for a in addresses):
        raise ValueError("IP must be CIDR form (e.g., 203.0.113.10/32).")

    listed = client.list_ip_sets(Scope=scope).get("IPSets", [])
    existing = next((x for x in listed if x["Name"] == name), None)

    if existing:
        cur = client.get_ip_set(Name=name, Scope=scope, Id=existing["Id"])
        merged = sorted(set(cur["IPSet"]["Addresses"]) | set(addresses))
        if merged != cur["IPSet"]["Addresses"]:
            client.update_ip_set(Name=name, Scope=scope, Id=existing["Id"],
                                 Addresses=merged, LockToken=cur["LockToken"])
        return cur["IPSet"]["ARN"]
    else:
        created = client.create_ip_set(Name=name, Scope=scope,
                                       Addresses=addresses, IPAddressVersion="IPV4")
        return created["Summary"]["ARN"]


def upsert_regexset(client, scope: str, name: str, patterns):
    """
    Create or update a RegexPatternSet named `name` with given patterns.
    Returns the set ARN. Minimal idempotency.
    """
    # Light validation: ensure regex compiles
    for p in patterns:
        re.compile(p)

    listed = client.list_regex_pattern_sets(Scope=scope).get("RegexPatternSets", [])
    existing = next((x for x in listed if x["Name"] == name), None)

    if existing:
        cur = client.get_regex_pattern_set(Name=name, Scope=scope, Id=existing["Id"])
        merged = sorted(set(cur["RegexPatternSet"]["RegularExpressionList"]) | set(patterns))
        if merged != cur["RegexPatternSet"]["RegularExpressionList"]:
            client.update_regex_pattern_set(Name=name, Scope=scope, Id=existing["Id"],
                                            RegularExpressionList=merged,
                                            LockToken=cur["LockToken"])
        return cur["RegexPatternSet"]["ARN"]
    else:
        created = client.create_regex_pattern_set(Name=name, Scope=scope,
                                                  RegularExpressionList=patterns)
        return created["Summary"]["ARN"]


# ------------------ Rule ensure ------------------

def ensure_block_rule(client, scope: str, web_acl_arn: str, ipset_arn=None, regex_arn=None):
    """
    Ensure a single BLOCK rule named 'CLIBlock' (priority=1) exists with the desired statement.
    Tries once, with one simple retry on OptimisticLockException.
    """
    scope_from_arn, name, wid = parse_web_acl_arn(web_acl_arn)
    if scope_from_arn != scope:
        print(f"[WARN] Scope mismatch: ARN={scope_from_arn}, flag={scope}. Using flag scope: {scope}")

    def build_stmt():
        if ipset_arn:
            return {"IPSetReferenceStatement": {"ARN": ipset_arn}}
        if regex_arn:
            return {
                "RegexPatternSetReferenceStatement": {
                    "ARN": regex_arn,
                    "FieldToMatch": {"UriPath": {}},
                    "TextTransformations": [{"Priority": 0, "Type": "NONE"}],
                }
            }
        raise ValueError("Either ipset_arn or regex_arn must be provided.")

    for attempt in (1, 2):  # try once, then one quick retry if needed
        acl = client.get_web_acl(Name=name, Scope=scope, Id=wid)
        web_acl = acl["WebACL"]
        rules = list(web_acl.get("Rules", []))

        desired = {
            "Name": "CLIBlock",
            "Priority": 1,
            "Action": {"Block": {}},
            "Statement": build_stmt(),
            "VisibilityConfig": {
                "SampledRequestsEnabled": True,
                "CloudWatchMetricsEnabled": True,
                "MetricName": "CLIBlock",
            },
        }

        idx = next((i for i, r in enumerate(rules) if r["Name"] == "CLIBlock"), None)
        if idx is None:
            rules.insert(0, desired)  # put it first for high precedence
        else:
            rules[idx] = desired

        try:
            client.update_web_acl(
                Name=web_acl["Name"],
                Scope=scope,
                Id=web_acl["Id"],
                DefaultAction=web_acl["DefaultAction"],
                VisibilityConfig=web_acl["VisibilityConfig"],
                Rules=rules,
                LockToken=acl["LockToken"],
            )
            return
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code")
            if code == "WAFOptimisticLockException" and attempt == 1:
                time.sleep(0.5)  # quick backoff then retry once
                continue
            raise


# ------------------ Main ------------------

def main():
    args = parse_args()
    client = waf_client(args.scope)

    start = time.time()
    if args.block_ip:
        ipset_arn = upsert_ipset(client, args.scope, "cli-block-ips", [args.block_ip])
        ensure_block_rule(client, args.scope, args.web_acl_arn, ipset_arn=ipset_arn)
        print(f"[OK] IP/CIDR blocked: {args.block_ip}")
    else:
        regex_arn = upsert_regexset(client, args.scope, "cli-block-uri", [args.block_uri_regex])
        ensure_block_rule(client, args.scope, args.web_acl_arn, regex_arn=regex_arn)
        print(f"[OK] URI regex blocked: {args.block_uri_regex!r}")

    print(f"Completed in {time.time() - start:.1f}s")


if __name__ == "__main__":
    main()
