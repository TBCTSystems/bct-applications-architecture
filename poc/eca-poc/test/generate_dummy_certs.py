#!/usr/bin/env python3
"""
Generate dummy certificates for testing the certificate renewal service.
This script creates a test CA and various certificates with different expiration dates.
"""
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

class DummyCertGenerator:
    def __init__(self, base_dir="dummy-certs"):
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(exist_ok=True)
        
    def generate_ca_certificate(self):
        """Generate a dummy CA certificate and private key."""
        print("🏛️  Generating dummy CA certificate...")
        
        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        # Certificate details
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Test State"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Test City"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Test CA Organization"),
            x509.NameAttribute(NameOID.COMMON_NAME, "Test Root CA"),
        ])
        
        # Create certificate
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.now(timezone.utc)
        ).not_valid_after(
            datetime.now(timezone.utc) + timedelta(days=365 * 5)  # 5 years
        ).add_extension(
            x509.BasicConstraints(ca=True, path_length=None),
            critical=True,
        ).add_extension(
            x509.KeyUsage(
                key_cert_sign=True,
                crl_sign=True,
                digital_signature=False,
                key_encipherment=False,
                key_agreement=False,
                data_encipherment=False,
                content_commitment=False,
                encipher_only=False,
                decipher_only=False
            ),
            critical=True,
        ).add_extension(
            x509.SubjectKeyIdentifier.from_public_key(private_key.public_key()),
            critical=False,
        ).sign(private_key, hashes.SHA256())
        
        return cert, private_key

    def generate_certificate(self, subject_name, ca_cert, ca_key, sans=None, days_valid=30):
        """Generate a certificate signed by the CA."""
        print(f"🔐 Generating certificate for {subject_name} (valid for {days_valid} days)...")
        
        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        # Certificate subject
        subject = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Test State"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Test City"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Test Organization"),
            x509.NameAttribute(NameOID.COMMON_NAME, subject_name),
        ])
        
        # Calculate validity dates
        not_before = datetime.now(timezone.utc)
        not_after = not_before + timedelta(days=days_valid)
        
        # Handle already expired certificates (negative days)
        if days_valid < 0:
            not_before = datetime.now(timezone.utc) + timedelta(days=days_valid)
            not_after = datetime.now(timezone.utc) + timedelta(days=-1)  # Expired 1 day ago
        
        # Create certificate builder
        builder = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            ca_cert.subject
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            not_before
        ).not_valid_after(
            not_after
        ).add_extension(
            x509.BasicConstraints(ca=False, path_length=None),
            critical=True,
        ).add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=True,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                data_encipherment=False,
                content_commitment=False,
                encipher_only=False,
                decipher_only=False
            ),
            critical=True,
        ).add_extension(
            x509.ExtendedKeyUsage([
                x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
                x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH,
            ]),
            critical=False,
        ).add_extension(
            x509.SubjectKeyIdentifier.from_public_key(private_key.public_key()),
            critical=False,
        ).add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
            critical=False,
        )
        
        # Add SANs if provided
        if sans:
            san_list = [x509.DNSName(san) for san in sans]
            builder = builder.add_extension(
                x509.SubjectAlternativeName(san_list),
                critical=False,
            )
        
        # Sign certificate
        cert = builder.sign(ca_key, hashes.SHA256())
        
        # Print certificate info
        print(f"   📅 Valid from: {not_before.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(f"   📅 Valid to:   {not_after.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        if sans:
            print(f"   🌐 SANs: {', '.join(sans)}")
        
        return cert, private_key

    def save_certificate(self, cert, key, name):
        """Save certificate and key to files."""
        cert_path = self.base_dir / f"{name}.crt"
        key_path = self.base_dir / f"{name}.key"
        
        # Save certificate
        with open(cert_path, 'wb') as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
        
        # Save private key
        with open(key_path, 'wb') as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            ))
        
        # Set appropriate permissions on Windows/Unix
        try:
            os.chmod(cert_path, 0o644)
            os.chmod(key_path, 0o600)
        except (OSError, AttributeError):
            # Windows doesn't support chmod the same way
            pass
        
        print(f"   💾 Saved: {cert_path}")
        print(f"   🔑 Saved: {key_path}")
        
        return cert_path, key_path

    def generate_all_certificates(self):
        """Generate all test certificates."""
        print("🚀 Certificate Renewal Service - Dummy Certificate Generator")
        print("=" * 65)
        
        # Generate CA certificate
        ca_cert, ca_key = self.generate_ca_certificate()
        self.save_certificate(ca_cert, ca_key, "ca")
        
        print()
        
        # Define test certificates with different scenarios
        certificates = [
            {
                "name": "test-web-server",
                "subject": "test-web.local",
                "sans": ["www.test-web.local", "api.test-web.local"],
                "days": 10,  # Expires in 10 days - should trigger renewal
                "description": "Web server certificate (expires soon)"
            },
            {
                "name": "test-api-server", 
                "subject": "test-api.local",
                "sans": ["api-v2.test-web.local", "backend.test-web.local"],
                "days": 20,  # Expires in 20 days
                "description": "API server certificate (medium expiration)"
            },
            {
                "name": "test-expiring-soon",
                "subject": "expiring.test.local",
                "sans": None,
                "days": 2,   # Expires in 2 days - emergency renewal
                "description": "Certificate expiring very soon (emergency)"
            },
            {
                "name": "test-valid-long",
                "subject": "valid.test.local",
                "sans": ["valid-api.test.local", "long-term.test.local"],
                "days": 60,  # Expires in 60 days - should not renew
                "description": "Long-term valid certificate (should not renew)"
            },
            {
                "name": "test-already-expired",
                "subject": "expired.test.local", 
                "sans": None,
                "days": -5,  # Already expired 5 days ago
                "description": "Already expired certificate (needs immediate renewal)"
            },
            {
                "name": "test-client-auth",
                "subject": "client.test.local",
                "sans": ["client-app.test.local"],
                "days": 7,   # Expires in 7 days
                "description": "Client authentication certificate"
            }
        ]
        
        # Generate each certificate
        for i, cert_info in enumerate(certificates, 1):
            print(f"📋 Certificate {i}/{len(certificates)}: {cert_info['description']}")
            
            cert, key = self.generate_certificate(
                cert_info["subject"],
                ca_cert,
                ca_key,
                cert_info["sans"],
                cert_info["days"]
            )
            
            self.save_certificate(cert, key, cert_info['name'])
            print()
        
        # Generate summary report
        self.generate_summary_report(certificates)
        
        print("✅ All dummy certificates generated successfully!")
        print(f"📁 Certificates saved in: {self.base_dir.absolute()}")
        print("\n🎯 Next steps:")
        print("1. Update CA fingerprint in test configuration")
        print("2. Start Step CA server")
        print("3. Run certificate renewal tests")

    def generate_summary_report(self, certificates):
        """Generate a summary report of all certificates."""
        report_path = self.base_dir / "certificate_summary.txt"
        
        with open(report_path, 'w') as f:
            f.write("Certificate Renewal Service - Test Certificate Summary\n")
            f.write("=" * 55 + "\n\n")
            f.write(f"Generated on: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n\n")
            
            for cert_info in certificates:
                f.write(f"Certificate: {cert_info['name']}\n")
                f.write(f"  Subject: {cert_info['subject']}\n")
                f.write(f"  Description: {cert_info['description']}\n")
                f.write(f"  Validity: {cert_info['days']} days from generation\n")
                if cert_info['sans']:
                    f.write(f"  SANs: {', '.join(cert_info['sans'])}\n")
                f.write(f"  Certificate file: {cert_info['name']}.crt\n")
                f.write(f"  Private key file: {cert_info['name']}.key\n")
                f.write("\n")
            
            f.write("Test Scenarios:\n")
            f.write("- Certificates expiring soon (< 10 days): test-web-server, test-expiring-soon, test-client-auth\n")
            f.write("- Emergency renewals (< 5 days): test-expiring-soon\n")
            f.write("- Already expired: test-already-expired\n")
            f.write("- Long-term valid: test-valid-long\n")
            f.write("\nUse these certificates to test different renewal scenarios.\n")
        
        print(f"📊 Summary report saved: {report_path}")

def main():
    """Main entry point."""
    if len(sys.argv) > 1:
        base_dir = sys.argv[1]
    else:
        # Default to test/dummy-certs if we're in the root directory
        base_dir = "test/dummy-certs" if Path("test").exists() else "dummy-certs"
    
    try:
        generator = DummyCertGenerator(base_dir)
        generator.generate_all_certificates()
        return 0
    except ImportError as e:
        print(f"❌ Missing required Python package: {e}")
        print("💡 Install with: pip install cryptography")
        return 1
    except Exception as e:
        print(f"❌ Error generating certificates: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())