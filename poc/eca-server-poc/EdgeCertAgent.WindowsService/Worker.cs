using Microsoft.Extensions.Options;

namespace EdgeCertAgent.WindowsService;

public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly ServiceSettings _settings;

    public Worker(ILogger<Worker> logger, IOptions<ServiceSettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("EdgeCertAgent Windows Service started at: {time}", DateTimeOffset.Now);
        _logger.LogInformation("Check interval: {hours} hours", _settings.CheckIntervalHours);
        _logger.LogInformation("Monitoring domains: {domains}", string.Join(", ", _settings.Domains));

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _logger.LogInformation("Starting certificate renewal check at: {time}", DateTimeOffset.Now);
                
                await CheckAndRenewCertificatesAsync(stoppingToken);
                
                _logger.LogInformation("Certificate check completed. Next check in {hours} hours", _settings.CheckIntervalHours);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during certificate renewal check");
            }

            try
            {
                await Task.Delay(TimeSpan.FromHours(_settings.CheckIntervalHours), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Service stopping requested");
                break;
            }
        }
        
        _logger.LogInformation("EdgeCertAgent Windows Service stopped");
    }

    private async Task CheckAndRenewCertificatesAsync(CancellationToken cancellationToken)
    {
        foreach (var domain in _settings.Domains)
        {
            if (cancellationToken.IsCancellationRequested)
                break;

            try
            {
                _logger.LogInformation("Checking certificate for domain: {domain}", domain);
                
                // Create settings for this domain
                var domainSettings = new EdgeCertAgent.Settings
                {
                    StepCaUrl = _settings.StepCaUrl,
                    SubjectName = domain,
                    ValidityDays = _settings.ValidityDays,
                    RenewalThreshold = _settings.RenewalThreshold,
                    OutputFolder = Path.Combine(_settings.CertificateOutputPath, SanitizeDomainName(domain)),
                    AccountEmail = _settings.AccountEmail,
                    Insecure = _settings.Insecure,
                    CloudflareApiToken = _settings.CloudflareApiToken,
                    CloudflareZoneId = _settings.CloudflareZoneId
                };

                // Create DNS provider
                var dnsProvider = new EdgeCertAgent.CloudflareDnsProvider(
                    _settings.CloudflareApiToken, 
                    _settings.CloudflareZoneId);

                // Run certificate agent
                var certificateAgent = new EdgeCertAgent.CertificateAgent(domainSettings, dnsProvider);
                await certificateAgent.RunAsync();
                
                _logger.LogInformation("Certificate check completed for domain: {domain}", domain);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to process certificate for domain: {domain}", domain);
            }
        }
    }

    private static string SanitizeDomainName(string domain)
    {
        return domain.Replace("*", "wildcard").Replace(".", "_");
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("EdgeCertAgent Windows Service is stopping...");
        await base.StopAsync(cancellationToken);
    }
}
