using System.Text.Json.Serialization;

namespace IntuneUp.Common.Models;

/// <summary>
/// Payload sent by endpoint collection scripts.
/// </summary>
public sealed class DeviceTelemetryPayload
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
}
