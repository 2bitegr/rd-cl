/// Selects the pre-v2 compatibility path only for an actual HTTP 404.
/// Authentication, server, and decoding errors must propagate instead of
/// masquerading as an older Office API.
T? decodeExantasOptional404<T>(int statusCode, T Function() decode) {
  if (statusCode == 404) return null;
  return decode();
}
