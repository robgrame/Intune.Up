using System.Text.Json.Serialization;

namespace IntuneUp.Common.Models;

/// <summary>
/// Enriched message placed on the Service Bus queue.
/// </summary>
public sealed class EnrichedTelemetryMessage
{
    [JsonPropertyName("DeviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("DeviceName")]
    public string DeviceName { get; set; } = string.Empty;

    [JsonPropertyName("UPN")]
    public string? UPN { get; set; }

    [JsonPropertyName("UseCase")]
    public string UseCase { get; set; } = string.Empty;

    [JsonPropertyName("Data")]
    public Dictionary<string, object>? Data { get; set; }

    [JsonPropertyName("ReceivedAt")]
    public DateTimeOffset ReceivedAt { get; set; }

    [JsonPropertyName("FunctionRegion")]
    public string? FunctionRegion { get; set; }
}
