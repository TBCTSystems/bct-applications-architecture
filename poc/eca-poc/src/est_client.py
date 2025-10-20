"""
EST (Enrollment over Secure Transport) client implementation.
"""
import os
import base64
import requests
from typing import Optional, Dict, Any, Tuple
from urllib.parse import urljoin
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from .config import StepCAConfig, CertificateConfig
from .logger import ServiceLogger


class ESTClient:
    """EST client for certificate enrollment and renewal operations."""
    
    def __init__(self, step_config: StepCAConfig, logger: ServiceLogger):
        self.config = step_config
        self.logger = logger
        self.session = requests.Session()
        
        # Set up authentication
        self._setup_authentication()
        
        # Set up TLS verification
        if self.config.est_ca_bundle:
            self.session.verify = self.config.est_ca_bundle
        elif self.config.root_cert_path:
            self.session.verify = self.config.root_cert_path
        else:
            self.logger.warning("No CA bundle specified, using system default")
    
    def _setup_authentication(self):
        """Setup EST authentication method."""
        if self.config.est_username and self.config.est_password:
            # HTTP Basic Authentication
            self.session.auth = (self.config.est_username, self.config.est_password)
            self.logger.info("EST client configured with HTTP Basic authentication")
        
        elif self.config.est_client_cert and self.config.est_client_key:
            # Client certificate authentication
            self.session.cert = (self.config.est_client_cert, self.config.est_client_key)
            self.logger.info("EST client configured with client certificate authentication")
        
        else:
            self.logger.warning("No EST authentication method configured")
    
    def _get_est_url(self, operation: str) -> str:
        """Construct EST URL for the given operation."""
        # EST URLs typically follow: https://ca.example.com:8443/.well-known/est/{operation}
        base_url = self.config.ca_url.rstrip('/')
        
        # Handle Step CA URL format (convert from Step CA to EST endpoint)
        if ':9000' in base_url:
            # Step CA default port, convert to EST endpoint
            est_url = base_url.replace(':9000', ':8443/.well-known/est')
        else:
            # Assume EST endpoint
            if '.well-known/est' not in base_url:
                est_url = f"{base_url}/.well-known/est"
            else:
                est_url = base_url
        
        return f"{est_url}/{operation}"
    
    def get_ca_certs(self) -> Optional[bytes]:
        """Get CA certificates using EST /cacerts operation."""
        try:
            url = self._get_est_url("cacerts")
            self.logger.debug(f"Requesting CA certificates from: {url}")
            
            response = self.session.get(
                url,
                headers={'Accept': 'application/pkcs7-mime'},
                timeout=30
            )
            
            if response.status_code == 200:
                self.logger.info("Successfully retrieved CA certificates via EST")
                return response.content
            else:
                self.logger.error(f"EST cacerts request failed: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            self.logger.error(f"Error getting CA certificates via EST: {str(e)}")
            return None
    
    def _generate_csr(self, cert_config: CertificateConfig) -> Tuple[bytes, bytes]:
        """Generate a certificate signing request and private key."""
        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        # Build subject
        subject_components = [
            x509.NameAttribute(NameOID.COMMON_NAME, cert_config.subject)
        ]
        
        # Create CSR builder
        csr_builder = x509.CertificateSigningRequestBuilder()
        csr_builder = csr_builder.subject_name(x509.Name(subject_components))
        
        # Add SANs if provided
        if cert_config.sans:
            san_list = []
            for san in cert_config.sans:
                try:
                    # Try to parse as IP address
                    import ipaddress
                    ip = ipaddress.ip_address(san)
                    san_list.append(x509.IPAddress(ip))
                except ValueError:
                    # Treat as DNS name
                    san_list.append(x509.DNSName(san))
            
            if san_list:
                csr_builder = csr_builder.add_extension(
                    x509.SubjectAlternativeName(san_list),
                    critical=False
                )
        
        # Sign the CSR
        csr = csr_builder.sign(private_key, hashes.SHA256())
        
        # Serialize CSR and private key
        csr_pem = csr.public_bytes(serialization.Encoding.PEM)
        key_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        
        return csr_pem, key_pem
    
    def enroll_certificate(self, cert_config: CertificateConfig, 
                         output_cert_path: str, output_key_path: str) -> bool:
        """Enroll for a new certificate using EST /simpleenroll."""
        try:
            self.logger.info(f"Enrolling certificate via EST: {cert_config.subject}")
            
            # Generate CSR and private key
            csr_pem, key_pem = self._generate_csr(cert_config)
            
            # Prepare EST request
            url = self._get_est_url("simpleenroll")
            
            # Convert PEM CSR to DER and then base64 encode for EST
            csr_der = x509.load_pem_x509_csr(csr_pem).public_bytes(serialization.Encoding.DER)
            csr_b64 = base64.b64encode(csr_der).decode('ascii')
            
            headers = {
                'Content-Type': 'application/pkcs10',
                'Content-Transfer-Encoding': 'base64'
            }
            
            response = self.session.post(
                url,
                data=csr_b64,
                headers=headers,
                timeout=60
            )
            
            if response.status_code == 200:
                # Parse the response (should be PKCS#7)
                cert_data = response.content
                
                # For now, assume the response is the certificate in PEM format
                # In a full implementation, you'd need to parse PKCS#7
                
                # Save certificate and key
                os.makedirs(os.path.dirname(output_cert_path), exist_ok=True)
                os.makedirs(os.path.dirname(output_key_path), exist_ok=True)
                
                with open(output_cert_path, 'wb') as f:
                    f.write(cert_data)
                
                with open(output_key_path, 'wb') as f:
                    f.write(key_pem)
                
                # Set appropriate permissions
                os.chmod(output_cert_path, 0o644)
                os.chmod(output_key_path, 0o600)
                
                self.logger.info(f"Successfully enrolled certificate via EST: {cert_config.subject}")
                return True
            
            else:
                self.logger.error(f"EST enrollment failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error during EST enrollment: {str(e)}")
            return False
    
    def renew_certificate(self, cert_config: CertificateConfig) -> bool:
        """Renew certificate using EST /simplereenroll."""
        try:
            self.logger.info(f"Renewing certificate via EST: {cert_config.subject}")
            
            # Check if current certificate exists
            if not os.path.exists(cert_config.cert_path):
                self.logger.warning("Current certificate not found, performing enrollment instead")
                return self.enroll_certificate(cert_config, cert_config.cert_path, cert_config.key_path)
            
            # Load current certificate for renewal
            with open(cert_config.cert_path, 'rb') as f:
                current_cert_data = f.read()
            
            # Generate new CSR
            csr_pem, key_pem = self._generate_csr(cert_config)
            
            # Prepare EST reenrollment request
            url = self._get_est_url("simplereenroll")
            
            # Convert PEM CSR to DER and then base64 encode
            csr_der = x509.load_pem_x509_csr(csr_pem).public_bytes(serialization.Encoding.DER)
            csr_b64 = base64.b64encode(csr_der).decode('ascii')
            
            headers = {
                'Content-Type': 'application/pkcs10',
                'Content-Transfer-Encoding': 'base64'
            }
            
            response = self.session.post(
                url,
                data=csr_b64,
                headers=headers,
                timeout=60
            )
            
            if response.status_code == 200:
                # Backup current certificate
                backup_path = f"{cert_config.cert_path}.backup"
                with open(backup_path, 'wb') as f:
                    f.write(current_cert_data)
                
                # Save new certificate and key
                with open(cert_config.cert_path, 'wb') as f:
                    f.write(response.content)
                
                with open(cert_config.key_path, 'wb') as f:
                    f.write(key_pem)
                
                # Set appropriate permissions
                os.chmod(cert_config.cert_path, 0o644)
                os.chmod(cert_config.key_path, 0o600)
                
                self.logger.info(f"Successfully renewed certificate via EST: {cert_config.subject}")
                return True
            
            else:
                self.logger.error(f"EST renewal failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error during EST renewal: {str(e)}")
            return False
    
    def verify_connectivity(self) -> bool:
        """Verify EST server connectivity by checking cacerts endpoint."""
        try:
            ca_certs = self.get_ca_certs()
            return ca_certs is not None
        except Exception as e:
            self.logger.error(f"EST connectivity test failed: {str(e)}")
            return False