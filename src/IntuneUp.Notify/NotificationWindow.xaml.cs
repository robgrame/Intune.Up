using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using IntuneUp.Notify.Models;

namespace IntuneUp.Notify;

public partial class NotificationWindow : Window
{
    private readonly NotificationPayload _payload;
    private readonly DispatcherTimer? _timer;
    private int _remainingSeconds;
    private int _exitCode = ExitCodes.Dismissed;

    public NotificationWindow(NotificationPayload payload)
    {
        InitializeComponent();

        _payload = payload;
        Topmost = payload.Topmost;
        Title = payload.Title;

        ConfigureHeader();
        ConfigureContent();
        ConfigureButtons();

        if (payload.TimeoutSeconds > 0)
        {
            _remainingSeconds = payload.TimeoutSeconds;
            TimeoutText.Text = $"This dialog will close automatically in {_remainingSeconds} seconds.";
            TimeoutText.Visibility = Visibility.Visible;

            _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _timer.Tick += OnTimerTick;
            _timer.Start();
        }
    }

    private void ConfigureHeader()
    {
        TitleText.Text = _payload.Title;

        // Organization name
        if (!string.IsNullOrWhiteSpace(_payload.Organization))
        {
            OrgText.Text = _payload.Organization;
            OrgText.Visibility = Visibility.Visible;
        }

        // Logo
        if (!string.IsNullOrWhiteSpace(_payload.LogoPath) && File.Exists(_payload.LogoPath))
        {
            try
            {
                var bitmap = new BitmapImage(new Uri(_payload.LogoPath, UriKind.Absolute));
                LogoImage.Source = bitmap;
                LogoImage.Visibility = Visibility.Visible;
            }
            catch
            {
                // Ignore logo errors
            }
        }

        // Icon emoji based on type
        IconText.Text = _payload.Icon switch
        {
            NotificationIcon.Warning => "⚠️",
            NotificationIcon.Error => "❌",
            NotificationIcon.Shield => "🛡️",
            _ => "ℹ️"
        };
    }

    private void ConfigureContent()
    {
        if (!string.IsNullOrWhiteSpace(_payload.Subtitle))
        {
            SubtitleText.Text = _payload.Subtitle;
            SubtitleText.Visibility = Visibility.Visible;
        }

        BodyText.Text = _payload.Body.Replace("\\n", Environment.NewLine);
    }

    private void ConfigureButtons()
    {
        switch (_payload.Buttons)
        {
            case NotificationButtons.Ok:
                AddButton("OK", ExitCodes.Acknowledged, isPrimary: true);
                break;

            case NotificationButtons.OkSnooze:
                AddButton("Snooze", ExitCodes.Snoozed, isPrimary: false);
                AddButton("OK", ExitCodes.Acknowledged, isPrimary: true);
                break;

            case NotificationButtons.OkCancel:
                AddButton("Cancel", ExitCodes.Dismissed, isPrimary: false);
                AddButton("OK", ExitCodes.Acknowledged, isPrimary: true);
                break;

            case NotificationButtons.YesNo:
                AddButton("No", ExitCodes.Dismissed, isPrimary: false);
                AddButton("Yes", ExitCodes.Acknowledged, isPrimary: true);
                break;
        }
    }

    private void AddButton(string text, int exitCode, bool isPrimary)
    {
        var button = new Button
        {
            Content = text,
            Style = (Style)FindResource(isPrimary ? "PrimaryButton" : "SecondaryButton")
        };

        button.Click += (_, _) =>
        {
            _exitCode = exitCode;
            CloseDialog();
        };

        ButtonPanel.Children.Add(button);
    }

    private void OnTimerTick(object? sender, EventArgs e)
    {
        _remainingSeconds--;
        TimeoutText.Text = $"This dialog will close automatically in {_remainingSeconds} seconds.";

        if (_remainingSeconds <= 0)
        {
            _exitCode = ExitCodes.TimedOut;
            CloseDialog();
        }
    }

    private void CloseDialog()
    {
        _timer?.Stop();
        Application.Current.Shutdown(_exitCode);
    }

    protected override void OnClosed(EventArgs e)
    {
        _timer?.Stop();
        base.OnClosed(e);
        Application.Current.Shutdown(_exitCode);
    }
}
