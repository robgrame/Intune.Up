namespace IntuneUp.Notify.Models;

/// <summary>
/// Exit codes returned by the process based on user action.
/// Designed for consumption by Intune proactive remediations or scripts.
/// </summary>
public static class ExitCodes
{
    /// <summary>User acknowledged (OK/Yes).</summary>
    public const int Acknowledged = 0;

    /// <summary>User chose to snooze.</summary>
    public const int Snoozed = 1;

    /// <summary>User dismissed or clicked Cancel/No.</summary>
    public const int Dismissed = 2;

    /// <summary>Dialog timed out without user action.</summary>
    public const int TimedOut = 3;

    /// <summary>Invalid payload or argument error.</summary>
    public const int InvalidPayload = 10;

    /// <summary>Unexpected runtime error.</summary>
    public const int RuntimeError = 99;
}
