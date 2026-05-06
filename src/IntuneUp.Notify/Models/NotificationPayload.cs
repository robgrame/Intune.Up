using System.Text.Json.Serialization;

namespace IntuneUp.Notify.Models;

/// <summary>
/// Represents the notification message payload.
/// Passed via --message JSON or --file path.
/// </summary>
public class NotificationPayload
{
    /// <summary>Dialog window title.</summary>
    [JsonPropertyName("title")]
    public string Title { get; set; } = "Notification";

    /// <summary>Main message body (supports basic line breaks with \n).</summary>
    [JsonPropertyName("body")]
    public string Body { get; set; } = string.Empty;

    /// <summary>Optional subtitle shown below the title.</summary>
    [JsonPropertyName("subtitle")]
    public string? Subtitle { get; set; }

    /// <summary>Icon type: Info, Warning, Error, Shield. Default: Info.</summary>
    [JsonPropertyName("icon")]
    public NotificationIcon Icon { get; set; } = NotificationIcon.Info;

    /// <summary>Buttons to display. Default: OK only.</summary>
    [JsonPropertyName("buttons")]
    public NotificationButtons Buttons { get; set; } = NotificationButtons.Ok;

    /// <summary>Auto-dismiss timeout in seconds. 0 = no timeout.</summary>
    [JsonPropertyName("timeoutSeconds")]
    public int TimeoutSeconds { get; set; } = 0;

    /// <summary>Optional company/org name shown in header.</summary>
    [JsonPropertyName("organization")]
    public string? Organization { get; set; }

    /// <summary>Optional logo path (local file) shown in header.</summary>
    [JsonPropertyName("logoPath")]
    public string? LogoPath { get; set; }

    /// <summary>If true, dialog is topmost and cannot be moved behind other windows.</summary>
    [JsonPropertyName("topmost")]
    public bool Topmost { get; set; } = true;
}

public enum NotificationIcon
{
    Info,
    Warning,
    Error,
    Shield
}

public enum NotificationButtons
{
    Ok,
    OkSnooze,
    OkCancel,
    YesNo
}
