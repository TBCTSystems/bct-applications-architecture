using System;

namespace EdgeCertAgent;

public sealed class Settings
{
    public string StepCaUrl { get; set; } = "https://localca.example.com:9443/acme/acme/directory";
    public string SubjectName { get; set; } = "acme.dhygw.org";
    public int ValidityDays { get; set; } = 30;
    public double RenewalThreshold { get; set; } = 0.75; // renew once 75% of lifetime consumed
    public string OutputFolder { get; set; } = "./certs";
    public string AccountEmail { get; set; } = "test@dhygw.org";
    public bool Insecure { get; set; } = false;
    
    // Cloudflare DNS settings (optional - for DNS-01 challenge)
    public string? CloudflareApiToken { get; set; } = "924L61ctUYlskddT-rV-33Jjus_OnGBDzlNNSTec";
    public string? CloudflareZoneId { get; set; } = "1552686b0636e0a524b6214a57445462";

    public static Settings LoadFromArgs(string[] args)
    {
        var settings = new Settings();
        foreach (var arg in args)
        {
            if (arg.StartsWith("--url=")) settings.StepCaUrl = arg[6..];
            if (arg.StartsWith("--subject=")) settings.SubjectName = arg[10..];
            if (arg.StartsWith("--days=")) settings.ValidityDays = int.Parse(arg[7..]);
            if (arg.StartsWith("--threshold=")) settings.RenewalThreshold = double.Parse(arg[12..]) / 100.0;
            if (arg.StartsWith("--out=")) settings.OutputFolder = arg[6..];
            if (arg.StartsWith("--email=")) settings.AccountEmail = arg[8..];
            if (arg.Equals("--insecure", StringComparison.OrdinalIgnoreCase)) settings.Insecure = true;
            if (arg.StartsWith("--cf-token=")) settings.CloudflareApiToken = arg[11..];
            if (arg.StartsWith("--cf-zone=")) settings.CloudflareZoneId = arg[10..];
        }

        return settings;
    }
}
