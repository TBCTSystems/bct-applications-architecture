using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Logging;

namespace DeviceSimulator.Services;

public class CertificateManager : ICertificateManager, IDisposable
{
    private readonly ILogger<CertificateManager> _logger;
    private readonly FileSystemWatcher? _certWatcher;
    private readonly string _certPath;
    private readonly string _keyPath;
    private readonly string _caPath;
    private X509Certificate2? _currentCertificate;
    private X509Certificate2? _caCertificate;

    public event EventHandler<CertificateUpdatedEventArgs>? CertificateUpdated;

    public CertificateManager(ILogger<CertificateManager> logger)
    {
        _logger = logger;
        _certPath = Environment.GetEnvironmentVariable("CERT_PATH") ?? "/certs/cert.pem";
        _keyPath = Environment.GetEnvironmentVariable("KEY_PATH") ?? "/certs/privkey.pem";
        _caPath = Environment.GetEnvironmentVariable("CA_PATH") ?? "/ca-certs/ca_chain.crt";

        _logger.LogInformation("Certificate Manager initialized with paths: Cert={CertPath}, Key={KeyPath}, CA={CaPath}", 
            _certPath, _keyPath, _caPath);

        // Set up file system watcher for certificate updates
        var certDirectory = Path.GetDirectoryName(_certPath);
        if (!string.IsNullOrEmpty(certDirectory) && Directory.Exists(certDirectory))
        {
            _certWatcher = new FileSystemWatcher(certDirectory)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.CreationTime,
                Filter = "*.pem",
                EnableRaisingEvents = true
            };
            _certWatcher.Changed += OnCertificateFileChanged;
            _certWatcher.Created += OnCertificateFileChanged;
        }
        else
        {
            _logger.LogWarning("Certificate directory {Directory} does not exist, file watching disabled", certDirectory);
        }
    }

    public async Task<X509Certificate2?> GetClientCertificateAsync()
    {
        if (_currentCertificate != null && IsCertificateValid(_currentCertificate))
        {
            return _currentCertificate;
        }

        return await LoadClientCertificateAsync();
    }

    public async Task<X509Certificate2?> GetCaCertificateAsync()
    {
        if (_caCertificate != null)
        {
            return _caCertificate;
        }

        return await LoadCaCertificateAsync();
    }

    public bool IsCertificateValid(X509Certificate2? certificate)
    {
        if (certificate == null)
            return false;

        try
        {
            // Check if certificate is not expired and not yet valid
            var now = DateTime.UtcNow;
            return now >= certificate.NotBefore && now <= certificate.NotAfter;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating certificate");
            return false;
        }
    }

    private async Task<X509Certificate2?> LoadClientCertificateAsync()
    {
        try
        {
            if (!File.Exists(_certPath) || !File.Exists(_keyPath))
            {
                _logger.LogWarning("Certificate files not found: Cert={CertExists}, Key={KeyExists}", 
                    File.Exists(_certPath), File.Exists(_keyPath));
                return null;
            }

            var certPem = await File.ReadAllTextAsync(_certPath);
            var keyPem = await File.ReadAllTextAsync(_keyPath);

            // Load the full certificate chain for proper validation
            var chainPem = await File.ReadAllTextAsync("/certs/fullchain.pem");
            var certificate = X509Certificate2.CreateFromPem(chainPem, keyPem);
            
            _logger.LogInformation("Loaded client certificate: Subject={Subject}, Expires={Expires}", 
                certificate.Subject, certificate.NotAfter);

            _currentCertificate?.Dispose();
            _currentCertificate = certificate;

            return certificate;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load client certificate from {CertPath}", _certPath);
            return null;
        }
    }

    private async Task<X509Certificate2?> LoadCaCertificateAsync()
    {
        try
        {
            if (!File.Exists(_caPath))
            {
                _logger.LogWarning("CA certificate file not found: {CaPath}", _caPath);
                return null;
            }

            var caPem = await File.ReadAllTextAsync(_caPath);
            var certificate = X509Certificate2.CreateFromPem(caPem);
            
            _logger.LogInformation("Loaded CA certificate: Subject={Subject}", certificate.Subject);

            _caCertificate?.Dispose();
            _caCertificate = certificate;

            return certificate;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load CA certificate from {CaPath}", _caPath);
            return null;
        }
    }

    private async void OnCertificateFileChanged(object sender, FileSystemEventArgs e)
    {
        if (e.Name == Path.GetFileName(_certPath))
        {
            _logger.LogInformation("Certificate file changed, reloading...");
            
            // Add a small delay to ensure file write is complete
            await Task.Delay(1000);
            
            var newCertificate = await LoadClientCertificateAsync();
            if (newCertificate != null)
            {
                CertificateUpdated?.Invoke(this, new CertificateUpdatedEventArgs 
                { 
                    Certificate = newCertificate 
                });
            }
        }
    }

    public void Dispose()
    {
        _certWatcher?.Dispose();
        _currentCertificate?.Dispose();
        _caCertificate?.Dispose();
    }
}