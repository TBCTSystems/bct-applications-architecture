"""
Main certificate renewal service.
"""
import os
import time
import signal
import sys
from typing import List
from datetime import datetime, timedelta, timezone

from .config import ServiceConfig, load_config
from .logger import ServiceLogger
from .certificate_monitor import CertificateMonitor, CertificateStatus
from .step_ca_client import StepCAClient


class CertificateRenewalService:
    """Main service for automatic certificate renewal."""
    
    def __init__(self, config_file: str = "config/config.yaml"):
        self.config = load_config(config_file)
        self.logger = ServiceLogger(
            log_level=self.config.log_level,
            log_file=self.config.log_file
        )
        
        self.monitor = CertificateMonitor(self.logger, self.config.step_ca, self.config)
        self.step_client = StepCAClient(self.config.step_ca, self.logger)
        
        self.running = False
        self._setup_signal_handlers()
    
    def _setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown."""
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals."""
        self.logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False
    
    def initialize(self) -> bool:
        """Initialize the service and verify Step CA connectivity."""
        self.logger.info("Initializing Certificate Renewal Service")
        
        # Create necessary directories
        os.makedirs(self.config.cert_storage_path, exist_ok=True)
        os.makedirs(os.path.dirname(self.config.log_file), exist_ok=True)
        
        # Bootstrap Step CA if needed
        if not self.step_client.bootstrap_ca():
            self.logger.error("Failed to bootstrap Step CA configuration")
            return False
        
        # Verify CA connectivity
        ca_info = self.step_client.get_ca_info()
        if ca_info is None:
            self.logger.error("Cannot connect to Step CA")
            return False
        
        self.logger.info(f"Step CA connection verified: {ca_info}")
        
        # Validate certificate configurations
        if not self.config.certificates:
            self.logger.warning("No certificates configured for monitoring")
        
        for cert_config in self.config.certificates:
            # Ensure certificate directories exist
            cert_dir = os.path.dirname(cert_config.cert_path)
            key_dir = os.path.dirname(cert_config.key_path)
            
            os.makedirs(cert_dir, exist_ok=True)
            os.makedirs(key_dir, exist_ok=True)
        
        self.logger.info("Service initialization completed successfully")
        return True
    
    def check_and_renew_certificates(self) -> List[CertificateStatus]:
        """Check all certificates and renew those that need it."""
        self.logger.info("Starting certificate check and renewal cycle")
        
        # Check certificate statuses
        statuses = self.monitor.check_all_certificates(self.config.certificates)
        
        # Process certificates that need renewal
        renewal_attempts = []
        for status in statuses:
            if status.needs_renewal:
                cert_config = next(
                    (cert for cert in self.config.certificates if cert.name == status.name),
                    None
                )
                
                if cert_config:
                    self.logger.info(f"Attempting to renew certificate: {status.name}")
                    
                    try:
                        if self.step_client.renew_certificate(cert_config):
                            self.logger.info(f"Successfully renewed certificate: {status.name}")
                            
                            # Verify the renewed certificate
                            if self.step_client.verify_certificate(cert_config.cert_path):
                                self.logger.info(f"Renewed certificate verified: {status.name}")
                                
                                # Update status to reflect successful renewal
                                status.needs_renewal = False
                                status.error_message = None
                            else:
                                self.logger.error(f"Renewed certificate failed verification: {status.name}")
                                status.error_message = "Certificate verification failed after renewal"
                        else:
                            self.logger.error(f"Failed to renew certificate: {status.name}")
                            status.error_message = "Certificate renewal failed"
                    
                    except Exception as e:
                        error_msg = f"Exception during certificate renewal: {str(e)}"
                        self.logger.error(error_msg)
                        status.error_message = error_msg
                    
                    renewal_attempts.append(status)
        
        # Log summary
        total_renewals = len(renewal_attempts)
        successful_renewals = sum(1 for s in renewal_attempts if not s.needs_renewal)
        
        self.logger.info(
            f"Renewal cycle completed: {successful_renewals}/{total_renewals} "
            f"certificates renewed successfully"
        )
        
        return statuses
    
    def run_once(self) -> bool:
        """Run a single check and renewal cycle."""
        try:
            self.check_and_renew_certificates()
            return True
        except Exception as e:
            self.logger.error(f"Error during certificate check cycle: {str(e)}")
            return False
    
    def run_daemon(self):
        """Run the service as a daemon with periodic checks."""
        self.logger.info(
            f"Starting certificate renewal daemon "
            f"(check interval: {self.config.check_interval_minutes} minutes)"
        )
        
        self.running = True
        
        while self.running:
            try:
                # Run certificate check and renewal
                self.run_once()
                
                # Sleep until next check (but wake up every minute to check for shutdown)
                sleep_time = self.config.check_interval_minutes * 60  # Convert to seconds
                end_time = time.time() + sleep_time
                
                while time.time() < end_time and self.running:
                    time.sleep(60)  # Sleep for 1 minute intervals
                
            except Exception as e:
                self.logger.error(f"Unexpected error in daemon loop: {str(e)}")
                if self.running:
                    self.logger.info("Continuing after error...")
                    time.sleep(300)  # Wait 5 minutes before retrying
        
        self.logger.info("Certificate renewal daemon stopped")
    
    def status_report(self) -> dict:
        """Generate a status report for all certificates."""
        self.logger.info("Generating certificate status report")
        
        statuses = self.monitor.check_all_certificates(self.config.certificates)
        
        report = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "total_certificates": len(statuses),
            "certificates": []
        }
        
        for status in statuses:
            cert_info = {
                "name": status.name,
                "cert_path": status.cert_path,
                "is_valid": status.is_valid,
                "needs_renewal": status.needs_renewal,
                "days_until_expiry": status.days_until_expiry,
                "expires_at": status.expires_at.isoformat() if status.expires_at else None,
                "renewal_threshold_percent": status.renewal_threshold_percent,
                "remaining_lifetime_percent": status.remaining_lifetime_percent,
                "renewal_reason": status.renewal_reason,
                "is_revoked": status.is_revoked,
                "revocation_info": None,
                "error_message": status.error_message
            }
            
            # Add revocation details if available
            if status.revocation_info and status.is_revoked:
                cert_info["revocation_info"] = {
                    "revocation_date": status.revocation_info.revocation_date.isoformat() 
                                     if status.revocation_info.revocation_date else None,
                    "revocation_reason": status.revocation_info.revocation_reason,
                    "crl_source": status.revocation_info.crl_source,
                    "check_time": status.revocation_info.check_time.isoformat()
                }
            
            report["certificates"].append(cert_info)
        
        # Summary statistics
        report["summary"] = {
            "valid_certificates": sum(1 for s in statuses if s.is_valid),
            "certificates_needing_renewal": sum(1 for s in statuses if s.needs_renewal),
            "certificates_with_errors": sum(1 for s in statuses if s.error_message),
            "revoked_certificates": sum(1 for s in statuses if s.is_revoked)
        }
        
        # Add CRL status if CRL manager is available
        if self.monitor.crl_manager:
            report["crl_status"] = self.monitor.crl_manager.get_crl_status_report()
        
        return report