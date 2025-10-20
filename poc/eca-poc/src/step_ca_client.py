"""
Step CA client for certificate renewal operations.
"""
import os
import json
import subprocess
import tempfile
from typing import Optional, Dict, Any, List
from pathlib import Path

from .config import StepCAConfig, CertificateConfig
from .logger import ServiceLogger
from .est_client import ESTClient


class StepCAClient:
    """Client for interacting with Step CA for certificate operations."""
    
    def __init__(self, step_config: StepCAConfig, logger: ServiceLogger):
        self.config = step_config
        self.logger = logger
        
        # Initialize protocol-specific clients
        if self.config.protocol.upper() == "EST":
            self.est_client = ESTClient(step_config, logger)
            self._step_cli_path = None  # EST doesn't need step CLI
            self.logger.info("Initialized EST client")
        else:
            self.est_client = None
            self._step_cli_path = self._find_step_cli()
            self.logger.info("Initialized JWK client with Step CLI")
    
    def _find_step_cli(self) -> str:
        """Find the step CLI executable."""
        # Common locations for step CLI
        possible_paths = [
            "step",  # In PATH
            "/usr/local/bin/step",
            "/usr/bin/step",
            "C:\\Program Files\\step\\bin\\step.exe",
            "step.exe"  # Windows
        ]
        
        for path in possible_paths:
            try:
                result = subprocess.run([path, "version"], 
                                      capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    self.logger.info(f"Found step CLI at: {path}")
                    return path
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                continue
        
        raise RuntimeError("Step CLI not found. Please install step-cli and ensure it's in PATH.")
    
    def _run_step_command(self, args: List[str], input_data: Optional[str] = None) -> Dict[str, Any]:
        """Run a step CLI command and return the result."""
        cmd = [self._step_cli_path] + args
        
        try:
            self.logger.debug(f"Running step command: {' '.join(cmd)}")
            
            # Use UTF-8 encoding and handle Windows encoding issues
            result = subprocess.run(
                cmd,
                input=input_data,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='replace',  # Replace problematic characters
                timeout=60
            )
            
            stdout = result.stdout.strip() if result.stdout else ""
            stderr = result.stderr.strip() if result.stderr else ""
            
            return {
                "success": result.returncode == 0,
                "stdout": stdout,
                "stderr": stderr,
                "returncode": result.returncode
            }
            
        except subprocess.TimeoutExpired:
            self.logger.error("Step command timed out")
            return {
                "success": False,
                "stdout": "",
                "stderr": "Command timed out",
                "returncode": -1
            }
        except Exception as e:
            self.logger.error(f"Error running step command: {str(e)}")
            return {
                "success": False,
                "stdout": "",
                "stderr": str(e),
                "returncode": -1
            }
    
    def bootstrap_ca(self) -> bool:
        """Bootstrap the CA configuration."""
        if self.config.protocol.upper() == "EST":
            # For EST, verify connectivity instead of bootstrapping
            self.logger.info("Verifying EST server connectivity")
            return self.est_client.verify_connectivity()
        else:
            # JWK/Step CA bootstrap
            return self._bootstrap_ca_jwk()
    
    def _bootstrap_ca_jwk(self) -> bool:
        """Bootstrap Step CA configuration for JWK."""
        self.logger.info("Bootstrapping Step CA configuration")
        
        args = [
            "ca", "bootstrap",
            "--ca-url", self.config.ca_url,
            "--fingerprint", self.config.ca_fingerprint,
            "--force"
        ]
        
        result = self._run_step_command(args)
        
        if result["success"]:
            self.logger.info("Successfully bootstrapped CA configuration")
            return True
        else:
            self.logger.error(f"Failed to bootstrap CA: {result['stderr']}")
            return False
    
    def get_provisioner_token(self, subject: str, sans: Optional[List[str]] = None) -> Optional[str]:
        """Get a provisioner token for certificate request."""
        self.logger.debug(f"Getting provisioner token for subject: {subject}")
        
        args = [
            "ca", "token",
            subject,
            "--provisioner", self.config.provisioner_name
        ]
        
        # Add SANs if provided
        if sans:
            for san in sans:
                args.extend(["--san", san])
        
        # Handle provisioner password
        input_data = None
        temp_password_file = None
        
        if self.config.provisioner_password:
            try:
                # Create a temporary password file (more reliable than stdin on Windows)
                import tempfile
                temp_password_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.pwd')
                temp_password_file.write(self.config.provisioner_password)
                temp_password_file.close()
                
                args.extend(["--password-file", temp_password_file.name])
                self.logger.debug(f"Using temporary password file: {temp_password_file.name}")
                
            except Exception as e:
                self.logger.warning(f"Failed to create temp password file, falling back to stdin: {e}")
                # Fallback to stdin method
                args.extend(["--password-file", "-"])
                input_data = self.config.provisioner_password
        
        try:
            result = self._run_step_command(args, input_data=input_data)
        finally:
            # Clean up temporary password file
            if temp_password_file:
                try:
                    os.unlink(temp_password_file.name)
                except Exception as e:
                    self.logger.debug(f"Failed to clean up temp password file: {e}")
        
        if result["success"]:
            token = result["stdout"]
            self.logger.debug("Successfully obtained provisioner token")
            return token
        else:
            self.logger.error(f"Failed to get provisioner token: {result['stderr']}")
            return None
    
    def request_certificate(self, cert_config: CertificateConfig, 
                          output_cert_path: str, output_key_path: str) -> bool:
        """Request a new certificate from Step CA."""
        self.logger.info(f"Requesting new certificate for: {cert_config.subject}")
        
        # Route to appropriate protocol handler
        if self.config.protocol.upper() == "EST":
            return self.est_client.enroll_certificate(cert_config, output_cert_path, output_key_path)
        else:
            # JWK/Step CA native method
            return self._request_certificate_jwk(cert_config, output_cert_path, output_key_path)
    
    def _request_certificate_jwk(self, cert_config: CertificateConfig, 
                               output_cert_path: str, output_key_path: str) -> bool:
        """Request certificate using JWK provisioner and Step CLI."""
        # Get provisioner token
        token = self.get_provisioner_token(cert_config.subject, cert_config.sans)
        if not token:
            return False
        
        # Prepare certificate request
        args = [
            "ca", "certificate",
            cert_config.subject,
            output_cert_path,
            output_key_path,
            "--token", token,
            "--force"  # Overwrite existing files
        ]
        
        result = self._run_step_command(args)
        
        if result["success"]:
            self.logger.info(f"Successfully obtained certificate for {cert_config.subject}")
            return True
        else:
            self.logger.error(f"Failed to request certificate: {result['stderr']}")
            return False
    
    def renew_certificate(self, cert_config: CertificateConfig) -> bool:
        """Renew an existing certificate."""
        self.logger.info(f"Renewing certificate: {cert_config.name}")
        
        # Route to appropriate protocol handler
        if self.config.protocol.upper() == "EST":
            return self.est_client.renew_certificate(cert_config)
        else:
            # JWK/Step CA native method
            return self._renew_certificate_jwk(cert_config)
    
    def _renew_certificate_jwk(self, cert_config: CertificateConfig) -> bool:
        """Renew certificate using JWK provisioner and Step CLI."""
        # Check if current certificate exists
        if not os.path.exists(cert_config.cert_path):
            self.logger.error(f"Current certificate not found: {cert_config.cert_path}")
            return False
        
        if not os.path.exists(cert_config.key_path):
            self.logger.error(f"Current key not found: {cert_config.key_path}")
            return False
        
        # Create backup of current certificate
        backup_cert_path = f"{cert_config.cert_path}.backup"
        backup_key_path = f"{cert_config.key_path}.backup"
        
        try:
            import shutil
            shutil.copy2(cert_config.cert_path, backup_cert_path)
            shutil.copy2(cert_config.key_path, backup_key_path)
            self.logger.debug("Created backup of current certificate")
        except Exception as e:
            self.logger.warning(f"Failed to create backup: {str(e)}")
        
        # Try renewal using existing certificate
        args = [
            "ca", "renew",
            cert_config.cert_path,
            cert_config.key_path,
            "--force"
        ]
        
        result = self._run_step_command(args)
        
        if result["success"]:
            self.logger.info(f"Successfully renewed certificate: {cert_config.name}")
            # Remove backups on success
            try:
                os.remove(backup_cert_path)
                os.remove(backup_key_path)
            except:
                pass
            return True
        else:
            self.logger.warning(f"Renewal failed, trying fresh certificate request: {result['stderr']}")
            
            # Restore backups
            try:
                shutil.copy2(backup_cert_path, cert_config.cert_path)
                shutil.copy2(backup_key_path, cert_config.key_path)
            except:
                pass
            
            # Try requesting a fresh certificate
            return self.request_certificate(cert_config, cert_config.cert_path, cert_config.key_path)
    
    def verify_certificate(self, cert_path: str) -> bool:
        """Verify a certificate against the CA."""
        self.logger.debug(f"Verifying certificate: {cert_path}")
        
        if not os.path.exists(cert_path):
            self.logger.error(f"Certificate file not found: {cert_path}")
            return False
        
        args = [
            "certificate", "verify",
            cert_path,
            "--roots", self.config.root_cert_path
        ]
        
        result = self._run_step_command(args)
        
        if result["success"]:
            self.logger.debug("Certificate verification successful")
            return True
        else:
            self.logger.error(f"Certificate verification failed: {result['stderr']}")
            return False
    
    def get_ca_info(self) -> Optional[Dict[str, Any]]:
        """Get information about the CA."""
        self.logger.debug("Getting CA information")
        
        if self.config.protocol.upper() == "EST":
            # For EST, test connectivity by getting CA certificates
            if self.est_client.verify_connectivity():
                return {
                    "status": "healthy", 
                    "protocol": "EST",
                    "message": "EST server is accessible"
                }
            else:
                return {"status": "unhealthy", "protocol": "EST", "message": "EST server not accessible"}
        else:
            # JWK/Step CA health check
            return self._get_ca_info_jwk()
    
    def _get_ca_info_jwk(self) -> Optional[Dict[str, Any]]:
        """Get CA info using Step CA health endpoint."""
        args = ["ca", "health"]
        result = self._run_step_command(args)
        
        if result["success"]:
            try:
                # Parse JSON output if available
                if result["stdout"].startswith("{"):
                    info = json.loads(result["stdout"])
                    info["protocol"] = "JWK"
                    return info
                else:
                    return {"status": "healthy", "protocol": "JWK", "message": result["stdout"]}
            except json.JSONDecodeError:
                return {"status": "unknown", "protocol": "JWK", "message": result["stdout"]}
        else:
            self.logger.error(f"Failed to get CA info: {result['stderr']}")
            return None