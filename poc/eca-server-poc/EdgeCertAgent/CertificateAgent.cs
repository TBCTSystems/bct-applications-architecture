using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Certes;
using Certes.Acme;

namespace EdgeCertAgent;

public sealed class CertificateAgent
{
    private readonly Settings _settings;
    private readonly IDnsProvider _dnsProvider;
    private readonly string _accountKeyPath;
    private readonly string _certPath;
    private readonly string _keyPath;
    private readonly string _caPath;

    public CertificateAgent(Settings settings, IDnsProvider dnsProvider)
    {
        _settings = settings;
        _dnsProvider = dnsProvider ?? throw new ArgumentNullException(nameof(dnsProvider));
        _accountKeyPath = Path.Combine(settings.OutputFolder, "account.pem");
        _certPath = Path.Combine(settings.OutputFolder, "cert.pem");
        _keyPath = Path.Combine(settings.OutputFolder, "key.pem");
        _caPath = Path.Combine(settings.OutputFolder, "ca.pem");
    }

    public async Task RunAsync()
    {
        Directory.CreateDirectory(_settings.OutputFolder);

        if (File.Exists(_certPath) && File.Exists(_keyPath))
        {
            if (!NeedsRenewal())
            {
                Console.WriteLine("Existing certificate still within renewal threshold.");
                return;
            }

            Console.WriteLine("Certificate renewal required.");
        }

        await RequestCertificateAsync();
    }

    private bool NeedsRenewal()
    {
        try
        {
            var cert = new X509Certificate2(_certPath);
            var now = DateTimeOffset.UtcNow;
            var notBefore = cert.NotBefore.ToUniversalTime();
            var notAfter = cert.NotAfter.ToUniversalTime();
            var totalLifetime = notAfter - notBefore;
            var elapsed = now - notBefore;
            var usedFraction = elapsed.TotalSeconds / totalLifetime.TotalSeconds;

            Console.WriteLine($"Certificate expires {notAfter:O}; used {usedFraction:P1} of lifetime.");
            return usedFraction >= _settings.RenewalThreshold;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Failed to inspect existing certificate: {ex.Message}");
            return true; // fall back to renewal if cert unreadable
        }
    }

    private async Task RequestCertificateAsync()
    {
        Console.WriteLine($"Initialising ACME client for {_settings.StepCaUrl}");
        Console.WriteLine("Challenge type: DNS-01");

        var accountKey = KeyFactory.NewKey(KeyAlgorithm.ES256);
        await File.WriteAllTextAsync(_accountKeyPath, accountKey.ToPem());
        Console.WriteLine($"Account key saved to {_accountKeyPath}");

        if (_settings.Insecure)
        {
            Console.WriteLine("WARNING: TLS certificate validation disabled (--insecure mode)");
            ServicePointManager.ServerCertificateValidationCallback = 
                (sender, cert, chain, sslPolicyErrors) => true;
        }

        var acmeUri = new Uri(_settings.StepCaUrl);
        var acme = new AcmeContext(acmeUri, accountKey);

        Console.WriteLine("Ensuring ACME account exists...");
        await acme.NewAccount(_settings.AccountEmail, true);
        Console.WriteLine("ACME account ready.");

        Console.WriteLine("Creating certificate order...");
        var order = await acme.NewOrder(new[] { _settings.SubjectName });

        var authorizations = await order.Authorizations();
        foreach (var authz in authorizations)
        {
            var authzResource = await authz.Resource();
            Console.WriteLine($"Processing authorization for {authzResource.Identifier.Value}");
            
            var challenges = await authz.Challenges();
            await HandleDns01Challenge(challenges, acme);
        }

        Console.WriteLine("Finalising order and downloading certificate...");
        var privateKey = KeyFactory.NewKey(KeyAlgorithm.RS256);
        var cert = await order.Generate(new CsrInfo
        {
            CommonName = _settings.SubjectName,
            Organization = "Edge Agent"
        }, privateKey);

        // Save certificate
        var certPem = cert.Certificate.ToDer();
        await File.WriteAllBytesAsync(_certPath + ".der", certPem);
        
        // Convert to PEM format manually
        var certPemStr = $"-----BEGIN CERTIFICATE-----\n{Convert.ToBase64String(certPem, Base64FormattingOptions.InsertLineBreaks)}\n-----END CERTIFICATE-----\n";
        await File.WriteAllTextAsync(_certPath, certPemStr);
        await File.WriteAllTextAsync(_keyPath, privateKey.ToPem());

        Console.WriteLine($"Certificate saved: {_certPath}");
        Console.WriteLine($"Private key saved: {_keyPath}");

        // Download CA certificate chain
        await DownloadCACertificateAsync(acme);
    }

    private async Task HandleDns01Challenge(System.Collections.Generic.IEnumerable<Certes.Acme.IChallengeContext> challenges, AcmeContext acme)
    {
        var dnsChallenge = challenges.FirstOrDefault(c => c.Type == Certes.Acme.Resource.ChallengeTypes.Dns01)
            ?? throw new InvalidOperationException("DNS-01 challenge not provided by CA");

        var dnsTxt = acme.AccountKey.DnsTxt(dnsChallenge.Token);
        
        // DNS record name format: _acme-challenge.{domain}
        var recordName = $"_acme-challenge.{_settings.SubjectName}";
        
        Console.WriteLine($"Creating DNS TXT record: {recordName} = {dnsTxt}");
        
        try
        {
            await _dnsProvider.CreateTxtRecord(recordName, dnsTxt);
            Console.WriteLine("DNS TXT record created successfully.");
            
            // Wait for DNS propagation
            Console.WriteLine("Waiting for DNS propagation (30 seconds)...");
            await Task.Delay(TimeSpan.FromSeconds(30));

            Console.WriteLine("Triggering challenge validation...");
            var challengeResult = await dnsChallenge.Validate();

            // Poll for challenge status
            for (var i = 0; i < 60; i++)
            {
                var status = await dnsChallenge.Resource();
                Console.WriteLine($"Challenge status: {status.Status}");
                
                if (status.Status == Certes.Acme.Resource.ChallengeStatus.Valid)
                {
                    Console.WriteLine("Challenge validated by CA.");
                    break;
                }
                
                if (status.Status == Certes.Acme.Resource.ChallengeStatus.Invalid)
                {
                    throw new InvalidOperationException($"Challenge failed: {status.Error?.Detail}");
                }
                
                await Task.Delay(TimeSpan.FromSeconds(2));
            }
        }
        finally
        {
            // Clean up DNS record
            try
            {
                Console.WriteLine($"Deleting DNS TXT record: {recordName}");
                await _dnsProvider.DeleteTxtRecord(recordName, dnsTxt);
                Console.WriteLine("DNS TXT record deleted.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Warning: Failed to delete DNS record: {ex.Message}");
            }
        }
    }

    private async Task DownloadCACertificateAsync(AcmeContext acme)
    {
        try
        {
            Console.WriteLine("Downloading CA certificate chain...");
            
            // Step CA provides root certificates at /roots.pem endpoint
            var baseUri = new Uri(_settings.StepCaUrl);
            var rootsUrl = new Uri($"{baseUri.Scheme}://{baseUri.Host}:{baseUri.Port}/roots.pem");
            
            using var handler = new HttpClientHandler();
            if (_settings.Insecure)
            {
                handler.ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
            }
            
            using var httpClient = new HttpClient(handler);
            var caPem = await httpClient.GetStringAsync(rootsUrl);
            await File.WriteAllTextAsync(_caPath, caPem);
            
            Console.WriteLine($"CA certificate chain saved: {_caPath}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Failed to download CA certificate: {ex.Message}");
            Console.WriteLine("Continuing without CA certificate file...");
        }
    }
}
