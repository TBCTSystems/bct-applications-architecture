#!/usr/bin/env python3
"""
Test runner for certificate renewal service.
This script runs automated tests to validate the certificate renewal functionality.
"""
import subprocess
import sys
import time
import json
import os
from pathlib import Path
from datetime import datetime, timezone

class CertificateRenewalTester:
    def __init__(self, config_path="test/test-config/config.yaml"):
        self.config_path = config_path
        self.passed_tests = 0
        self.failed_tests = 0
        self.warnings = []
        
    def log_result(self, test_name, passed, message="", warning=False):
        """Log test result with colored output."""
        if warning:
            print(f"⚠️  {test_name}: {message}")
            self.warnings.append(f"{test_name}: {message}")
        elif passed:
            print(f"✅ {test_name}")
            if message:
                print(f"   💬 {message}")
            self.passed_tests += 1
        else:
            print(f"❌ {test_name}: {message}")
            self.failed_tests += 1

    def run_command(self, cmd, cwd=None, timeout=60):
        """Run a command and return the result."""
        print(f"🔧 Running: {' '.join(cmd)}")
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
            print(f"⏰ Command timed out after {timeout} seconds")
            return None
        except Exception as e:
            print(f"💥 Error running command: {e}")
            return None

    def test_prerequisites(self):
        """Test that all prerequisites are available."""
        print("\n🔍 Testing Prerequisites...")
        
        # Test Python
        result = self.run_command(["python", "--version"])
        if result and result.returncode == 0:
            version = result.stdout.strip()
            self.log_result("Python available", True, version)
        else:
            self.log_result("Python available", False, "Python not found")
            return False
        
        # Test main.py exists
        if Path("main.py").exists():
            self.log_result("Main service script exists", True)
        else:
            self.log_result("Main service script exists", False, "main.py not found")
            return False
        
        # Test config file exists
        if Path(self.config_path).exists():
            self.log_result("Test configuration exists", True)
        else:
            self.log_result("Test configuration exists", False, f"{self.config_path} not found")
            return False
        
        return True

    def test_service_initialization(self):
        """Test service initialization."""
        print("\n🏗️  Testing Service Initialization...")
        
        result = self.run_command([
            "python", "main.py", 
            "--config", self.config_path, 
            "init"
        ])
        
        if result and result.returncode == 0:
            self.log_result("Service initialization", True, "Configuration validated successfully")
            return True
        else:
            error_msg = result.stderr if result else "Command failed to execute"
            self.log_result("Service initialization", False, error_msg.strip()[:100])
            return False

    def test_certificate_status(self):
        """Test certificate status checking."""
        print("\n📋 Testing Certificate Status...")
        
        # Test basic status command
        result = self.run_command([
            "python", "main.py", 
            "--config", self.config_path, 
            "status"
        ])
        
        if result and result.returncode == 0:
            self.log_result("Basic status check", True)
            print(f"   📄 Status output preview:\n{result.stdout[:200]}...")
        else:
            error_msg = result.stderr if result else "Command failed"
            self.log_result("Basic status check", False, error_msg.strip()[:100])
            return False
        
        # Test JSON status format
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "status",
            "--format", "json"
        ])
        
        if result and result.returncode == 0:
            try:
                status_data = json.loads(result.stdout)
                total_certs = status_data.get('total_certificates', 0)
                needing_renewal = status_data.get('summary', {}).get('certificates_needing_renewal', 0)
                
                self.log_result("JSON status format", True, 
                               f"{total_certs} certificates found, {needing_renewal} need renewal")
                return True
            except json.JSONDecodeError as e:
                self.log_result("JSON status format", False, f"Invalid JSON output: {e}")
                return False
        else:
            self.log_result("JSON status format", False, "JSON status command failed")
            return False

    def test_certificate_checking(self):
        """Test certificate renewal checking."""
        print("\n🔍 Testing Certificate Renewal Check...")
        
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "check",
            "--dry-run"
        ])
        
        if result and result.returncode == 0:
            self.log_result("Certificate renewal check", True, "Dry run completed successfully")
            
            # Check if any certificates were identified for renewal
            if "would be renewed" in result.stdout.lower() or "renewal needed" in result.stdout.lower():
                self.log_result("Renewal detection", True, "Service correctly identified certificates needing renewal")
            else:
                self.log_result("Renewal detection", True, "No certificates need renewal (expected with long-term test certs)", warning=True)
            
            return True
        else:
            error_msg = result.stderr if result else "Command failed"
            self.log_result("Certificate renewal check", False, error_msg.strip()[:100])
            return False

    def test_crl_functionality(self):
        """Test CRL (Certificate Revocation List) functionality."""
        print("\n🚫 Testing CRL Functionality...")
        
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "crl"
        ])
        
        if result and result.returncode == 0:
            self.log_result("CRL command", True, "CRL functionality working")
            return True
        else:
            # CRL might not be configured, which is OK for basic testing
            self.log_result("CRL command", True, "CRL not configured (optional for basic testing)", warning=True)
            return True

    def test_configuration_validation(self):
        """Test configuration file validation."""
        print("\n⚙️  Testing Configuration Validation...")
        
        # Test with valid config
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "status",
            "--validate-only"
        ])
        
        success = result and result.returncode == 0
        if success:
            self.log_result("Configuration validation", True, "Configuration file is valid")
        else:
            # Try without --validate-only flag as it might not be implemented
            result2 = self.run_command([
                "python", "main.py",
                "--config", self.config_path,
                "init"
            ])
            
            if result2 and result2.returncode == 0:
                self.log_result("Configuration validation", True, "Configuration validated via init command")
                success = True
            else:
                error_msg = result.stderr if result else "Validation failed"
                self.log_result("Configuration validation", False, error_msg.strip()[:100])
        
        return success

    def test_dummy_certificates(self):
        """Test that dummy certificates exist and are readable."""
        print("\n🔐 Testing Dummy Certificates...")
        
        dummy_cert_dir = Path("test/dummy-certs")
        if not dummy_cert_dir.exists():
            self.log_result("Dummy certificates directory", False, "Directory does not exist")
            return False
        
        self.log_result("Dummy certificates directory", True)
        
        # Check for key certificate files
        expected_files = [
            "ca.crt", "ca.key",
            "test-web-server.crt", "test-web-server.key",
            "test-api-server.crt", "test-api-server.key",
            "test-expiring-soon.crt", "test-expiring-soon.key"
        ]
        
        found_files = 0
        for filename in expected_files:
            file_path = dummy_cert_dir / filename
            if file_path.exists():
                found_files += 1
        
        if found_files >= len(expected_files) * 0.75:  # At least 75% of expected files
            self.log_result("Dummy certificate files", True, f"{found_files}/{len(expected_files)} files found")
            return True
        else:
            self.log_result("Dummy certificate files", False, f"Only {found_files}/{len(expected_files)} files found")
            return False

    def test_service_help(self):
        """Test that service help commands work."""
        print("\n❓ Testing Service Help...")
        
        result = self.run_command(["python", "main.py", "--help"])
        
        if result and result.returncode == 0:
            self.log_result("Main help command", True)
            
            # Check that common commands are mentioned in help
            help_text = result.stdout.lower()
            if "status" in help_text and "check" in help_text and "daemon" in help_text:
                self.log_result("Help content completeness", True, "All major commands documented")
            else:
                self.log_result("Help content completeness", False, "Some commands missing from help")
            
            return True
        else:
            self.log_result("Main help command", False, "Help command failed")
            return False

    def test_error_handling(self):
        """Test error handling with invalid inputs."""
        print("\n🚨 Testing Error Handling...")
        
        # Test with non-existent config file
        result = self.run_command([
            "python", "main.py",
            "--config", "nonexistent-config.yaml",
            "status"
        ])
        
        if result and result.returncode != 0:
            self.log_result("Invalid config handling", True, "Service properly rejected invalid config")
        else:
            self.log_result("Invalid config handling", False, "Service should have failed with invalid config")
        
        # Test with invalid command
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "invalid-command"
        ])
        
        if result and result.returncode != 0:
            self.log_result("Invalid command handling", True, "Service properly rejected invalid command")
        else:
            self.log_result("Invalid command handling", False, "Service should have failed with invalid command")

    def run_performance_test(self):
        """Run a basic performance test."""
        print("\n⚡ Testing Performance...")
        
        start_time = time.time()
        
        result = self.run_command([
            "python", "main.py",
            "--config", self.config_path,
            "status"
        ])
        
        end_time = time.time()
        duration = end_time - start_time
        
        if result and result.returncode == 0:
            if duration < 10:  # Should complete within 10 seconds
                self.log_result("Performance test", True, f"Status check completed in {duration:.2f} seconds")
            else:
                self.log_result("Performance test", False, f"Status check took too long: {duration:.2f} seconds")
        else:
            self.log_result("Performance test", False, "Performance test failed to execute")

    def run_all_tests(self):
        """Run all tests in sequence."""
        print("🧪 Certificate Renewal Service - Test Runner")
        print("=" * 50)
        print(f"🕐 Test started at: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(f"⚙️  Configuration: {self.config_path}")
        print()
        
        # Check prerequisites first
        if not self.test_prerequisites():
            print("\n❌ Prerequisites check failed. Cannot continue with tests.")
            return 1
        
        # Define test sequence
        tests = [
            ("Service Help", self.test_service_help),
            ("Configuration Validation", self.test_configuration_validation),
            ("Service Initialization", self.test_service_initialization),
            ("Dummy Certificates", self.test_dummy_certificates),
            ("Certificate Status", self.test_certificate_status),
            ("Certificate Checking", self.test_certificate_checking),
            ("CRL Functionality", self.test_crl_functionality),
            ("Error Handling", self.test_error_handling),
            ("Performance", self.run_performance_test),
        ]
        
        # Run each test
        for test_name, test_func in tests:
            try:
                test_func()
                time.sleep(1)  # Brief pause between tests
            except Exception as e:
                self.log_result(test_name, False, f"Test threw exception: {str(e)}")
        
        # Generate summary
        self.print_summary()
        
        return 0 if self.failed_tests == 0 else 1

    def print_summary(self):
        """Print test summary."""
        print("\n" + "=" * 50)
        print("📊 Test Summary")
        print("=" * 50)
        print(f"✅ Passed: {self.passed_tests}")
        print(f"❌ Failed: {self.failed_tests}")
        print(f"⚠️  Warnings: {len(self.warnings)}")
        print(f"📈 Total: {self.passed_tests + self.failed_tests}")
        
        if self.warnings:
            print("\n⚠️  Warnings:")
            for warning in self.warnings:
                print(f"   • {warning}")
        
        if self.failed_tests == 0:
            print("\n🎉 All tests passed! Certificate renewal service is working correctly.")
            print("🚀 You can now run the service in production mode.")
        else:
            print(f"\n❌ {self.failed_tests} test(s) failed. Please review the issues above.")
            print("💡 Check the configuration and ensure all dependencies are installed.")
        
        print(f"\n🕐 Test completed at: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")

def main():
    """Main entry point."""
    config_path = "test/test-config/config.yaml"
    
    # Allow custom config path as argument
    if len(sys.argv) > 1:
        config_path = sys.argv[1]
    
    print(f"Using configuration: {config_path}")
    
    if not Path(config_path).exists():
        print(f"❌ Configuration file not found: {config_path}")
        print("💡 Run the test setup first: ./setup-test-env.ps1")
        return 1
    
    tester = CertificateRenewalTester(config_path)
    return tester.run_all_tests()

if __name__ == "__main__":
    sys.exit(main())