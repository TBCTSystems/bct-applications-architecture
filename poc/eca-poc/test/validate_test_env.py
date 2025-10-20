#!/usr/bin/env python3
"""
Comprehensive validation script for the certificate renewal service test environment.
This script validates the entire test setup and provides detailed feedback.
"""

import os
import sys
import json
import subprocess
import time
import requests
from datetime import datetime
from pathlib import Path

class TestValidator:
    def __init__(self, test_dir="test"):
        self.test_dir = Path(test_dir)
        self.passed_tests = 0
        self.failed_tests = 0
        self.warnings = []
        
    def log_result(self, test_name, passed, message="", warning=False):
        """Log test result."""
        if warning:
            print(f"⚠️  {test_name}: {message}")
            self.warnings.append(f"{test_name}: {message}")
        elif passed:
            print(f"✅ {test_name}")
            self.passed_tests += 1
        else:
            print(f"❌ {test_name}: {message}")
            self.failed_tests += 1
    
    def run_command(self, cmd, cwd=None, timeout=30):
        """Run a command and return the result."""
        try:
            result = subprocess.run(
                cmd, 
                cwd=cwd, 
                capture_output=True, 
                text=True, 
                timeout=timeout
            )
            return result
        except subprocess.TimeoutExpired:
            return None
        except Exception as e:
            print(f"Error running command {' '.join(cmd)}: {e}")
            return None
    
    def check_prerequisites(self):
        """Check if all prerequisites are installed."""
        print("\n🔍 Checking Prerequisites...")
        
        # Check Python
        result = self.run_command(["python", "--version"])
        if result and result.returncode == 0:
            version = result.stdout.strip()
            self.log_result("Python installed", True, version)
        else:
            self.log_result("Python installed", False, "Python not found or not working")
        
        # Check Step CLI
        result = self.run_command(["step", "version"])
        if result and result.returncode == 0:
            version = result.stdout.strip().split('\n')[0]
            self.log_result("Step CLI installed", True, version)
        else:
            self.log_result("Step CLI installed", False, "Step CLI not found")
        
        # Check Docker
        result = self.run_command(["docker", "--version"])
        if result and result.returncode == 0:
            version = result.stdout.strip()
            self.log_result("Docker installed", True, version)
        else:
            self.log_result("Docker installed", False, "Docker not found")
        
        # Check Docker Compose
        result = self.run_command(["docker-compose", "--version"])
        if result and result.returncode == 0:
            version = result.stdout.strip()
            self.log_result("Docker Compose installed", True, version)
        else:
            self.log_result("Docker Compose installed", False, "Docker Compose not found")
    
    def check_directory_structure(self):
        """Check if test directories exist."""
        print("\n📁 Checking Directory Structure...")
        
        required_dirs = [
            "test",
            "test/step-ca",
            "test/dummy-certs", 
            "test/client-certs",
            "test/test-config",
            "test/logs"
        ]
        
        for dir_path in required_dirs:
            if Path(dir_path).exists():
                self.log_result(f"Directory {dir_path}", True)
            else:
                self.log_result(f"Directory {dir_path}", False, "Directory does not exist")
    
    def check_configuration_files(self):
        """Check if configuration files exist and are valid."""
        print("\n⚙️  Checking Configuration Files...")
        
        config_files = [
            "test/docker-compose.test.yml",
            "test/test-config/config.yaml",
            "test/generate_dummy_certs.py",
            "test/test_runner.py",
            "test/init-step-ca.ps1",
            "test/README.md"
        ]
        
        for file_path in config_files:
            if Path(file_path).exists():
                self.log_result(f"File {file_path}", True)
            else:
                self.log_result(f"File {file_path}", False, "File does not exist")
    
    def check_dummy_certificates(self):
        """Check if dummy certificates exist and are valid."""
        print("\n🔐 Checking Dummy Certificates...")
        
        cert_files = [
            "test/dummy-certs/ca.crt",
            "test/dummy-certs/ca.key",
            "test/dummy-certs/test-web-server.crt",
            "test/dummy-certs/test-web-server.key",
            "test/dummy-certs/test-api-server.crt",
            "test/dummy-certs/test-api-server.key",
            "test/dummy-certs/test-expiring-soon.crt",
            "test/dummy-certs/test-expiring-soon.key"
        ]
        
        for file_path in cert_files:
            if Path(file_path).exists():
                self.log_result(f"Certificate {Path(file_path).name}", True)
            else:
                self.log_result(f"Certificate {Path(file_path).name}", False, "Certificate file does not exist")
        
        # Check certificate validity if openssl is available
        result = self.run_command(["openssl", "version"])
        if result and result.returncode == 0:
            for cert_file in [f for f in cert_files if f.endswith('.crt') and Path(f).exists()]:
                result = self.run_command(["openssl", "x509", "-in", cert_file, "-noout", "-dates"])
                if result and result.returncode == 0:
                    self.log_result(f"Certificate validity {Path(cert_file).name}", True)
                else:
                    self.log_result(f"Certificate validity {Path(cert_file).name}", False, "Invalid certificate format")
    
    def check_step_ca_configuration(self):
        """Check Step CA configuration."""
        print("\n🏛️  Checking Step CA Configuration...")
        
        step_ca_files = [
            "test/step-ca/config/ca.json",
            "test/step-ca/certs/root_ca.crt",
            "test/step-ca/secrets/root_ca_key"
        ]
        
        for file_path in step_ca_files:
            if Path(file_path).exists():
                self.log_result(f"Step CA {Path(file_path).name}", True)
            else:
                self.log_result(f"Step CA {Path(file_path).name}", False, "Step CA not initialized")
        
        # Check CA fingerprint file
        fingerprint_file = "test/ca-fingerprint.txt"
        if Path(fingerprint_file).exists():
            self.log_result("CA fingerprint file", True)
        else:
            self.log_result("CA fingerprint file", False, "Fingerprint file not found")
    
    def check_docker_services(self):
        """Check Docker services status."""
        print("\n🐳 Checking Docker Services...")
        
        # Check if Docker is running
        result = self.run_command(["docker", "info"])
        if not result or result.returncode != 0:
            self.log_result("Docker daemon", False, "Docker daemon not running")
            return
        
        self.log_result("Docker daemon", True)
        
        # Check for test containers
        result = self.run_command(["docker", "ps", "-a", "--format", "json"])
        if result and result.returncode == 0:
            try:
                containers = []
                for line in result.stdout.strip().split('\n'):
                    if line.strip():
                        containers.append(json.loads(line))
                
                step_ca_container = None
                for container in containers:
                    if 'step-ca-test' in container.get('Names', ''):
                        step_ca_container = container
                        break
                
                if step_ca_container:
                    status = step_ca_container.get('State', 'unknown')
                    self.log_result(f"Step CA container", True, f"Status: {status}")
                else:
                    self.log_result("Step CA container", False, "Container not found")
                    
            except json.JSONDecodeError:
                self.log_result("Docker container check", False, "Could not parse docker output")
    
    def check_service_connectivity(self):
        """Check if services are accessible."""
        print("\n🌐 Checking Service Connectivity...")
        
        # Check Step CA endpoint
        try:
            # Disable SSL verification for test CA
            response = requests.get("https://localhost:9000/health", verify=False, timeout=10)
            if response.status_code == 200:
                self.log_result("Step CA endpoint", True, "Responding to health checks")
            else:
                self.log_result("Step CA endpoint", False, f"HTTP {response.status_code}")
        except requests.exceptions.ConnectionError:
            self.log_result("Step CA endpoint", False, "Connection refused")
        except requests.exceptions.Timeout:
            self.log_result("Step CA endpoint", False, "Connection timeout")
        except Exception as e:
            self.log_result("Step CA endpoint", False, f"Error: {str(e)}")
    
    def check_python_dependencies(self):
        """Check if required Python packages are installed."""
        print("\n🐍 Checking Python Dependencies...")
        
        required_packages = [
            "cryptography",
            "pydantic", 
            "pyyaml",
            "requests",
            "python-dotenv"
        ]
        
        for package in required_packages:
            result = self.run_command(["python", "-c", f"import {package}"])
            if result and result.returncode == 0:
                self.log_result(f"Python package {package}", True)
            else:
                self.log_result(f"Python package {package}", False, "Package not installed")
    
    def run_service_tests(self):
        """Run basic service functionality tests."""
        print("\n🧪 Running Service Tests...")
        
        # Test service initialization
        result = self.run_command([
            "python", "main.py", 
            "--config", "test/test-config/config.yaml", 
            "init"
        ])
        
        if result and result.returncode == 0:
            self.log_result("Service initialization", True)
        else:
            self.log_result("Service initialization", False, "Init command failed")
        
        # Test status command
        result = self.run_command([
            "python", "main.py",
            "--config", "test/test-config/config.yaml",
            "status"
        ])
        
        if result and result.returncode == 0:
            self.log_result("Status command", True)
        else:
            self.log_result("Status command", False, "Status command failed")
    
    def run_all_checks(self):
        """Run all validation checks."""
        print("🚀 Certificate Renewal Service - Test Environment Validation")
        print("=" * 70)
        
        self.check_prerequisites()
        self.check_directory_structure()
        self.check_configuration_files()
        self.check_dummy_certificates()
        self.check_step_ca_configuration()
        self.check_python_dependencies()
        self.check_docker_services()
        self.check_service_connectivity()
        self.run_service_tests()
        
        # Summary
        print("\n📊 Validation Summary")
        print("=" * 30)
        print(f"✅ Passed: {self.passed_tests}")
        print(f"❌ Failed: {self.failed_tests}")
        print(f"⚠️  Warnings: {len(self.warnings)}")
        
        if self.warnings:
            print("\nWarnings:")
            for warning in self.warnings:
                print(f"  ⚠️  {warning}")
        
        print(f"\nTotal: {self.passed_tests + self.failed_tests}")
        
        if self.failed_tests == 0:
            print("\n🎉 All validations passed! Test environment is ready.")
            return 0
        else:
            print("\n❌ Some validations failed. Please check the issues above.")
            return 1

def main():
    """Main entry point."""
    validator = TestValidator()
    return validator.run_all_checks()

if __name__ == "__main__":
    sys.exit(main())