using DemoWeb.Models;

namespace DemoWeb.Services;

public interface ISystemMonitorService
{
    Task<SystemStatus> GetSystemStatusAsync();
    Task EnableProvisioningServiceAsync();
    Task DisableProvisioningServiceAsync();
    Task AddToWhitelistAsync(string ipAddress);
    Task<List<CertificateInfo>> GetCertificateStatusAsync();
}

public interface IMqttMonitorService
{
    List<MqttMessage> GetRecentMessages();
    void AddMessage(MqttMessage message);
    Task StartMonitoringAsync();
    Task StopMonitoringAsync();
}