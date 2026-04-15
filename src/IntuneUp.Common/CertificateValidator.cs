namespace IntuneUp.Common;

using System.Security.Cryptography.X509Certificates;

/// <summary>
/// Validates client certificates by verifying the issuer/CA thumbprint
/// in the certificate chain against an allowlist.
/// </summary>
public sealed class CertificateValidator
{
    private readonly HashSet<string> _allowedIssuerThumbprints;

    /// <param name="commaDelimitedIssuerThumbprints">Allowed issuer/CA thumbprints (any cert signed by these CAs is accepted)</param>
    public CertificateValidator(string? commaDelimitedIssuerThumbprints)
    {
        _allowedIssuerThumbprints = ParseList(commaDelimitedIssuerThumbprints);
    }

    /// <summary>
    /// Validate a full X509Certificate2 by checking issuer thumbprint in chain.
    /// </summary>
    public bool IsValid(X509Certificate2? certificate)
    {
        if (certificate is null || _allowedIssuerThumbprints.Count == 0)
            return false;

        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.Build(certificate);

        foreach (var element in chain.ChainElements)
        {
            if (_allowedIssuerThumbprints.Contains(element.Certificate.Thumbprint.ToUpperInvariant()))
                return true;
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
