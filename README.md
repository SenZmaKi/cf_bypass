# cf_bypass

A Flutter package that:

1. **Detects** whether a response looks like a CloudFlare-style challenge or block page.
2. **Solves** the challenge in a WebView and return the browser artifacts your own HTTP client needs, such as cookies and user agent.

## Installation

Add this to your `pubspec.yaml`

```yaml
dependencies:
  cf_bypass:
    git:
      url: https://github.com/SenZmaKi/cf_bypass
      ref: main # or specify a commit/tag
```

Then run:

```bash
flutter pub get
```

## Usage

### Detection

Pass the response data from your own HTTP client into `CfDetector`.

```dart
import 'package:cf_bypass/cf_bypass.dart';

final result = CfDetector.detect(
  const CfDetectionRequest(
    url: 'https://example.com/protected',
    statusCode: 403,
    body: '<html><div id="challenge-form"></div></html>',
    headers: {'content-type': 'text/html'},
  ),
);

if (result.isProtected) {
  print(result.kind);               // CfProtectionKind.challenge
  print(result.matchedIndicators);  // ['challenge-form']
  print(result.exception);          // CfProtectedException
}
```

### Solving

Embed `CfWebView` in a full-screen route when you need to solve a challenge.

```dart
import 'package:cf_bypass/cf_bypass.dart';

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CfWebView(
      url: 'https://example.com/protected',
      initialCookies: const [
        CfBrowserCookie(
          name: 'session',
          value: 'abc123',
          domain: 'example.com',
        ),
      ],
      onSuccess: (result) {
        print(result.userAgent);
        print(result.cfClearanceCookie);
        print(result.cookies);
        Navigator.pop(context, result);
      },
      onFailure: (result) {
        print(result.error);
      },
      onError: (error) {
        // Retry only when your app considers this WebView error transient.
        print(error);
        return true;
      },
    ),
  ),
);
```

`onError` is called for main-frame WebView load errors. Return `true` to let
`CfWebView` clear its configured cookie state and reload the original URL, or
return `false` to keep waiting until success, manual retry, cancel, or timeout.

Check [example](https://github.com/SenZmaKi/cf_bypass/tree/main/example) for more details.

## Acknowledgements

This project would not have been possible without [cloudflare_bypass](https://github.com/lkrjangid1/cloudflare_bypass).
