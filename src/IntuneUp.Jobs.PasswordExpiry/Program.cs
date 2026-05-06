using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Data.Tables;
using Microsoft.Graph;

var builder = FunctionsApplication.CreateBuilder(args);

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

var credential = new DefaultAzureCredential();

// Microsoft Graph client (User.Read.All permission via Managed Identity)
builder.Services.AddSingleton(_ => new GraphServiceClient(credential));

// Azure Table Storage client
builder.Services.AddSingleton(sp =>
{
    var storageAccountName = Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__StorageAccountName")
        ?? throw new InvalidOperationException("IntuneUp__PasswordExpiry__StorageAccountName must be set");
    var tableUri = new Uri($"https://{storageAccountName}.table.core.windows.net");
    return new TableServiceClient(tableUri, credential);
});

builder.Build().Run();
