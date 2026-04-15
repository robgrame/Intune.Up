namespace IntuneUp.Common;

using System.Security.Cryptography.X509Certificates;

/// <summary>
/// Validates client certificates against an allowlist of thumbprints
/// and/or trusted issuer thumbprints.
/// </summary>
public sealed class CertificateValidator
{
    private readonly HashSet<string> _allowedThumbprints;
    private readonly HashSet<string> _allowedIssuerThumbprints;

    /// <param name="commaDelimitedThumbprints">Allowed client cert thumbprints (exact match)</param>
    /// <param name="commaDelimitedIssuerThumbprints">Allowed issuer/CA thumbprints (any cert signed by these CAs is accepted)</param>
    public CertificateValidator(string? commaDelimitedThumbprints, string? commaDelimitedIssuerThumbprints = null)
    {
        _allowedThumbprints = ParseList(commaDelimitedThumbprints);
        _allowedIssuerThumbprints = ParseList(commaDelimitedIssuerThumbprints);
    }

    /// <summary>
    /// Validate by thumbprint string only (legacy/fallback).
    /// </summary>
    public bool IsValid(string? thumbprint)
    {
        if (string.IsNullOrWhiteSpace(thumbprint))
            return false;

        return _allowedThumbprints.Contains(thumbprint.Trim().ToUpperInvariant());
    }

    /// <summary>
    /// Validate a full X509Certificate2: checks client thumbprint OR issuer thumbprint.
    /// </summary>
    public bool IsValid(X509Certificate2? certificate)
    {
        if (certificate is null)
            return false;

        // Check direct thumbprint match
        if (_allowedThumbprints.Count > 0 &&
            _allowedThumbprints.Contains(certificate.Thumbprint.ToUpperInvariant()))
            return true;

        // Check issuer thumbprint (cert signed by a trusted CA)
        if (_allowedIssuerThumbprints.Count > 0)
        {
            using var chain = new X509Chain();
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            chain.Build(certificate);

            foreach (var element in chain.ChainElements)
            {
                if (_allowedIssuerThumbprints.Contains(element.Certificate.Thumbprint.ToUpperInvariant()))
                    return true;
            }
        }

        return false;
    }

    private static HashSet<string> ParseList(string? commaDelimited)
    {
        return (commaDelimited ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => t.ToUpperInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }
}
