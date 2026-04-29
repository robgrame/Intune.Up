using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

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

// (Legacy) HttpClient for Log Analytics Data Collector API
// NOTE: ProcessorFunction now uses Logs Ingestion API (DCR/DCE) via Azure.Monitor.Ingestion.

// Helper: Get config value with fallback and validation
static string GetConfigValue(IConfiguration config, string key, string? envVarName = null, string? defaultValue = null)
{
    // Try config first (highest priority)
    var value = config[key];
    if (!string.IsNullOrWhiteSpace(value))
        return value;

    // Try environment variable
    if (!string.IsNullOrEmpty(envVarName))
    {
        value = Environment.GetEnvironmentVariable(envVarName);
        if (!string.IsNullOrWhiteSpace(value))
            return value;
    }

    // Return default or empty
    return defaultValue ?? string.Empty;
}

// BlobServiceClient for claim-check pattern
var defaultCredential = new DefaultAzureCredential();
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var logger = sp.GetRequiredService<ILogger<Program>>();
    
    var storageAccountName = GetConfigValue(
        config,
        "IntuneUp:ClaimCheck:StorageAccountName",
        "AzureWebJobsStorage__accountName"
    );

    if (string.IsNullOrWhiteSpace(storageAccountName))
    {
        logger.LogError("BlobServiceClient: Storage account name not found in configuration");
        throw new InvalidOperationException("IntuneUp:ClaimCheck:StorageAccountName must be configured");
    }

    var blobUri = new Uri($"https://{storageAccountName}.blob.core.windows.net");
    logger.LogInformation("BlobServiceClient: Using storage account {StorageAccount}", storageAccountName);
    return new BlobServiceClient(blobUri, defaultCredential);
});

builder.Build().Run();
