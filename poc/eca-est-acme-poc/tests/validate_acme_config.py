#!/usr/bin/env python3
"""
ACME Agent Configuration Validation Test
=========================================
This test validates the ACME agent configuration file against the JSON schema.

Validation Checks:
1. YAML file exists at specified path
2. YAML is parseable (valid syntax)
3. All required fields are present (pki_url, cert_path, key_path)
4. domain_name field is present (required for ACME agent)
5. Optional fields have correct defaults (renewal_threshold_pct: 75, check_interval_sec: 60)
6. All field values match expected data types
7. No additional properties beyond schema definition
8. Values match expected defaults for Docker environment
"""

import os
import sys
import json
import yaml
from pathlib import Path
from jsonschema import validate, ValidationError, Draft7Validator

# Color codes for terminal output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

def print_success(message):
    print(f"{GREEN}✓{RESET} {message}")

def print_error(message):
    print(f"{RED}✗{RESET} {message}")

def print_info(message):
    print(f"{BLUE}ℹ{RESET} {message}")

def print_warning(message):
    print(f"{YELLOW}⚠{RESET} {message}")

def main():
    """Main validation function"""

    # Define paths relative to project root
    project_root = Path(__file__).parent.parent
    config_path = project_root / "agents" / "acme" / "config.yaml"
    schema_path = project_root / "config" / "agent_config_schema.json"

    print_info("ACME Agent Configuration Validation")
    print_info("=" * 60)
    print()

    all_tests_passed = True

    # Test 1: YAML file exists
    print_info("Test 1: Checking if YAML file exists...")
    if not config_path.exists():
        print_error(f"Configuration file not found at: {config_path}")
        all_tests_passed = False
        return 1
    print_success(f"Configuration file found: {config_path}")
    print()

    # Test 2: YAML is parseable
    print_info("Test 2: Validating YAML syntax...")
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        print_success("YAML syntax is valid")
        print_info(f"Parsed configuration: {json.dumps(config, indent=2)}")
    except yaml.YAMLError as e:
        print_error(f"YAML parsing failed: {e}")
        all_tests_passed = False
        return 1
    print()

    # Test 3: Schema file exists
    print_info("Test 3: Checking if JSON schema exists...")
    if not schema_path.exists():
        print_error(f"Schema file not found at: {schema_path}")
        all_tests_passed = False
        return 1
    print_success(f"Schema file found: {schema_path}")
    print()

    # Load schema
    print_info("Loading JSON schema...")
    try:
        with open(schema_path, 'r') as f:
            schema = json.load(f)
        print_success("JSON schema loaded successfully")
    except json.JSONDecodeError as e:
        print_error(f"Schema parsing failed: {e}")
        all_tests_passed = False
        return 1
    print()

    # Test 4: Required fields present
    print_info("Test 4: Verifying required fields are present...")
    required_fields = ["pki_url", "cert_path", "key_path"]
    for field in required_fields:
        if field in config:
            print_success(f"Required field '{field}' is present: {config[field]}")
        else:
            print_error(f"Required field '{field}' is missing")
            all_tests_passed = False
    print()

    # Test 5: domain_name field present (ACME requirement)
    print_info("Test 5: Verifying domain_name field (required for ACME)...")
    if "domain_name" in config:
        print_success(f"Field 'domain_name' is present: {config['domain_name']}")
    else:
        print_error("Field 'domain_name' is missing (required for ACME agent)")
        all_tests_passed = False
    print()

    # Test 6: Optional fields with defaults
    print_info("Test 6: Verifying optional fields have correct defaults...")
    expected_defaults = {
        "renewal_threshold_pct": 75,
        "check_interval_sec": 60
    }
    for field, expected_value in expected_defaults.items():
        if field in config:
            actual_value = config[field]
            if actual_value == expected_value:
                print_success(f"Field '{field}' has correct default: {actual_value}")
            else:
                print_warning(f"Field '{field}' has non-default value: {actual_value} (expected: {expected_value})")
        else:
            print_warning(f"Optional field '{field}' is not present (will use default: {expected_value})")
    print()

    # Test 7: Docker environment values
    print_info("Test 7: Verifying values match Docker environment defaults...")
    expected_values = {
        "pki_url": "https://pki:9000",
        "cert_path": "/certs/server/server.crt",
        "key_path": "/certs/server/server.key",
        "domain_name": "target-server"
    }
    for field, expected_value in expected_values.items():
        if field in config:
            actual_value = config[field]
            if actual_value == expected_value:
                print_success(f"Field '{field}' matches expected value: {actual_value}")
            else:
                print_warning(f"Field '{field}' has different value: {actual_value} (expected: {expected_value})")
        else:
            print_error(f"Field '{field}' is missing")
            all_tests_passed = False
    print()

    # Test 8: No additional properties
    print_info("Test 8: Checking for additional properties (schema has additionalProperties: false)...")
    allowed_properties = set(schema["properties"].keys())
    actual_properties = set(config.keys())
    extra_properties = actual_properties - allowed_properties
    if extra_properties:
        print_error(f"Configuration contains additional properties not defined in schema: {extra_properties}")
        print_info(f"Allowed properties: {allowed_properties}")
        all_tests_passed = False
    else:
        print_success("No additional properties found (complies with schema)")
    print()

    # Test 9: JSON Schema validation
    print_info("Test 9: Running JSON Schema validation...")
    try:
        validator = Draft7Validator(schema)
        errors = list(validator.iter_errors(config))
        if errors:
            print_error("Schema validation failed with the following errors:")
            for error in errors:
                print_error(f"  - {error.message}")
                if error.path:
                    print_error(f"    Path: {' -> '.join(str(p) for p in error.path)}")
            all_tests_passed = False
        else:
            print_success("Configuration validates successfully against JSON schema")
    except Exception as e:
        print_error(f"Schema validation error: {e}")
        all_tests_passed = False
    print()

    # Test 10: Field type validation
    print_info("Test 10: Verifying field types...")
    type_checks = {
        "pki_url": str,
        "cert_path": str,
        "key_path": str,
        "domain_name": str,
        "renewal_threshold_pct": int,
        "check_interval_sec": int
    }
    for field, expected_type in type_checks.items():
        if field in config:
            actual_value = config[field]
            if isinstance(actual_value, expected_type):
                print_success(f"Field '{field}' has correct type: {expected_type.__name__}")
            else:
                print_error(f"Field '{field}' has incorrect type: {type(actual_value).__name__} (expected: {expected_type.__name__})")
                all_tests_passed = False
    print()

    # Test 11: Range validation for numeric fields
    print_info("Test 11: Validating numeric field ranges...")
    if "renewal_threshold_pct" in config:
        value = config["renewal_threshold_pct"]
        if 1 <= value <= 100:
            print_success(f"Field 'renewal_threshold_pct' is within valid range [1-100]: {value}")
        else:
            print_error(f"Field 'renewal_threshold_pct' is out of range [1-100]: {value}")
            all_tests_passed = False

    if "check_interval_sec" in config:
        value = config["check_interval_sec"]
        if value >= 1:
            print_success(f"Field 'check_interval_sec' is >= 1: {value}")
        else:
            print_error(f"Field 'check_interval_sec' is < 1: {value}")
            all_tests_passed = False
    print()

    # Summary
    print_info("=" * 60)
    if all_tests_passed:
        print_success("All validation tests passed!")
        print_success("Configuration file is valid and complies with schema")
        return 0
    else:
        print_error("Some validation tests failed")
        print_error("Please review the errors above and fix the configuration")
        return 1

if __name__ == "__main__":
    sys.exit(main())
