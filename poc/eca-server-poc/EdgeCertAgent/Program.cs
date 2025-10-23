using System;
using System.Threading.Tasks;

namespace EdgeCertAgent;

class Program
{
    static async Task<int> Main(string[] args)
    {
        try
        {
            Console.WriteLine("Edge Certificate Agent - Step CA ACME Client");
            Console.WriteLine("==============================================\n");

            var settings = Settings.LoadFromArgs(args);
            
            Console.WriteLine($"ACME URL: {settings.StepCaUrl}");
            Console.WriteLine($"Subject: {settings.SubjectName}");
            Console.WriteLine($"Output: {settings.OutputFolder}");
            Console.WriteLine($"Renewal threshold: {settings.RenewalThreshold:P0}");
            Console.WriteLine("DNS Provider: Cloudflare\n");

            var dnsProvider = new CloudflareDnsProvider(settings.CloudflareApiToken!, settings.CloudflareZoneId!);

            var agent = new CertificateAgent(settings, dnsProvider);
            await agent.RunAsync();

            Console.WriteLine("\n✓ Certificate agent completed successfully.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"\n✗ Fatal error: {ex.Message}");
            Console.Error.WriteLine(ex.StackTrace);
            return 1;
        }
    }
}
