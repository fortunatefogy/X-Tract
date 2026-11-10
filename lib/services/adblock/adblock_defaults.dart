/// Filter sources and built-in rules modelled on the defaults shipped by
/// Brave and Helium (uBlock Origin / EasyList / EasyPrivacy).
class AdblockDefaults {
  AdblockDefaults._();

  static const recommendedListUrls = <String>[
    'https://abp.oisd.nl/',
    'https://easylist.to/easylist/easylist.txt',
    'https://easylist.to/easylist/easyprivacy.txt',
    'https://filters.adtidy.org/extension/chromium/filters/4.txt',
    'https://filters.adtidy.org/extension/chromium/filters/2.txt',
    'https://filters.adtidy.org/extension/chromium/filters/3.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt',
  ];

  static const legacyRecommendedListUrls = <String>[
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/resource-abuse.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt',
    'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt',
    'https://easylist.to/easylist/easylist.txt',
    'https://easylist.to/easylist/easyprivacy.txt',
    'https://filters.adtidy.org/extension/ublock/filters/2_without_easylist.txt',
    'https://filters.adtidy.org/extension/ublock/filters/3.txt',
    'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext',
  ];

  static bool matchesLegacyDefaults(List<String> urls) {
    if (urls.length != legacyRecommendedListUrls.length) return false;
    for (var index = 0; index < urls.length; index++) {
      if (urls[index] != legacyRecommendedListUrls[index]) return false;
    }
    return true;
  }

  static String labelFor(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('oisd')) return 'OISD Privacy';
    if (lower.contains('easylist') && !lower.contains('easyprivacy')) {
      return 'EasyList';
    }
    if (lower.contains('easyprivacy')) return 'EasyPrivacy';
    if (lower.contains('adbanner') ||
        lower.contains('/2.txt') ||
        lower.contains('2_without_easylist')) {
      return 'AdGuard Base';
    }
    if (lower.contains('/3.txt')) return 'AdGuard Tracking Protection';
    if (lower.contains('/4.txt')) return 'AdGuard Social Media';
    if (lower.contains('/filters/filters.txt')) return 'uBlock filters';
    if (lower.contains('unbreak')) return 'uBlock Unbreak';
    if (lower.contains('privacy.txt')) return 'uBlock Privacy';
    if (lower.contains('badware')) return 'uBlock Badware';
    if (lower.contains('resource-abuse')) return 'uBlock Resource Abuse';
    if (lower.contains('quick-fixes')) return 'uBlock Quick Fixes';
    if (lower.contains('pgl.yoyo')) return "Peter Lowe's List";
    final host = Uri.tryParse(url)?.host ?? url;
    return host.isEmpty ? url : host;
  }

  static const builtInOisdAsset = 'assets/adblock/oisd_small.txt';

  static const seedHosts = <String>{
    '2mdn.net',
    '4dsply.com',
    'ad-delivery.net',
    'adform.net',
    'adition.com',
    'adnxs.com',
    'adroll.com',
    'ads-twitter.com',
    'adsafeprotected.com',
    'adsrvr.org',
    'adsterra.com',
    'advertising.com',
    'adzerk.net',
    'agkn.com',
    'amazon-adsystem.com',
    'amplitude.com',
    'aniview.com',
    'applovin.com',
    'appnexus.com',
    'atdmt.com',
    'bat.bing.com',
    'bidswitch.net',
    'bluekai.com',
    'branch.io',
    'casalemedia.com',
    'chartbeat.com',
    'criteo.com',
    'criteo.net',
    'doubleclick.net',
    'demdex.net',
    'exoclick.com',
    'facebook.net',
    'gemius.pl',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'hotjar.com',
    'inmobi.com',
    'juicyads.com',
    'krxd.net',
    'lijit.com',
    'liadm.com',
    'media.net',
    'mgid.com',
    'mixpanel.com',
    'mopub.com',
    'moatads.com',
    'mookie1.com',
    'newrelic.com',
    'omtrdc.net',
    'onclickads.net',
    'openx.net',
    'outbrain.com',
    'permutive.com',
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'pubmatic.com',
    'quantserve.com',
    'revcontent.com',
    'rlcdn.com',
    'rubiconproject.com',
    'scorecardresearch.com',
    'segment.com',
    'segment.io',
    'serving-sys.com',
    'sharethrough.com',
    'smartadserver.com',
    'spotxchange.com',
    'taboola.com',
    'teads.tv',
    'trafficjunky.com',
    'tribalfusion.com',
    'turn.com',
    'unityads.unity3d.com',
    'vungle.com',
    'yieldmo.com',
    'zedo.com',
  };

  static const seedRules = <String>[
    '/ads/',
    '/adserver/',
    '/advert/',
    '/banners/',
    '/pagead/',
    '/ad_sense/',
    '/adframe',
    '/popunder/',
    'doubleclick',
    'googlesyndication',
    'prebid',
  ];

  static const seedCosmeticSelectors = <String>[
    '.ad',
    '.ads',
    '.ad-banner',
    '.ad-container',
    '.ad-slot',
    '.ad-wrapper',
    '.advert',
    '.advertisement',
    '.adsbygoogle',
    '.ad-container',
    '.banner-ad',
    '.dfp-ad',
    '.google-ad',
    '.sponsored',
    '.sponsor',
    '[id^="ad-"]',
    '[id^="ads-"]',
    '[id^="div-gpt-ad"]',
    '[id^="google_ads"]',
    '[class^="ad-"]',
    '[class^="ads-"]',
    '[class*=" ad-"]',
    '[class*=" ads-"]',
    '[class*="-ad-"]',
    '[class*="-ads-"]',
    '[class*="advert"]',
    '[class*="banner-ad"]',
    '[class*="sponsor"]',
    '[aria-label="advertisement"]',
    '[data-ad]',
    '[data-ad-slot]',
    '[data-ad-unit]',
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication.com"]',
    'iframe[src*="googleadservices.com"]',
    'iframe[src*="amazon-adsystem.com"]',
    'ins.adsbygoogle',
  ];
}
