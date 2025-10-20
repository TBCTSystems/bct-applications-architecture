"""
Certificate monitoring and expiration checking functionality.
"""
import os
from datetime import datetime, timedelta, timezone
from typing import List, Tuple, Optional
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from dataclasses import dataclass

from .config import CertificateConfig, StepCAConfig
from .logger import ServiceLogger
from .crl_manager import CRLManager, RevocationStatus


@dataclass
class CertificateStatus:
    """Status information for a monitored certificate."""
    name: str
    cert_path: str
    is_valid: bool
    expires_at: Optional[datetime]
    days_until_expiry: Optional[int]
    needs_renewal: bool
    renewal_threshold_days: int = 30
    renewal_reason: str = "valid"
    is_revoked: bool = False
    revocation_info: Optional[RevocationStatus] = None
    error_message: Optional[str] = None


class CertificateMonitor:
    """Monitors certificates for expiration and renewal needs."""
    
    def __init__(self, logger: ServiceLogger, step_config: Optional[StepCAConfig] = None, service_config: Optional[object] = None):
        self.logger = logger
        self.service_config = service_config
        
        # Initialize CRL manager if Step CA config is provided
        self.crl_manager = None
        if step_config and step_config.crl_enabled:
            self.crl_manager = CRLManager(step_config, logger)
            self.logger.info("CRL checking enabled")
        else:
            self.logger.info("CRL checking disabled")
    
    def load_certificate(self, cert_path: str) -> Optional[x509.Certificate]:
        """Load a certificate from file."""
        try:
            if not os.path.exists(cert_path):
                self.logger.error(f"Certificate file not found: {cert_path}")
                return None
            
            with open(cert_path, 'rb') as cert_file:
                cert_data = cert_file.read()
            
            # Try PEM format first
            try:
                certificate = x509.load_pem_x509_certificate(cert_data, default_backend())
                return certificate
            except ValueError:
                # Try DER format
                try:
                    certificate = x509.load_der_x509_certificate(cert_data, default_backend())
                    return certificate
                except ValueError as e:
                    self.logger.error(f"Failed to parse certificate {cert_path}: {str(e)}")
                    return None
                    
        except Exception as e:
            self.logger.error(f"Error loading certificate {cert_path}: {str(e)}")
            return None
    
    def check_certificate_expiry(self, certificate: x509.Certificate, 
                               renewal_threshold_days: int) -> Tuple[datetime, int, bool, str]:
        """Check if certificate needs renewal based on expiry date."""
        expires_at = certificate.not_valid_after
        # Make expires_at timezone-aware if it's naive (assume UTC)
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        
        now = datetime.now(timezone.utc)
        
        days_until_expiry = (expires_at - now).days
        needs_renewal = days_until_expiry <= renewal_threshold_days
        
        # Determine renewal urgency
        if self.service_config:
            emergency_threshold = getattr(self.service_config, 'emergency_renewal_threshold_days', 7)
            warning_threshold = getattr(self.service_config, 'warning_threshold_days', 14)
            
            if days_until_expiry <= emergency_threshold:
                renewal_reason = "emergency"
            elif days_until_expiry <= warning_threshold:
                renewal_reason = "warning" if needs_renewal else "approaching"
            else:
                renewal_reason = "normal" if needs_renewal else "valid"
        else:
            renewal_reason = "normal" if needs_renewal else "valid"
        
        return expires_at, days_until_expiry, needs_renewal, renewal_reason
    
    def get_effective_renewal_threshold(self, cert_config: CertificateConfig) -> int:
        """Get the effective renewal threshold for a certificate."""
        # Use certificate-specific threshold if provided
        if cert_config.renewal_threshold_days is not None:
            return cert_config.renewal_threshold_days
        
        # Use service default if available
        if self.service_config and hasattr(self.service_config, 'default_renewal_threshold_days'):
            return self.service_config.default_renewal_threshold_days
        
        # Fallback to hardcoded default
        return 30
    
    def get_certificate_subject(self, certificate: x509.Certificate) -> str:
        """Extract the subject (Common Name) from certificate."""
        try:
            # Get the common name from the subject
            for attribute in certificate.subject:
                if attribute.oid == x509.NameOID.COMMON_NAME:
                    return attribute.value
            return "Unknown"
        except Exception as e:
            self.logger.warning(f"Could not extract subject from certificate: {str(e)}")
            return "Unknown"
    
    def get_certificate_sans(self, certificate: x509.Certificate) -> List[str]:
        """Extract Subject Alternative Names from certificate."""
        try:
            san_extension = certificate.extensions.get_extension_for_oid(
                x509.ExtensionOID.SUBJECT_ALTERNATIVE_NAME
            ).value
            
            sans = []
            for san in san_extension:
                if isinstance(san, x509.DNSName):
                    sans.append(san.value)
                elif isinstance(san, x509.IPAddress):
                    sans.append(str(san.value))
            
            return sans
        except x509.ExtensionNotFound:
            return []
        except Exception as e:
            self.logger.warning(f"Could not extract SANs from certificate: {str(e)}")
            return []
    
    def check_certificate_status(self, cert_config: CertificateConfig) -> CertificateStatus:
        """Check the status of a single certificate."""
        self.logger.debug(f"Checking certificate: {cert_config.name}")
        
        # Load certificate
        certificate = self.load_certificate(cert_config.cert_path)
        
        if certificate is None:
            return CertificateStatus(
                name=cert_config.name,
                cert_path=cert_config.cert_path,
                is_valid=False,
                expires_at=None,
                days_until_expiry=None,
                needs_renewal=True,
                renewal_threshold_days=self.get_effective_renewal_threshold(cert_config),
                renewal_reason="error",
                error_message="Failed to load certificate"
            )
        
        # Check expiry
        try:
            # Get effective renewal threshold
            renewal_threshold = self.get_effective_renewal_threshold(cert_config)
            
            expires_at, days_until_expiry, needs_renewal, renewal_reason = self.check_certificate_expiry(
                certificate, renewal_threshold
            )
            
            # Check if certificate is currently valid (time-wise)
            now = datetime.now(timezone.utc)
            not_before = certificate.not_valid_before
            not_after = certificate.not_valid_after
            
            # Make certificate times timezone-aware if they're naive (assume UTC)
            if not_before.tzinfo is None:
                not_before = not_before.replace(tzinfo=timezone.utc)
            if not_after.tzinfo is None:
                not_after = not_after.replace(tzinfo=timezone.utc)
                
            is_time_valid = (not_before <= now <= not_after)
            
            # Check revocation status
            is_revoked = False
            revocation_info = None
            
            if self.crl_manager and is_time_valid:
                self.logger.debug(f"Checking revocation status for certificate: {cert_config.name}")
                revocation_info = self.crl_manager.check_certificate_revocation(certificate)
                is_revoked = revocation_info.is_revoked
                
                if is_revoked:
                    self.logger.warning(
                        f"Certificate '{cert_config.name}' is REVOKED: "
                        f"Revoked on {revocation_info.revocation_date}, "
                        f"Reason: {revocation_info.revocation_reason}"
                    )
                    # Force renewal if certificate is revoked
                    needs_renewal = True
            
            # Overall validity (time + revocation)
            is_valid = is_time_valid and not is_revoked
            
            status = CertificateStatus(
                name=cert_config.name,
                cert_path=cert_config.cert_path,
                is_valid=is_valid,
                expires_at=expires_at,
                days_until_expiry=days_until_expiry,
                needs_renewal=needs_renewal,
                renewal_threshold_days=renewal_threshold,
                renewal_reason=renewal_reason,
                is_revoked=is_revoked,
                revocation_info=revocation_info
            )
            
            # Log status with detailed information
            if is_revoked:
                self.logger.warning(
                    f"Certificate '{cert_config.name}' is REVOKED and needs immediate renewal"
                )
            elif needs_renewal:
                urgency = "EMERGENCY" if renewal_reason == "emergency" else "NORMAL"
                self.logger.warning(
                    f"Certificate '{cert_config.name}' needs {urgency} renewal "
                    f"(expires in {days_until_expiry} days, threshold: {renewal_threshold} days)"
                )
            elif renewal_reason == "approaching":
                self.logger.info(
                    f"Certificate '{cert_config.name}' is approaching renewal threshold "
                    f"(expires in {days_until_expiry} days, threshold: {renewal_threshold} days)"
                )
            else:
                self.logger.info(
                    f"Certificate '{cert_config.name}' is valid "
                    f"(expires in {days_until_expiry} days, threshold: {renewal_threshold} days)"
                )
            
            return status
            
        except Exception as e:
            error_msg = f"Error checking certificate: {str(e)}"
            self.logger.error(error_msg)
            
            return CertificateStatus(
                name=cert_config.name,
                cert_path=cert_config.cert_path,
                is_valid=False,
                expires_at=None,
                days_until_expiry=None,
                needs_renewal=True,
                renewal_threshold_days=self.get_effective_renewal_threshold(cert_config),
                renewal_reason="error",
                error_message=error_msg
            )
    
    def check_all_certificates(self, cert_configs: List[CertificateConfig]) -> List[CertificateStatus]:
        """Check the status of all configured certificates."""
        self.logger.info(f"Checking {len(cert_configs)} certificates for expiry")
        
        statuses = []
        for cert_config in cert_configs:
            status = self.check_certificate_status(cert_config)
            statuses.append(status)
        
        # Summary logging
        total_certs = len(statuses)
        needs_renewal = sum(1 for status in statuses if status.needs_renewal)
        invalid_certs = sum(1 for status in statuses if not status.is_valid)
        revoked_certs = sum(1 for status in statuses if status.is_revoked)
        
        self.logger.info(
            f"Certificate check complete: {total_certs} total, "
            f"{needs_renewal} need renewal, {invalid_certs} invalid, {revoked_certs} revoked"
        )
        
        return statuses