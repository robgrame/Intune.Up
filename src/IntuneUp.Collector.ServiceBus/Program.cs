using Azure.Identity;
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

// HttpClient for Log Analytics Data Collector API
builder.Services.AddHttpClient("LogAnalytics");

builder.Build().Run();
