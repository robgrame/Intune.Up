using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
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

var defaultCredential = new DefaultAzureCredential();

// Register ServiceBusClient
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var sbConnection = config["IntuneUp:ServiceBus:ConnectionString"];

    if (!string.IsNullOrEmpty(sbConnection) && sbConnection.Contains("Endpoint="))
        return new ServiceBusClient(sbConnection);

    var sbNamespace = config["IntuneUp:ServiceBus:Namespace"] ?? "sb-intuneup-dev.servicebus.windows.net";
    return new ServiceBusClient(sbNamespace, defaultCredential);
});

// Register BlobServiceClient (for claim-check pattern)
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var storageAccountName = config["IntuneUp:ClaimCheck:StorageAccountName"]
        ?? Environment.GetEnvironmentVariable("AzureWebJobsStorage__accountName")
        ?? "stintuneupclaimcheck";
    return new BlobServiceClient(new Uri($"https://{storageAccountName}.blob.core.windows.net"), defaultCredential);
});

builder.Build().Run();
