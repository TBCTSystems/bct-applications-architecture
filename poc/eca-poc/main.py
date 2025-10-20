#!/usr/bin/env python3
"""
Command-line interface for the certificate renewal service.
"""
import json
import sys
import click
from pathlib import Path

from src.renewal_service import CertificateRenewalService


@click.group()
@click.option('--config', '-c', default='config/config.yaml', 
              help='Path to configuration file')
@click.pass_context
def cli(ctx, config):
    """Certificate Auto-Renewal Service using Step CA."""
    ctx.ensure_object(dict)
    ctx.obj['config_file'] = config


@cli.command()
@click.pass_context
def daemon(ctx):
    """Run the service as a daemon with periodic certificate checks."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    if not service.initialize():
        click.echo("Failed to initialize service", err=True)
        sys.exit(1)
    
    try:
        service.run_daemon()
    except KeyboardInterrupt:
        click.echo("\nShutdown requested by user")
    except Exception as e:
        click.echo(f"Service error: {str(e)}", err=True)
        sys.exit(1)


@cli.command()
@click.pass_context
def check(ctx):
    """Run a single certificate check and renewal cycle."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    if not service.initialize():
        click.echo("Failed to initialize service", err=True)
        sys.exit(1)
    
    if service.run_once():
        click.echo("Certificate check completed successfully")
    else:
        click.echo("Certificate check failed", err=True)
        sys.exit(1)


@cli.command()
@click.option('--format', '-f', type=click.Choice(['json', 'table']), 
              default='table', help='Output format')
@click.pass_context
def status(ctx, format):
    """Show status of all configured certificates."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    if not service.initialize():
        click.echo("Failed to initialize service", err=True)
        sys.exit(1)
    
    report = service.status_report()
    
    if format == 'json':
        click.echo(json.dumps(report, indent=2))
    else:
        # Table format
        click.echo(f"Certificate Status Report - {report['timestamp']}")
        click.echo("=" * 80)
        click.echo(f"Total Certificates: {report['total_certificates']}")
        click.echo(f"Valid: {report['summary']['valid_certificates']}")
        click.echo(f"Need Renewal: {report['summary']['certificates_needing_renewal']}")
        click.echo(f"Revoked: {report['summary']['revoked_certificates']}")
        click.echo(f"Errors: {report['summary']['certificates_with_errors']}")
        click.echo()
        
        for cert in report['certificates']:
            status_icon = "✓" if cert['is_valid'] else "✗"
            renewal_icon = "⚠" if cert['needs_renewal'] else " "
            revoked_icon = "🚫" if cert['is_revoked'] else " "
            
            # Add urgency indicator for emergency renewals
            urgency_icon = "🚨" if cert.get('renewal_reason') == 'emergency' else " "
            
            click.echo(f"{status_icon} {renewal_icon} {revoked_icon} {urgency_icon} {cert['name']}")
            click.echo(f"    Path: {cert['cert_path']}")
            
            if cert['expires_at']:
                renewal_threshold = cert.get('renewal_threshold_days', 30)
                renewal_reason = cert.get('renewal_reason', 'unknown')
                click.echo(f"    Expires: {cert['expires_at']} ({cert['days_until_expiry']} days)")
                click.echo(f"    Renewal Threshold: {renewal_threshold} days ({renewal_reason})")
            
            if cert['is_revoked'] and cert['revocation_info']:
                rev_info = cert['revocation_info']
                click.echo(f"    REVOKED: {rev_info['revocation_date']} - {rev_info['revocation_reason']}")
                if rev_info['crl_source']:
                    click.echo(f"    CRL Source: {rev_info['crl_source']}")
            
            if cert['error_message']:
                click.echo(f"    Error: {cert['error_message']}")
            
            click.echo()
        
        # Show CRL status if available
        if 'crl_status' in report:
            crl_status = report['crl_status']
            click.echo("CRL Status:")
            click.echo(f"  Enabled: {crl_status['crl_enabled']}")
            if crl_status['crl_enabled'] and crl_status['crls']:
                for crl in crl_status['crls']:
                    if 'issuer' in crl:
                        click.echo(f"  • {crl['url']}")
                        click.echo(f"    Issuer: {crl['issuer']}")
                        click.echo(f"    Revoked Certificates: {crl['revoked_count']}")
                        click.echo(f"    Valid: {crl['is_valid']}")
            click.echo()


@cli.command()
@click.argument('certificate_name')
@click.pass_context
def renew(ctx, certificate_name):
    """Manually renew a specific certificate."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    if not service.initialize():
        click.echo("Failed to initialize service", err=True)
        sys.exit(1)
    
    # Find the certificate configuration
    cert_config = None
    for cert in service.config.certificates:
        if cert.name == certificate_name:
            cert_config = cert
            break
    
    if not cert_config:
        click.echo(f"Certificate '{certificate_name}' not found in configuration", err=True)
        sys.exit(1)
    
    click.echo(f"Renewing certificate: {certificate_name}")
    
    try:
        if service.step_client.renew_certificate(cert_config):
            if service.step_client.verify_certificate(cert_config.cert_path):
                click.echo("Certificate renewed and verified successfully")
            else:
                click.echo("Certificate renewed but verification failed", err=True)
                sys.exit(1)
        else:
            click.echo("Certificate renewal failed", err=True)
            sys.exit(1)
    except Exception as e:
        click.echo(f"Error renewing certificate: {str(e)}", err=True)
        sys.exit(1)


@cli.command()
@click.pass_context
def init(ctx):
    """Initialize Step CA configuration and test connectivity."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    click.echo("Initializing Step CA configuration...")
    
    if service.initialize():
        click.echo("Initialization completed successfully")
        
        # Show CA info
        ca_info = service.step_client.get_ca_info()
        if ca_info:
            click.echo(f"CA Status: {ca_info}")
    else:
        click.echo("Initialization failed", err=True)
        sys.exit(1)


@cli.command()
@click.option('--refresh', '-r', is_flag=True, help='Force refresh of all CRLs')
@click.pass_context
def crl(ctx, refresh):
    """Show CRL status and optionally refresh CRLs."""
    config_file = ctx.obj['config_file']
    
    service = CertificateRenewalService(config_file)
    
    if not service.initialize():
        click.echo("Failed to initialize service", err=True)
        sys.exit(1)
    
    if not service.monitor.crl_manager:
        click.echo("CRL checking is disabled", err=True)
        sys.exit(1)
    
    crl_manager = service.monitor.crl_manager
    
    if refresh:
        click.echo("Refreshing CRLs...")
        
        # Get all configured CRL URLs
        crl_urls = set()
        if service.config.step_ca.crl_urls:
            crl_urls.update(service.config.step_ca.crl_urls)
        
        # Also check certificate distribution points if we have certificates
        for cert_config in service.config.certificates:
            cert = service.monitor.load_certificate(cert_config.cert_path)
            if cert:
                cert_crls = crl_manager.get_certificate_distribution_points(cert)
                crl_urls.update(cert_crls)
        
        if crl_urls:
            for crl_url in crl_urls:
                click.echo(f"Refreshing CRL from: {crl_url}")
                crl = crl_manager.refresh_crl(crl_url)
                if crl:
                    click.echo(f"  ✓ Successfully refreshed")
                else:
                    click.echo(f"  ✗ Failed to refresh")
        else:
            click.echo("No CRL URLs configured or found")
    
    # Show CRL status
    crl_status = crl_manager.get_crl_status_report()
    
    click.echo(f"\nCRL Status Report")
    click.echo("=" * 50)
    click.echo(f"CRL Checking: {'Enabled' if crl_status['crl_enabled'] else 'Disabled'}")
    click.echo(f"Cache Directory: {crl_status['cache_directory']}")
    click.echo(f"Refresh Interval: {crl_status['refresh_interval_hours']} hours")
    click.echo(f"Configured URLs: {len(crl_status['crl_urls'])}")
    click.echo()
    
    if crl_status['crls']:
        for crl in crl_status['crls']:
            click.echo(f"CRL: {crl['url']}")
            if 'issuer' in crl:
                click.echo(f"  Issuer: {crl['issuer']}")
                click.echo(f"  Last Update: {crl['last_update']}")
                click.echo(f"  Next Update: {crl.get('next_update', 'Unknown')}")
                click.echo(f"  Revoked Certificates: {crl['revoked_count']}")
                click.echo(f"  Valid: {'Yes' if crl['is_valid'] else 'No'}")
                if crl.get('error_message'):
                    click.echo(f"  Error: {crl['error_message']}")
            else:
                click.echo(f"  Status: {crl.get('status', 'Unknown')}")
            click.echo()
    else:
        click.echo("No CRLs loaded")


if __name__ == '__main__':
    cli()