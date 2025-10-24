"""
Certificate Revocation List (CRL) management and validation functionality.
"""
import os
import hashlib
import requests
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Set, Dict, Any
from urllib.parse import urlparse
from dataclasses import dataclass

from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.x509.verification import PolicyBuilder, Store

from .config import StepCAConfig
from .logger import ServiceLogger


@dataclass
class CRLInfo:
    """Information about a CRL."""
    url: str
    file_path: str
    issuer: str
    last_update: datetime
    next_update: Optional[datetime]
    revoked_count: int
    is_valid: bool
    error_message: Optional[str] = None


@dataclass
class RevocationStatus:
    """Certificate revocation status."""
    is_revoked: bool
    revocation_date: Optional[datetime] = None
    revocation_reason: Optional[str] = None
    crl_source: Optional[str] = None
    check_time: datetime = None

    def __post_init__(self):
        if self.check_time is None:
            self.check_time = datetime.now(timezone.utc)


class CRLManager:
    """Manages Certificate Revocation Lists for certificate validation."""
    
    def __init__(self, step_config: StepCAConfig, logger: ServiceLogger):
        self.config = step_config
        self.logger = logger
        self.session = requests.Session()
        
        # Configure SSL verification for Step CA
        # Use the root CA certificate if available, otherwise disable verification for localhost
        if hasattr(step_config, 'root_cert_path') and step_config.root_cert_path and os.path.exists(step_config.root_cert_path):
            self.session.verify = step_config.root_cert_path
            self.logger.debug(f"Using root CA certificate for CRL verification: {step_config.root_cert_path}")
        else:
            # Disable SSL verification for localhost/development
            # In production, proper CA certificates should be used
            self.session.verify = False
            self.logger.warning("SSL verification disabled for CRL downloads - use proper CA certificates in production")
            # Suppress InsecureRequestWarning
            import urllib3
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Create CRL cache directory
        os.makedirs(self.config.crl_cache_dir, exist_ok=True)
        
        # Cache for parsed CRLs
        self._crl_cache: Dict[str, x509.CertificateRevocationList] = {}
        self._crl_info_cache: Dict[str, CRLInfo] = {}
        # Track last download time to avoid redundant downloads in the same session
        self._last_download_time: Dict[str, datetime] = {}

    
    def _get_crl_file_path(self, crl_url: str) -> str:
        """Generate a file path for caching a CRL."""
        # Create a hash of the URL for the filename
        url_hash = hashlib.sha256(crl_url.encode()).hexdigest()[:16]
        parsed_url = urlparse(crl_url)
        hostname = parsed_url.hostname or "unknown"
        filename = f"{hostname}_{url_hash}.crl"
        return os.path.join(self.config.crl_cache_dir, filename)
    
    def _should_refresh_crl(self, crl_url: str, file_path: str) -> bool:
        """Check if a CRL should be refreshed."""
        if not os.path.exists(file_path):
            return True
        
        # Check file age
        file_stat = os.stat(file_path)
        file_age = datetime.now(timezone.utc) - datetime.fromtimestamp(file_stat.st_mtime, tz=timezone.utc)
        
        if file_age > timedelta(hours=self.config.crl_refresh_hours):
            self.logger.debug(f"CRL cache expired for {crl_url}")
            return True
        
        # Check if we have cached CRL info with next update time
        if crl_url in self._crl_info_cache:
            crl_info = self._crl_info_cache[crl_url]
            if crl_info.next_update and datetime.now(timezone.utc) >= crl_info.next_update:
                self.logger.debug(f"CRL next update time reached for {crl_url}")
                return True
        
        return False
    
    def download_crl(self, crl_url: str) -> Optional[bytes]:
        """Download a CRL from the given URL."""
        try:
            self.logger.debug(f"Downloading CRL from: {crl_url}")
            
            headers = {
                'User-Agent': 'Certificate-Renewal-Service/1.0',
                'Accept': 'application/pkix-crl'
            }
            
            response = self.session.get(
                crl_url, 
                headers=headers,
                timeout=self.config.crl_timeout_seconds
            )
            response.raise_for_status()
            
            if response.content:
                self.logger.info(f"Successfully downloaded CRL from {crl_url} ({len(response.content)} bytes)")
                return response.content
            else:
                self.logger.warning(f"Empty CRL response from {crl_url}")
                return None
                
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Failed to download CRL from {crl_url}: {str(e)}")
            return None
        except Exception as e:
            self.logger.error(f"Unexpected error downloading CRL from {crl_url}: {str(e)}")
            return None
    
    def load_crl_from_file(self, file_path: str) -> Optional[x509.CertificateRevocationList]:
        """Load and parse a CRL from file."""
        try:
            if not os.path.exists(file_path):
                return None
            
            with open(file_path, 'rb') as f:
                crl_data = f.read()
            
            # Try PEM format first
            try:
                crl = x509.load_pem_x509_crl(crl_data, default_backend())
                return crl
            except ValueError:
                # Try DER format
                try:
                    crl = x509.load_der_x509_crl(crl_data, default_backend())
                    return crl
                except ValueError as e:
                    self.logger.error(f"Failed to parse CRL from {file_path}: {str(e)}")
                    return None
                    
        except Exception as e:
            self.logger.error(f"Error loading CRL from {file_path}: {str(e)}")
            return None
    
    def save_crl_to_file(self, crl_data: bytes, file_path: str) -> bool:
        """Save CRL data to file."""
        try:
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            with open(file_path, 'wb') as f:
                f.write(crl_data)
            
            # Set appropriate permissions
            os.chmod(file_path, 0o644)
            
            self.logger.debug(f"Saved CRL to {file_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to save CRL to {file_path}: {str(e)}")
            return False
    
    def get_crl_info(self, crl: x509.CertificateRevocationList, crl_url: str) -> CRLInfo:
        """Extract information from a CRL."""
        try:
            # Get issuer
            issuer = crl.issuer.rfc4514_string()
            
            # Get update times (using UTC-aware properties)
            last_update = crl.last_update_utc
            next_update = crl.next_update_utc
            
            # Count revoked certificates
            revoked_count = len(list(crl))
            
            # Check if CRL is still valid
            now = datetime.now(timezone.utc)
            is_valid = (last_update <= now and 
                       (next_update is None or now <= next_update))
            
            return CRLInfo(
                url=crl_url,
                file_path=self._get_crl_file_path(crl_url),
                issuer=issuer,
                last_update=last_update,
                next_update=next_update,
                revoked_count=revoked_count,
                is_valid=is_valid
            )
            
        except Exception as e:
            error_msg = f"Error extracting CRL info: {str(e)}"
            self.logger.error(error_msg)
            
            return CRLInfo(
                url=crl_url,
                file_path=self._get_crl_file_path(crl_url),
                issuer="Unknown",
                last_update=datetime.now(timezone.utc),
                next_update=None,
                revoked_count=0,
                is_valid=False,
                error_message=error_msg
            )
    
    def refresh_crl(self, crl_url: str) -> Optional[x509.CertificateRevocationList]:
        """Refresh a CRL from URL and cache it. Always tries to download the latest CRL first,
        but uses in-memory cache for a short time (60 seconds) to avoid redundant downloads
        when checking multiple certificates in the same cycle."""
        file_path = self._get_crl_file_path(crl_url)
        
        # Check if we recently downloaded this CRL (within last 60 seconds)
        now = datetime.now(timezone.utc)
        if crl_url in self._last_download_time:
            time_since_download = (now - self._last_download_time[crl_url]).total_seconds()
            if time_since_download < 60:  # Use in-memory cache for 60 seconds
                if crl_url in self._crl_cache:
                    self.logger.debug(f"Using recently downloaded CRL for {crl_url} (downloaded {time_since_download:.0f}s ago)")
                    return self._crl_cache[crl_url]
        
        # Try to download the latest CRL to ensure we have up-to-date revocation information
        self.logger.debug(f"Attempting to download latest CRL from {crl_url}")
        crl_data = self.download_crl(crl_url)
        
        if not crl_data:
            # Fallback to cached version if download fails
            self.logger.warning(f"CRL download failed, trying cached version for {crl_url}")
            
            # Try in-memory cache first
            if crl_url in self._crl_cache:
                self.logger.info(f"Using in-memory cached CRL for {crl_url}")
                return self._crl_cache[crl_url]
            
            # Try loading from cached file
            crl = self.load_crl_from_file(file_path)
            if crl:
                self.logger.info(f"Loaded CRL from cached file for {crl_url}")
                self._crl_cache[crl_url] = crl
                return crl
            
            self.logger.error(f"No cached CRL available for {crl_url}")
            return None
        
        # Successfully downloaded CRL - update download time
        self._last_download_time[crl_url] = now
        
        # Save to file
        if not self.save_crl_to_file(crl_data, file_path):
            self.logger.warning(f"Failed to cache CRL for {crl_url}")
        
        # Parse CRL
        try:
            # Try PEM format first
            try:
                crl = x509.load_pem_x509_crl(crl_data, default_backend())
            except ValueError:
                # Try DER format
                crl = x509.load_der_x509_crl(crl_data, default_backend())
            
            # Cache the parsed CRL and its info
            self._crl_cache[crl_url] = crl
            self._crl_info_cache[crl_url] = self.get_crl_info(crl, crl_url)
            
            self.logger.info(f"Successfully refreshed CRL for {crl_url}")
            return crl
            
        except ValueError as e:
            self.logger.error(f"Failed to parse downloaded CRL from {crl_url}: {str(e)}")
            # Try to fall back to cached version if parsing fails
            self.logger.warning(f"Attempting to use cached CRL after parse failure")
            crl = self.load_crl_from_file(file_path)
            if crl:
                self.logger.info(f"Using cached CRL after download parse failure")
                self._crl_cache[crl_url] = crl
                return crl
            return None
    
    def get_certificate_distribution_points(self, certificate: x509.Certificate) -> List[str]:
        """Extract CRL distribution points from a certificate."""
        try:
            # Look for CRL Distribution Points extension
            crl_dist_points = certificate.extensions.get_extension_for_oid(
                x509.ExtensionOID.CRL_DISTRIBUTION_POINTS
            ).value
            
            urls = []
            for dist_point in crl_dist_points:
                if dist_point.full_name:
                    for general_name in dist_point.full_name:
                        if isinstance(general_name, x509.UniformResourceIdentifier):
                            urls.append(general_name.value)
            
            return urls
            
        except x509.ExtensionNotFound:
            self.logger.debug("No CRL distribution points found in certificate")
            return []
        except Exception as e:
            self.logger.warning(f"Error extracting CRL distribution points: {str(e)}")
            return []
    
    def check_certificate_revocation(self, certificate: x509.Certificate) -> RevocationStatus:
        """Check if a certificate is revoked using CRLs."""
        if not self.config.crl_enabled:
            self.logger.debug("CRL checking is disabled")
            return RevocationStatus(is_revoked=False)
        
        # Get CRL URLs from multiple sources
        crl_urls = set()
        
        # Add configured CRL URLs
        if self.config.crl_urls:
            crl_urls.update(self.config.crl_urls)
        
        # Add CRL distribution points from certificate
        cert_crl_urls = self.get_certificate_distribution_points(certificate)
        crl_urls.update(cert_crl_urls)
        
        if not crl_urls:
            self.logger.warning("No CRL URLs available for revocation checking")
            return RevocationStatus(is_revoked=False)
        
        self.logger.debug(f"Checking certificate revocation against {len(crl_urls)} CRL sources")
        
        # Check against each CRL
        for crl_url in crl_urls:
            try:
                crl = self.refresh_crl(crl_url)
                if not crl:
                    self.logger.warning(f"Could not load CRL from {crl_url}")
                    continue
                
                # Check if certificate is in this CRL
                cert_serial = certificate.serial_number
                
                for revoked_cert in crl:
                    if revoked_cert.serial_number == cert_serial:
                        # Certificate is revoked (using UTC-aware property)
                        revocation_date = revoked_cert.revocation_date_utc
                        
                        # Try to get revocation reason
                        revocation_reason = "Unspecified"
                        try:
                            if revoked_cert.extensions:
                                reason_ext = revoked_cert.extensions.get_extension_for_oid(
                                    x509.ExtensionOID.CRL_REASON
                                ).value
                                revocation_reason = reason_ext.reason.name
                        except (x509.ExtensionNotFound, AttributeError):
                            pass
                        
                        self.logger.warning(
                            f"Certificate is REVOKED: Serial {cert_serial}, "
                            f"Revoked on {revocation_date}, Reason: {revocation_reason}"
                        )
                        
                        return RevocationStatus(
                            is_revoked=True,
                            revocation_date=revocation_date,
                            revocation_reason=revocation_reason,
                            crl_source=crl_url
                        )
                
                self.logger.debug(f"Certificate not found in CRL from {crl_url}")
                
            except Exception as e:
                self.logger.error(f"Error checking CRL from {crl_url}: {str(e)}")
                continue
        
        # Certificate not found in any CRL
        self.logger.debug("Certificate revocation check passed - not found in any CRL")
        return RevocationStatus(is_revoked=False)
    
    def get_crl_status_report(self) -> Dict[str, Any]:
        """Generate a status report for all managed CRLs."""
        report = {
            "crl_enabled": self.config.crl_enabled,
            "crl_urls": self.config.crl_urls,
            "cache_directory": self.config.crl_cache_dir,
            "refresh_interval_hours": self.config.crl_refresh_hours,
            "crls": []
        }
        
        all_crl_urls = set(self.config.crl_urls or [])
        
        for crl_url in all_crl_urls:
            crl_info = self._crl_info_cache.get(crl_url)
            if crl_info:
                crl_data = {
                    "url": crl_info.url,
                    "issuer": crl_info.issuer,
                    "last_update": crl_info.last_update.isoformat(),
                    "next_update": crl_info.next_update.isoformat() if crl_info.next_update else None,
                    "revoked_count": crl_info.revoked_count,
                    "is_valid": crl_info.is_valid,
                    "error_message": crl_info.error_message
                }
            else:
                crl_data = {
                    "url": crl_url,
                    "status": "not_loaded"
                }
            
            report["crls"].append(crl_data)
        
        return report