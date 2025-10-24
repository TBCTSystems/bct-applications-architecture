using EdgeCertAgent.WindowsService;

var builder = Host.CreateApplicationBuilder(args);

// Add Windows Service support
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "EdgeCertAgent";
});

// Register the background worker
builder.Services.AddHostedService<Worker>();

// Configure settings from appsettings.json
builder.Services.Configure<ServiceSettings>(
    builder.Configuration.GetSection("ServiceSettings"));

var host = builder.Build();
host.Run();
