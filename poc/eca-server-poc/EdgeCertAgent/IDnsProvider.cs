using System.Threading.Tasks;

namespace EdgeCertAgent;

public interface IDnsProvider
{
    Task CreateTxtRecord(string name, string value);
    Task DeleteTxtRecord(string name, string value);
}
