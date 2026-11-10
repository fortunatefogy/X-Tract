class ChallengeHosts {
  ChallengeHosts._();

  static const hosts = <String>{
    'challenges.cloudflare.com',
    'turnstile.cloudflare.com',
    'www.recaptcha.net',
    'recaptcha.net',
    'hcaptcha.com',
    'newassets.hcaptcha.com',
    'js.hcaptcha.com',
    'www.hcaptcha.com',
    'captcha-delivery.com',
    'geo.captcha-delivery.com',
    'checkpoint.facebook.com',
    'challenge.instagram.com',
    'arkoselabs.com',
    'funcaptcha.com',
    'client-api.arkoselabs.com',
  };

  static const pathHints = <String>[
    '/cdn-cgi/challenge-platform/',
    '/cdn-cgi/l/chk_',
    '/recaptcha/',
    '/checkpoint/',
    '/challenge/',
    '/captcha/',
    '/turnstile/',
    '/arkose/',
    '/fc/gc/',
    '/api/v1/challenge',
  ];

  static bool isChallenge(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return false;
    final normalizedHosts = {
      for (final entry in hosts) entry.replaceFirst(RegExp(r'^www\.'), ''),
    };
    if (normalizedHosts.contains(host)) return true;
    if (host.endsWith('.hcaptcha.com') ||
        host.endsWith('.cloudflare.com') ||
        host.endsWith('.arkoselabs.com') ||
        host.endsWith('.funcaptcha.com')) {
      return true;
    }
    final path = uri.path.toLowerCase();
    return pathHints.any(path.contains);
  }

  static bool isChallengeUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    return uri != null && isChallenge(uri);
  }
}
