namespace EdgeCertAgent.WindowsService;

public class ServiceSettings
{
    public string StepCaUrl { get; set; } = "https://localca.example.com:9443/acme/acme/directory";
    public string[] Domains { get; set; } = ["acme.dhygw.org"];
    public int ValidityDays { get; set; } = 30;
    public double RenewalThreshold { get; set; } = 0.75;
    public string CertificateOutputPath { get; set; } = "C:\\EdgeCertAgent\\Certificates";
    public string AccountEmail { get; set; } = "test@dhygw.org";
    public bool Insecure { get; set; } = false;
    public double CheckIntervalHours { get; set; } = 24;
    
    // Cloudflare DNS settings
    public string CloudflareApiToken { get; set; } = "";
    public string CloudflareZoneId { get; set; } = "";
}
