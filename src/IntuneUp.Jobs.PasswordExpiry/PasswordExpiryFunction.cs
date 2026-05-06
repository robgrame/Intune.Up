using Azure;
using Azure.Data.Tables;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Microsoft.Kiota.Abstractions;
using System.Net;

namespace IntuneUp.Jobs.PasswordExpiry;

/// <summary>
/// Timer-triggered function that replaces the Azure Automation runbook.
/// Queries Microsoft Graph for users with passwords expiring within ThresholdDays
/// and writes records to Azure Table Storage for client-side pull detection.
/// 
/// Designed for large tenants (400K+ users):
///   - Streams pages from Graph API (never loads all users in memory)
///   - Uses batch operations for Table Storage writes (up to 100 per transaction)
///   - Implements retry with exponential backoff for Graph API throttling (429)
///   - Uses server-side $filter to reduce payload where possible
///   - Writes new records first, then cleans stale ones (no data gap)
/// 
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

    // Graph API page size (max 999)
    private const int GraphPageSize = 999;

    // Table Storage batch limit
    private const int TableBatchSize = 100;

    // Retry config for Graph throttling
    private const int MaxRetries = 5;
    private static readonly TimeSpan InitialBackoff = TimeSpan.FromSeconds(5);

    [Function("WritePasswordExpiryTriggers")]
    public async Task RunAsync(
        [TimerTrigger("0 0 6 * * *")] TimerInfo timerInfo,
        CancellationToken cancellationToken)
    {
        logger.LogInformation(
            "PasswordExpiry job started. MaxAgeDays={MaxAge}, ThresholdDays={Threshold}, Table={Table}",
            MaxPasswordAgeDays, ThresholdDays, TableName);

        var tableClient = tableServiceClient.GetTableClient(TableName);
        await tableClient.CreateIfNotExistsAsync(cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var targetDate = now.AddDays(ThresholdDays);

        // Server-side filter: only users whose password was changed between
        // (now - MaxPasswordAgeDays) and (targetDate - MaxPasswordAgeDays)
        // i.e., passwords that will expire between now and targetDate
        var filterStart = now.AddDays(-MaxPasswordAgeDays);
        var filterEnd = targetDate.AddDays(-MaxPasswordAgeDays);

        // Phase 1: Stream users from Graph and write to Table Storage in batches
        var written = await WriteExpiringUsersAsync(tableClient, now, targetDate, filterStart, filterEnd, cancellationToken);
        logger.LogInformation("Written {Count} password expiry records", written);

        // Phase 2: Clean stale records (written before this run)
        var cleaned = await CleanStaleRecordsAsync(tableClient, now, cancellationToken);
        logger.LogInformation("Cleaned {Count} stale records", cleaned);

        logger.LogInformation("PasswordExpiry job completed. Written={Written}, Cleaned={Cleaned}", written, cleaned);
    }

    private async Task<int> WriteExpiringUsersAsync(
        TableClient tableClient,
        DateTimeOffset now,
        DateTimeOffset targetDate,
        DateTimeOffset filterStart,
        DateTimeOffset filterEnd,
        CancellationToken ct)
    {
        var written = 0;
        var pagesProcessed = 0;

        // Graph filter: accountEnabled eq true AND lastPasswordChangeDateTime in range
        var graphFilter = $"accountEnabled eq true and lastPasswordChangeDateTime ge {filterStart:yyyy-MM-ddTHH:mm:ssZ} and lastPasswordChangeDateTime le {filterEnd:yyyy-MM-ddTHH:mm:ssZ}";

        logger.LogInformation("Graph filter: {Filter}", graphFilter);

        var usersResponse = await ExecuteWithRetryAsync(
            () => graphClient.Users.GetAsync(req =>
            {
                req.QueryParameters.Select = ["id", "userPrincipalName", "lastPasswordChangeDateTime"];
                req.QueryParameters.Filter = graphFilter;
                req.QueryParameters.Top = GraphPageSize;
                req.QueryParameters.Count = true;
                req.Headers.Add("ConsistencyLevel", "eventual");
            }, ct), ct);

        if (usersResponse?.OdataCount.HasValue == true)
        {
            logger.LogInformation("Graph reports {Count} total matching users", usersResponse.OdataCount.Value);
        }

        // Process first page
        pagesProcessed++;
        written += await ProcessUsersPageAsync(usersResponse?.Value, tableClient, now, targetDate, ct);

        // Process subsequent pages
        var nextLink = usersResponse?.OdataNextLink;
        while (!string.IsNullOrEmpty(nextLink))
        {
            ct.ThrowIfCancellationRequested();

            var nextPage = await ExecuteWithRetryAsync(
                () => graphClient.Users.WithUrl(nextLink).GetAsync(cancellationToken: ct), ct);

            pagesProcessed++;
            if (pagesProcessed % 50 == 0)
            {
                logger.LogInformation("Processed {Pages} pages, {Written} records written so far", pagesProcessed, written);
            }

            written += await ProcessUsersPageAsync(nextPage?.Value, tableClient, now, targetDate, ct);

            nextLink = nextPage?.OdataNextLink;
        }

        // Flush handled inside ProcessUsersPageAsync per page

        logger.LogInformation("Processed {Pages} total Graph pages", pagesProcessed);
        return written;
    }

    private async Task<int> ProcessUsersPageAsync(
        List<User>? users,
        TableClient tableClient,
        DateTimeOffset now,
        DateTimeOffset targetDate,
        CancellationToken ct)
    {
        if (users is null || users.Count == 0) return 0;

        var batch = new List<TableTransactionAction>(TableBatchSize);
        var written = 0;

        foreach (var user in users)
        {
            if (user.LastPasswordChangeDateTime is null || string.IsNullOrEmpty(user.UserPrincipalName))
                continue;

            var expiryDate = user.LastPasswordChangeDateTime.Value.AddDays(MaxPasswordAgeDays);

            if (expiryDate > now && expiryDate <= targetDate)
            {
                var daysUntilExpiry = (int)Math.Round((expiryDate - now).TotalDays);
                var entity = new TableEntity("PasswordExpiry", user.UserPrincipalName.ToLowerInvariant())
                {
                    { "DaysUntilExpiry", daysUntilExpiry },
                    { "UserUPN", user.UserPrincipalName },
                    { "ExpiryDate", expiryDate.ToString("yyyy-MM-dd") },
                    { "WrittenAt", now.ToString("o") }
                };

                batch.Add(new TableTransactionAction(TableTransactionActionType.UpsertReplace, entity));

                if (batch.Count >= TableBatchSize)
                {
                    await SubmitBatchAsync(tableClient, batch, ct);
                    written += batch.Count;
                    batch = new List<TableTransactionAction>(TableBatchSize);
                }
            }
        }

        // Flush remaining
        if (batch.Count > 0)
        {
            await SubmitBatchAsync(tableClient, batch, ct);
            written += batch.Count;
        }

        return written;
    }

    private async Task SubmitBatchAsync(TableClient tableClient, List<TableTransactionAction> batch, CancellationToken ct)
    {
        if (batch.Count == 0) return;

        try
        {
            await tableClient.SubmitTransactionAsync(batch, ct);
        }
        catch (TableTransactionFailedException)
        {
            // Batch transactions require same PartitionKey — ours are all "PasswordExpiry"
            // so this shouldn't happen, but fall back to individual upserts if it does
            logger.LogWarning("Batch transaction failed, falling back to individual upserts for {Count} entities", batch.Count);
            foreach (var action in batch)
            {
                await tableClient.UpsertEntityAsync(action.Entity, TableUpdateMode.Replace, ct);
            }
        }
    }

    private async Task<int> CleanStaleRecordsAsync(TableClient tableClient, DateTimeOffset currentRunTimestamp, CancellationToken ct)
    {
        // Delete records whose WrittenAt is older than current run (from a previous run)
        var count = 0;
        var deleteBatch = new List<TableTransactionAction>(TableBatchSize);

        await foreach (var entity in tableClient.QueryAsync<TableEntity>(
            filter: "PartitionKey eq 'PasswordExpiry'",
            select: new[] { "PartitionKey", "RowKey", "WrittenAt" },
            cancellationToken: ct))
        {
            var writtenAt = entity.GetString("WrittenAt");
            if (writtenAt is not null && DateTimeOffset.TryParse(writtenAt, out var ts) && ts < currentRunTimestamp)
            {
                deleteBatch.Add(new TableTransactionAction(TableTransactionActionType.Delete, entity));
                count++;

                if (deleteBatch.Count >= TableBatchSize)
                {
                    await SubmitDeleteBatchAsync(tableClient, deleteBatch, ct);
                    deleteBatch = new List<TableTransactionAction>(TableBatchSize);
                }
            }
        }

        if (deleteBatch.Count > 0)
        {
            await SubmitDeleteBatchAsync(tableClient, deleteBatch, ct);
        }

        return count;
    }

    private async Task SubmitDeleteBatchAsync(TableClient tableClient, List<TableTransactionAction> batch, CancellationToken ct)
    {
        try
        {
            await tableClient.SubmitTransactionAsync(batch, ct);
        }
        catch (TableTransactionFailedException)
        {
            foreach (var action in batch)
            {
                try
                {
                    await tableClient.DeleteEntityAsync(action.Entity.PartitionKey, action.Entity.RowKey, ETag.All, ct);
                }
                catch (RequestFailedException ex) when (ex.Status == (int)HttpStatusCode.NotFound)
                {
                    // Already deleted, ignore
                }
            }
        }
    }

    /// <summary>
    /// Executes a Graph API call with retry and exponential backoff for 429 (Too Many Requests)
    /// and 503 (Service Unavailable) responses.
    /// </summary>
    private async Task<T?> ExecuteWithRetryAsync<T>(Func<Task<T?>> operation, CancellationToken ct) where T : class
    {
        var delay = InitialBackoff;

        for (var attempt = 0; attempt <= MaxRetries; attempt++)
        {
            try
            {
                return await operation();
            }
            catch (ApiException ex) when (ex.ResponseStatusCode == (int)HttpStatusCode.TooManyRequests ||
                                          ex.ResponseStatusCode == (int)HttpStatusCode.ServiceUnavailable)
            {
                if (attempt == MaxRetries)
                {
                    logger.LogError(ex, "Graph API throttled after {Attempts} retries. Giving up.", MaxRetries);
                    throw;
                }

                // Respect Retry-After header if present
                var retryAfter = ex.ResponseHeaders?.TryGetValue("Retry-After", out var values) == true
                    && values.Any()
                    && int.TryParse(values.First(), out var seconds)
                        ? TimeSpan.FromSeconds(seconds)
                        : delay;

                logger.LogWarning(
                    "Graph API throttled (HTTP {Status}). Attempt {Attempt}/{Max}. Waiting {Delay}s before retry.",
                    ex.ResponseStatusCode, attempt + 1, MaxRetries, retryAfter.TotalSeconds);

                await Task.Delay(retryAfter, ct);
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, 120)); // cap at 2 minutes
            }
        }

        return null; // unreachable
    }
}
