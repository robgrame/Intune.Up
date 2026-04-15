namespace IntuneUp.Common;

/// <summary>
/// Validates client certificate thumbprints against an allowlist.
/// </summary>
public sealed class CertificateValidator
{
    private readonly HashSet<string> _allowedThumbprints;

    public CertificateValidator(string? commaDelimitedThumbprints)
    {
        _allowedThumbprints = (commaDelimitedThumbprints ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => t.ToUpperInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    public bool IsValid(string? thumbprint)
    {
        if (string.IsNullOrWhiteSpace(thumbprint))
            return false;

        return _allowedThumbprints.Contains(thumbprint.Trim().ToUpperInvariant());
    }
}
