using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

// Load configuration from Azure App Configuration (with Key Vault references)
var appConfigEndpoint = Environment.GetEnvironmentVariable("APPCONFIG_ENDPOINT");
if (!string.IsNullOrEmpty(appConfigEndpoint))
{
    var credential = new DefaultAzureCredential();
    builder.Configuration.AddAzureAppConfiguration(options =>
    {
        options.Connect(new Uri(appConfigEndpoint), credential)
               .Select("IntuneUp:*")
               .ConfigureKeyVault(kv => kv.SetCredential(credential));
    });
}

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Register ServiceBusClient with Managed Identity
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var sbConnection = config["IntuneUp:ServiceBus:ConnectionString"];

    if (!string.IsNullOrEmpty(sbConnection) && sbConnection.Contains("Endpoint="))
        return new ServiceBusClient(sbConnection);

    var sbNamespace = config["IntuneUp:ServiceBus:Namespace"] ?? "sb-intuneup-dev.servicebus.windows.net";
    return new ServiceBusClient(sbNamespace, new DefaultAzureCredential());
});

builder.Build().Run();
