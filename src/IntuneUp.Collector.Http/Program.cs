using Azure.Identity;
using Azure.Messaging.ServiceBus;
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
    try
    {
        var credential = new DefaultAzureCredential();
        builder.Configuration.AddAzureAppConfiguration(options =>
        {
            options.Connect(new Uri(appConfigEndpoint), credential)
                   .Select("IntuneUp:*")
                   .ConfigureKeyVault(kv => kv.SetCredential(credential));
        });
        System.Diagnostics.Debug.WriteLine($"[STARTUP] App Configuration loaded from {appConfigEndpoint}");
    }
    catch (Exception ex)
    {
        System.Diagnostics.Debug.WriteLine($"[STARTUP ERROR] Failed to load App Configuration: {ex.GetType().Name}: {ex.Message}");
        throw;
    }
}
else
{
    System.Diagnostics.Debug.WriteLine("[STARTUP] APPCONFIG_ENDPOINT not set, using only environment variables");
}

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

var defaultCredential = new DefaultAzureCredential();

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

// Register ServiceBusClient
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var logger = sp.GetRequiredService<ILogger<Program>>();
    
    try
    {
        var sbConnection = GetConfigValue(config, "IntuneUp:ServiceBus:ConnectionString");
        logger.LogDebug("ServiceBusClient: Connection string = '{Value}'", string.IsNullOrEmpty(sbConnection) ? "NULL" : "SET");

        if (!string.IsNullOrEmpty(sbConnection) && sbConnection.Contains("Endpoint="))
        {
            logger.LogInformation("ServiceBusClient: Using connection string from configuration");
            return new ServiceBusClient(sbConnection);
        }

        // Use correct namespace for environment
        var sbNamespace = GetConfigValue(config, "IntuneUp:ServiceBus:Namespace", null, "sb-intuneup-prod.servicebus.windows.net");
        logger.LogInformation("ServiceBusClient: Using namespace {Namespace}", sbNamespace);
        return new ServiceBusClient(sbNamespace, defaultCredential);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "ServiceBusClient: Failed to create client");
        throw;
    }
});

// Register BlobServiceClient (for claim-check pattern)
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var logger = sp.GetRequiredService<ILogger<Program>>();
    
    // Try environment variable first (faster, no App Config needed)
    var storageAccountName = Environment.GetEnvironmentVariable("IntuneUp__ClaimCheck__StorageAccountName");
    logger.LogDebug("BlobServiceClient: EnvVar IntuneUp__ClaimCheck__StorageAccountName = '{Value}'", storageAccountName ?? "NULL");

    // Fallback to config if env var not set
    if (string.IsNullOrWhiteSpace(storageAccountName))
    {
        storageAccountName = config["IntuneUp:ClaimCheck:StorageAccountName"];
        logger.LogDebug("BlobServiceClient: Config IntuneUp:ClaimCheck:StorageAccountName = '{Value}'", storageAccountName ?? "NULL");
    }

    if (string.IsNullOrWhiteSpace(storageAccountName))
    {
        logger.LogError("BlobServiceClient: Storage account name not found in environment or configuration");
        throw new InvalidOperationException("IntuneUp__ClaimCheck__StorageAccountName environment variable or IntuneUp:ClaimCheck:StorageAccountName config must be set");
    }

    try
    {
        var blobUri = new Uri($"https://{storageAccountName}.blob.core.windows.net");
        logger.LogInformation("BlobServiceClient: Using storage account {StorageAccount}", storageAccountName);
        return new BlobServiceClient(blobUri, defaultCredential);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "BlobServiceClient: Failed to create URI from storage account name '{StorageAccount}'", storageAccountName);
        throw;
    }
});

// Register TableServiceClient (for password expiry lookups)
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var logger = sp.GetRequiredService<ILogger<Program>>();
    
    // Try environment variable first (faster, no App Config needed)
    var storageAccountName = Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__StorageAccountName");
    logger.LogDebug("TableServiceClient: EnvVar IntuneUp__PasswordExpiry__StorageAccountName = '{Value}'", storageAccountName ?? "NULL");

    // Fallback to config if env var not set
    if (string.IsNullOrWhiteSpace(storageAccountName))
    {
        storageAccountName = config["IntuneUp:PasswordExpiry:StorageAccountName"];
        logger.LogDebug("TableServiceClient: Config IntuneUp:PasswordExpiry:StorageAccountName = '{Value}'", storageAccountName ?? "NULL");
    }

    if (string.IsNullOrWhiteSpace(storageAccountName))
    {
        logger.LogError("TableServiceClient: Storage account name not found in environment or configuration");
        throw new InvalidOperationException("IntuneUp__PasswordExpiry__StorageAccountName environment variable or IntuneUp:PasswordExpiry:StorageAccountName config must be set");
    }

    try
    {
        var tableUri = new Uri($"https://{storageAccountName}.table.core.windows.net");
        logger.LogInformation("TableServiceClient: Using storage account {StorageAccount}", storageAccountName);
        return new Azure.Data.Tables.TableServiceClient(tableUri, defaultCredential);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "TableServiceClient: Failed to create URI from storage account name '{StorageAccount}'", storageAccountName);
        throw;
    }
});

builder.Build().Run();
