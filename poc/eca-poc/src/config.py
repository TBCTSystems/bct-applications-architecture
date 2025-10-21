"""
Configuration management for the certificate renewal service.
"""
import os
from typing import List, Optional
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings


class CertificateConfig(BaseModel):
    """Configuration for a certificate to monitor and renew."""
    
    name: str = Field(..., description="Unique name for this certificate")
    cert_path: str = Field(..., description="Path to the certificate file")
    key_path: str = Field(..., description="Path to the private key file")
    renewal_threshold_percent: Optional[float] = Field(None, description="Percentage of remaining lifetime to trigger renewal (0-100). Uses default if not specified.")
    subject: str = Field(..., description="Certificate subject (Common Name)")
    sans: Optional[List[str]] = Field(default=[], description="Subject Alternative Names")


class StepCAConfig(BaseModel):
    """Configuration for Step CA client."""
    
    ca_url: str = Field(..., description="Step CA server URL")
    ca_fingerprint: str = Field(..., description="Step CA root certificate fingerprint")
    provisioner_name: str = Field(..., description="Provisioner name for authentication")
    provisioner_password: Optional[str] = Field(None, description="Provisioner password")
    provisioner_key_path: Optional[str] = Field(None, description="Path to provisioner private key")
    root_cert_path: str = Field(..., description="Path to Step CA root certificate")
    
    # Protocol configuration
    protocol: str = Field("JWK", description="Authentication protocol: JWK or EST")
    
    # EST-specific configuration
    est_username: Optional[str] = Field(None, description="EST username for authentication")
    est_password: Optional[str] = Field(None, description="EST password for authentication")
    est_client_cert: Optional[str] = Field(None, description="EST client certificate path")
    est_client_key: Optional[str] = Field(None, description="EST client private key path")
    est_ca_bundle: Optional[str] = Field(None, description="EST CA bundle path")
    
    # CRL configuration
    crl_enabled: bool = Field(True, description="Enable CRL checking")
    crl_urls: Optional[List[str]] = Field(default=[], description="CRL distribution point URLs")
    crl_cache_dir: str = Field("certs/crl", description="Directory to cache downloaded CRLs")
    crl_refresh_hours: int = Field(24, description="Hours between CRL refresh")
    crl_timeout_seconds: int = Field(30, description="Timeout for CRL download")


class ServiceConfig(BaseSettings):
    """Main service configuration."""
    
    # Service settings
    check_interval_minutes: int = Field(30, description="Minutes between certificate checks")
    log_level: str = Field("INFO", description="Logging level")
    log_file: str = Field("logs/cert_renewal.log", description="Log file path")
    
    # Certificate storage
    cert_storage_path: str = Field("certs", description="Directory to store certificates")
    
    # Renewal threshold based on percentage of remaining lifetime
    # For example: 33.0 means renew when 33% or less of the certificate lifetime remains
    renewal_threshold_percent: float = Field(33.0, description="Renew when remaining lifetime is at or below this percentage (0-100)")
    
    # Step CA configuration
    step_ca: StepCAConfig
    
    # Certificates to monitor
    certificates: List[CertificateConfig] = Field(default=[], description="Certificates to monitor")
    
    model_config = {
        "env_prefix": "CERT_RENEWAL_",
        "env_nested_delimiter": "__",
        "case_sensitive": False,
        "extra": "allow"
    }


def load_config(config_file: str = "config/config.yaml") -> ServiceConfig:
    """Load configuration from file and environment variables."""
    import yaml
    
    config_data = {}
    
    # Load from YAML file if it exists
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            config_data = yaml.safe_load(f) or {}
    
    # Create config with environment variable override support
    return ServiceConfig(**config_data)