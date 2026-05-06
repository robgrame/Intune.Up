using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Microsoft.Graph.Models;

namespace IntuneUp.Jobs.PasswordExpiry;

/// <summary>
/// Timer-triggered function that replaces the Azure Automation runbook.
/// Queries Microsoft Graph for users with passwords expiring within ThresholdDays
/// and writes records to Azure Table Storage for client-side pull detection.
/// Schedule: daily at 06:00 UTC.
/// </summary>
public class PasswordExpiryFunction(
    GraphServiceClient graphClient,
    TableServiceClient tableServiceClient,
    ILogger<PasswordExpiryFunction> logger)
{
    private static readonly string TableName =
        Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__TableName") ?? "PasswordExpiry";

    private static readonly int MaxPasswordAgeDays =
        int.TryParse(Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__MaxAgeDays"), out var v) ? v : 90;

    private static readonly int ThresholdDays =
        int.TryParse(Environment.GetEnvironmentVariable("IntuneUp__PasswordExpiry__ThresholdDays"), out var t) ? t : 10;

    [Function("WritePasswordExpiryTriggers")]
    public async Task RunAsync(
        [TimerTrigger("0 0 6 * * *")] TimerInfo timerInfo,
        CancellationToken cancellationToken)
    {
        logger.LogInformation("PasswordExpiry job started. MaxAgeDays={MaxAge}, ThresholdDays={Threshold}",
            MaxPasswordAgeDays, ThresholdDays);

        var tableClient = tableServiceClient.GetTableClient(TableName);
        await tableClient.CreateIfNotExistsAsync(cancellationToken);

        // Clean old records
        var deleted = await CleanExistingRecordsAsync(tableClient, cancellationToken);
        logger.LogInformation("Cleaned {Count} old records", deleted);

        // Query users with expiring passwords
        var now = DateTimeOffset.UtcNow;
        var targetDate = now.AddDays(ThresholdDays);

        var users = await GetUsersWithExpiringPasswordsAsync(now, targetDate, cancellationToken);
        logger.LogInformation("Found {Count} users with passwords expiring within {Days} days", users.Count, ThresholdDays);

        // Write records
        var written = 0;
        foreach (var (upn, expiryDate, daysUntilExpiry) in users)
        {
            var entity = new TableEntity("PasswordExpiry", upn.ToLowerInvariant())
            {
                { "DaysUntilExpiry", daysUntilExpiry },
                { "UserUPN", upn },
                { "ExpiryDate", expiryDate.ToString("yyyy-MM-dd") },
                { "WrittenAt", now.ToString("o") }
            };

            await tableClient.UpsertEntityAsync(entity, TableUpdateMode.Replace, cancellationToken);
            written++;
        }

        logger.LogInformation("Written {Count} password expiry records to table {Table}", written, TableName);
    }

    private async Task<int> CleanExistingRecordsAsync(TableClient tableClient, CancellationToken ct)
    {
        var count = 0;
        await foreach (var entity in tableClient.QueryAsync<TableEntity>(
            filter: "PartitionKey eq 'PasswordExpiry'",
            select: new[] { "PartitionKey", "RowKey" },
            cancellationToken: ct))
        {
            await tableClient.DeleteEntityAsync(entity.PartitionKey, entity.RowKey, entity.ETag, ct);
            count++;
        }
        return count;
    }

    private async Task<List<(string Upn, DateTimeOffset ExpiryDate, int DaysUntilExpiry)>> GetUsersWithExpiringPasswordsAsync(
        DateTimeOffset now, DateTimeOffset targetDate, CancellationToken ct)
    {
        var results = new List<(string, DateTimeOffset, int)>();

        var usersResponse = await graphClient.Users.GetAsync(req =>
        {
            req.QueryParameters.Select = ["id", "userPrincipalName", "lastPasswordChangeDateTime"];
            req.QueryParameters.Filter = "accountEnabled eq true";
            req.QueryParameters.Top = 999;
        }, ct);

        var users = usersResponse?.Value ?? [];

        foreach (var user in users)
        {
            if (user.LastPasswordChangeDateTime is null || string.IsNullOrEmpty(user.UserPrincipalName))
                continue;

            var expiryDate = user.LastPasswordChangeDateTime.Value.AddDays(MaxPasswordAgeDays);

            if (expiryDate <= targetDate && expiryDate > now)
            {
                var daysUntilExpiry = (int)Math.Round((expiryDate - now).TotalDays);
                results.Add((user.UserPrincipalName, expiryDate, daysUntilExpiry));
            }
        }

        // Handle pagination
        var nextLink = usersResponse?.OdataNextLink;
        while (!string.IsNullOrEmpty(nextLink))
        {
            var nextPage = await graphClient.Users
                .WithUrl(nextLink)
                .GetAsync(cancellationToken: ct);

            foreach (var user in nextPage?.Value ?? [])
            {
                if (user.LastPasswordChangeDateTime is null || string.IsNullOrEmpty(user.UserPrincipalName))
                    continue;

                var expiryDate = user.LastPasswordChangeDateTime.Value.AddDays(MaxPasswordAgeDays);

                if (expiryDate <= targetDate && expiryDate > now)
                {
                    var daysUntilExpiry = (int)Math.Round((expiryDate - now).TotalDays);
                    results.Add((user.UserPrincipalName, expiryDate, daysUntilExpiry));
                }
            }

            nextLink = nextPage?.OdataNextLink;
        }

        return results;
    }
}
