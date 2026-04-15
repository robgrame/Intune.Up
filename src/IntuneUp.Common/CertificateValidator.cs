namespace IntuneUp.Common;

using System.Security.Cryptography.X509Certificates;

/// <summary>
/// Validates client certificates with multiple checks:
/// - Issuer/CA thumbprint in certificate chain
/// - Certificate not expired (NotBefore / NotAfter)
/// - Certificate chain is valid
/// - Enhanced Key Usage includes Client Authentication (if present)
/// - Subject matches expected pattern (optional)
/// </summary>
public sealed class CertificateValidator
{
    private readonly HashSet<string> _allowedIssuerThumbprints;
    private readonly string? _requiredSubjectPattern;
    private readonly bool _checkRevocation;

    /// <param name="commaDelimitedIssuerThumbprints">Allowed issuer/CA thumbprints</param>
    /// <param name="requiredSubjectPattern">Optional: required substring in Subject (e.g. "CN=IntuneUp")</param>
    /// <param name="checkRevocation">If true, validates CRL/OCSP revocation status. Default false (Azure may not reach CRL endpoints).</param>
    public CertificateValidator(string? commaDelimitedIssuerThumbprints, string? requiredSubjectPattern = null, bool checkRevocation = false)
    {
        _allowedIssuerThumbprints = ParseList(commaDelimitedIssuerThumbprints);
        _requiredSubjectPattern = string.IsNullOrWhiteSpace(requiredSubjectPattern) ? null : requiredSubjectPattern;
        _checkRevocation = checkRevocation;
    }

    public CertificateValidationResult Validate(X509Certificate2? certificate)
    {
        if (certificate is null)
            return CertificateValidationResult.Fail("No certificate provided");

        // 1. Expiration check
        var now = DateTime.UtcNow;
        if (now < certificate.NotBefore)
            return CertificateValidationResult.Fail($"Certificate not yet valid (NotBefore: {certificate.NotBefore:o})");
        if (now > certificate.NotAfter)
            return CertificateValidationResult.Fail($"Certificate expired (NotAfter: {certificate.NotAfter:o})");

        // 2. Subject pattern check (optional)
        if (_requiredSubjectPattern is not null &&
            !certificate.Subject.Contains(_requiredSubjectPattern, StringComparison.OrdinalIgnoreCase))
            return CertificateValidationResult.Fail($"Subject '{certificate.Subject}' does not match required pattern '{_requiredSubjectPattern}'");

        // 3. Enhanced Key Usage - if present, must include Client Authentication (1.3.6.1.5.5.7.3.2)
        var ekuExtension = certificate.Extensions.OfType<X509EnhancedKeyUsageExtension>().FirstOrDefault();
        if (ekuExtension is not null)
        {
            var hasClientAuth = ekuExtension.EnhancedKeyUsages
                .Cast<System.Security.Cryptography.Oid>()
                .Any(oid => oid.Value == "1.3.6.1.5.5.7.3.2");
            if (!hasClientAuth)
                return CertificateValidationResult.Fail("Certificate EKU does not include Client Authentication (1.3.6.1.5.5.7.3.2)");
        }

        // 4. Chain validity + issuer thumbprint check
        if (_allowedIssuerThumbprints.Count == 0)
            return CertificateValidationResult.Fail("No allowed issuer thumbprints configured");

        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = _checkRevocation ? X509RevocationMode.Online : X509RevocationMode.NoCheck;
        chain.ChainPolicy.RevocationFlag = X509RevocationFlag.EntireChain;
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;

        var chainValid = chain.Build(certificate);

        // Check chain status for critical errors (ignore UntrustedRoot since we validate issuer manually)
        if (!chainValid)
        {
            var ignoredStatuses = new HashSet<X509ChainStatusFlags> { X509ChainStatusFlags.NoError, X509ChainStatusFlags.UntrustedRoot };
            if (!_checkRevocation)
            {
                ignoredStatuses.Add(X509ChainStatusFlags.RevocationStatusUnknown);
                ignoredStatuses.Add(X509ChainStatusFlags.OfflineRevocation);
            }

            var criticalErrors = chain.ChainStatus
                .Where(s => !ignoredStatuses.Contains(s.Status))
                .ToList();

            if (criticalErrors.Count > 0)
            {
                var errors = string.Join(", ", criticalErrors.Select(e => $"{e.Status}: {e.StatusInformation}"));
                return CertificateValidationResult.Fail($"Certificate chain validation failed: {errors}");
            }
        }

        // Check issuer thumbprint in chain (skip element[0] which is the leaf/client cert itself)
        for (int i = 1; i < chain.ChainElements.Count; i++)
        {
            var issuerCert = chain.ChainElements[i].Certificate;
            if (_allowedIssuerThumbprints.Contains(issuerCert.Thumbprint.ToUpperInvariant()))
                return CertificateValidationResult.Success(certificate.Thumbprint, certificate.Subject);
        }

        return CertificateValidationResult.Fail($"Issuer not trusted. Subject: '{certificate.Subject}', Issuer: '{certificate.Issuer}'");
    }

    /// <summary>Simple bool wrapper for backward compatibility.</summary>
    public bool IsValid(X509Certificate2? certificate) => Validate(certificate).Valid;

    private static HashSet<string> ParseList(string? commaDelimited)
    {
        return (commaDelimited ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => t.ToUpperInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }
}

public sealed record CertificateValidationResult(bool Valid, string? Thumbprint, string? Subject, string? Reason)
{
    public static CertificateValidationResult Success(string thumbprint, string subject)
        => new(true, thumbprint, subject, null);

    public static CertificateValidationResult Fail(string reason)
        => new(false, null, null, reason);
}
