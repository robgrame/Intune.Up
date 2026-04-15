using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Register ServiceBusClient with Managed Identity
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<Microsoft.Extensions.Configuration.IConfiguration>();
    var sbConnection = config["SERVICEBUS_CONNECTION"];

    if (!string.IsNullOrEmpty(sbConnection) && sbConnection.Contains("Endpoint="))
        return new ServiceBusClient(sbConnection);

    var sbNamespace = config["SERVICEBUS_NAMESPACE"] ?? "sb-intuneup-dev.servicebus.windows.net";
    return new ServiceBusClient(sbNamespace, new DefaultAzureCredential());
});

builder.Build().Run();
