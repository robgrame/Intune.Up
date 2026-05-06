using System;
using System.IO;
using System.Text.Json;
using System.Windows;
using IntuneUp.Notify.Models;

namespace IntuneUp.Notify;

public partial class App : Application
{
    internal static NotificationPayload? Payload { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        try
        {
            Payload = ParseArguments(e.Args);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Invalid arguments: {ex.Message}", "IntuneUp.Notify", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(ExitCodes.InvalidPayload);
            return;
        }

        if (Payload == null)
        {
            ShowUsage();
            Shutdown(ExitCodes.InvalidPayload);
            return;
        }

        var window = new NotificationWindow(Payload);
        window.Show();
    }

    private static NotificationPayload? ParseArguments(string[] args)
    {
        if (args.Length == 0)
            return null;

        string? json = null;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--message":
                case "-m":
                    if (i + 1 < args.Length)
                        json = args[++i];
                    break;

                case "--file":
                case "-f":
                    if (i + 1 < args.Length)
                    {
                        var filePath = args[++i];
                        if (!File.Exists(filePath))
                            throw new FileNotFoundException($"Payload file not found: {filePath}");
                        json = File.ReadAllText(filePath);
                    }
                    break;

                case "--help":
                case "-h":
                case "/?":
                    return null;
            }
        }

        if (string.IsNullOrWhiteSpace(json))
            return null;

        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() }
        };

        return JsonSerializer.Deserialize<NotificationPayload>(json!, options)
               ?? throw new InvalidOperationException("Failed to deserialize payload");
    }

    private static void ShowUsage()
    {
        const string usage = @"IntuneUp.Notify - Client-side notification dialog

Usage:
  IntuneUp.Notify.exe --message <json>
  IntuneUp.Notify.exe --file <path-to-json>

Options:
  -m, --message   JSON payload inline
  -f, --file      Path to JSON payload file
  -h, --help      Show this help

Exit codes:
  0  = User acknowledged (OK/Yes)
  1  = User snoozed
  2  = User dismissed (Cancel/No)
  3  = Dialog timed out
  10 = Invalid payload
  99 = Runtime error

Example:
  IntuneUp.Notify.exe -m ""{ \""title\"": \""Password Expiring\"", \""body\"": \""Your password expires in 3 days.\"", \""buttons\"": \""OkSnooze\"" }""
";
        MessageBox.Show(usage, "IntuneUp.Notify - Usage", MessageBoxButton.OK, MessageBoxImage.Information);
    }
}
