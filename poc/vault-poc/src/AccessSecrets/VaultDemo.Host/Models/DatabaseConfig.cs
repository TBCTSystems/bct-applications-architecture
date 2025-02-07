namespace VaultDemo.Host.Models;

public class DatabaseConfig
{
   public string Username { get; set; }
   public string Password { get; set; }
   public string Host { get; set; }
   public int Port { get; set; }
   public string Database { get; set; }
   
   public string GetConnectionString()
   {
      return $"Server={Host};Port={Port};Database={Database};User Id={Username};Password={Password};";
   }
}