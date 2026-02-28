class TotpMeta {
  final String? issuer;
  final String? label;
  final int digits;
  final int period;
  final String algorithm;

  const TotpMeta({
    this.issuer,
    this.label,
    this.digits = 6,
    this.period = 30,
    this.algorithm = "SHA1",
  });

  Map<String, dynamic> toJson() => {
        'issuer': issuer,
        'label': label,
        'digits': digits,
        'period': period,
        'algorithm': algorithm,
      };

  static TotpMeta fromJson(Map<String, dynamic> json) => TotpMeta(
        issuer: json['issuer'] as String?,
        label: json['label'] as String?,
        digits: (json['digits'] is int) ? json['digits'] as int : int.tryParse('${json['digits']}') ?? 6,
        period: (json['period'] is int) ? json['period'] as int : int.tryParse('${json['period']}') ?? 30,
        algorithm: (json['algorithm'] as String?)?.toUpperCase() ?? "SHA1",
      );
}

class TotpParsed {
  final String secret; // base32
  final TotpMeta meta;
  TotpParsed({required this.secret, required this.meta});
}

TotpParsed? parseOtpauthUri(String raw) {
  if (!raw.startsWith('otpauth://')) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;

  final secret = uri.queryParameters['secret'];
  if (secret == null || secret.isEmpty) return null;

  final issuerQ = uri.queryParameters['issuer'];
  final algoQ = uri.queryParameters['algorithm']?.toUpperCase();
  final digitsQ = int.tryParse(uri.queryParameters['digits'] ?? '');
  final periodQ = int.tryParse(uri.queryParameters['period'] ?? '');

  final label = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;

  final meta = TotpMeta(
    issuer: issuerQ,
    label: label,
    digits: digitsQ ?? 6,
    period: periodQ ?? 30,
    algorithm: (algoQ == "SHA256" || algoQ == "SHA512" || algoQ == "SHA1") ? algoQ! : "SHA1",
  );

  return TotpParsed(secret: secret, meta: meta);
}
