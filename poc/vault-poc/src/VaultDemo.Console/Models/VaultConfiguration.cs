namespace VaultDemo.Console.Models;

public class VaultConfiguration
{
   // Vault address
   public string Address { get; set; }
   
   // Authentication method
   public AuthMethod AuthMethod { get; set; }
   
   // For Token authentication
   public string AuthToken { get; set; }
   
   // For UserPass authentication
   public string Username { get; set; }
   public string Password { get; set; }
   
   // For AppRole authentication
   public string RoleId { get; set; }
   public string SecretId { get; set; }
   
   // For Certificate authentication
   public string CertPath { get; set; }
   public string CertPassword { get; set; }
}