using Azure.Data.Tables;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

var defaultCredential = new DefaultAzureCredential();

// ServiceBusClient with DefaultAzureCredential (managed identity in prod)
var sbNamespace = builder.Configuration["IntuneUp:ServiceBus:Namespace"]
    ?? Environment.GetEnvironmentVariable("IntuneUp__ServiceBus__Namespace")
    ?? Environment.GetEnvironmentVariable("ServiceBusNamespace")
    ?? throw new InvalidOperationException(
        "Service Bus namespace is not configured. Set app setting 'IntuneUp__ServiceBus__Namespace' " +
        "to '<namespace>.servicebus.windows.net'.");

builder.Services.AddSingleton(_ => new ServiceBusClient(sbNamespace, defaultCredential));

// TableServiceClient for PasswordExpiry functions (reads/writes Azure Table Storage)
var pwdExpiryStorageAccount = Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__StorageAccountName")
    ?? builder.Configuration["IntuneUp:PasswordExpiry:StorageAccountName"]
    ?? "";

if (!string.IsNullOrWhiteSpace(pwdExpiryStorageAccount))
{
    var tableUri = new Uri($"https://{pwdExpiryStorageAccount}.table.core.windows.net");
    builder.Services.AddSingleton(_ => new TableServiceClient(tableUri, defaultCredential));
}

await builder.Build().RunAsync();
