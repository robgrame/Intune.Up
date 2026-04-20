using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

// ServiceBusClient with DefaultAzureCredential (managed identity in prod)
var defaultCredential = new DefaultAzureCredential();
var sbNamespace = builder.Configuration["IntuneUp:ServiceBus:Namespace"]
    ?? Environment.GetEnvironmentVariable("IntuneUp__ServiceBus__Namespace")
    ?? Environment.GetEnvironmentVariable("ServiceBusNamespace")
    ?? throw new InvalidOperationException(
        "Service Bus namespace is not configured. Set app setting 'IntuneUp__ServiceBus__Namespace' " +
        "to '<namespace>.servicebus.windows.net'.");

builder.Services.AddSingleton(_ => new ServiceBusClient(sbNamespace, defaultCredential));

await builder.Build().RunAsync();
