// Which innertube client, with today's identifiers, produces an audio URL that
// googlevideo will serve in full?
//
// `youtube_explode_dart` 3.1.0 ships client versions from 2025 and asks for
// them in a way YouTube now answers with bot walls, so the clients are worth
// re-testing against the identifiers yt-dlp uses today (July 2026).
//
//   dart run tool/client_matrix.dart <videoId|"search query">
import 'dart:convert';
import 'dart:io';

import 'package:gandar/data/youtube/stream_health.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

String _stamp() {
  final now = DateTime.now();
  return '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

void log(String message) => stdout.writeln('${_stamp()} $message');

const _safariUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)';
const _cobaltUa =
    'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold '
    '(unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)';
const _key = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

/// One entry per client worth trying: the numbers YouTube expects in the
/// X-Youtube-Client-* headers, and the client context it expects in the body.
class ClientSpec {
  const ClientSpec({
    required this.label,
    required this.number,
    required this.client,
    this.contextExtras = const {},
    this.embedded = false,
  });
  final String label;
  final String number;
  final Map<String, dynamic> client;
  final Map<String, dynamic> contextExtras;
  final bool embedded;
}

final _specs = <ClientSpec>[
  ClientSpec(
    label: 'VISIONOS 1.02 (id 101)',
    number: '101',
    client: {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
      'osName': 'visionOS',
      'osVersion': '2.0.0.21O209',
      'userAgent': _safariUa,
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
    },
  ),
  ClientSpec(
    label: 'TVHTML5 7.20260707 (id 7)',
    number: '7',
    client: {
      'clientName': 'TVHTML5',
      'clientVersion': '7.20260707.07.00',
      'deviceMake': '',
      'deviceModel': '',
      'userAgent': _cobaltUa,
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
      'originalUrl': 'https://www.youtube.com/tv',
      'theme': 'CLASSIC',
      'platform': 'DESKTOP',
      'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
    },
    contextExtras: {
      'user': {'lockedSafetyMode': false},
      'request': {
        'useSsl': true,
        'internalExperimentFlags': <Object>[],
      },
    },
  ),
  ClientSpec(
    label: 'TVHTML5 Tizen 5.20260707 (id 7, tv_samsung)',
    number: '7',
    client: {
      'clientName': 'TVHTML5',
      'clientVersion': '5.20260707',
      'deviceMake': 'Samsung',
      'deviceModel': 'SmartTV',
      'osName': 'Tizen',
      'osVersion': '2.4.0',
      'userAgent':
          'Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 '
          '(KHTML, like Gecko) Version/2.4.0 TV Safari/538.1',
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
      'originalUrl': 'https://www.youtube.com/tv',
      'theme': 'CLASSIC',
      'platform': 'TV',
      'clientFormFactor': 'TV_UNKNOWN_FORM_FACTOR',
    },
    contextExtras: {
      'user': {'lockedSafetyMode': false},
      'request': {'useSsl': true},
    },
  ),
  ClientSpec(
    label: 'TVHTML5_SIMPLY 1.0 (id 75)',
    number: '75',
    client: {
      'clientName': 'TVHTML5_SIMPLY',
      'clientVersion': '1.0',
      'userAgent': _cobaltUa,
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
    },
    embedded: true,
  ),
  ClientSpec(
    label: 'WEB_EMBEDDED_PLAYER 2.20260708 (id 56)',
    number: '56',
    client: {
      'clientName': 'WEB_EMBEDDED_PLAYER',
      'clientVersion': '2.20260708.00.00',
      'userAgent': _safariUa,
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
    },
    embedded: true,
  ),
  ClientSpec(
    label: 'MWEB 2.20260708 (id 2)',
    number: '2',
    client: {
      'clientName': 'MWEB',
      'clientVersion': '2.20260708.05.00',
      'userAgent':
          'Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)',
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
    },
  ),
  ClientSpec(
    label: 'IOS 21.26.4 (id 5)',
    number: '5',
    client: {
      'clientName': 'IOS',
      'clientVersion': '21.26.4',
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iOS',
      'osVersion': '18.3.2.22D82',
      'userAgent':
          'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 '
          'like Mac OS X;)',
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'utcOffsetMinutes': 0,
    },
  ),
  ClientSpec(
    label: 'ANDROID 21.26.364 (id 3)',
    number: '3',
    client: {
      'clientName': 'ANDROID',
      'clientVersion': '21.26.364',
      'androidSdkVersion': 30,
      'userAgent': 'com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip',
      'hl': 'en',
      'timeZone': 'UTC',
      'gl': 'US',
      'osName': 'Android',
      'osVersion': '11',
      'utcOffsetMinutes': 0,
    },
  ),
];

class WatchContext {
  WatchContext(this.visitorData, this.signatureTimestamp, this.cookie);
  final String visitorData;
  final String signatureTimestamp;
  final String cookie;
}

Future<WatchContext?> _watchContext(String videoId) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('https://www.youtube.com/watch?v=$videoId'),
    );
    request.headers.set(HttpHeaders.userAgentHeader, _safariUa);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final cookies = <String>[
      for (final raw
          in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[])
        raw.split(';').first,
    ];
    final visitor = RegExp(r'"visitorData":"([^"]+)"').firstMatch(body);
    final sts = RegExp(r'"STS":(\d+)').firstMatch(body);
    if (visitor == null) return null;
    return WatchContext(
      Uri.decodeComponent(visitor.group(1)!),
      sts?.group(1) ?? '',
      cookies.join('; '),
    );
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> _probe(String url) async {
  // The verdict the app itself acts on, so this probe measures the real
  // classifier against the real CDN rather than a copy of the idea.
  log('    health: ${await const StreamHealth().check(url)}');
  for (final range in <String?>[null, 'bytes=0-1023', 'bytes=0-4194303']) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      await response.drain<void>();
      log('    ${range ?? '(no range)'}: ${response.statusCode}');
    } catch (e) {
      log('    ${range ?? '(no range)'}: ERR ${e.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }
}

Future<void> main(List<String> args) async {
  final target = args.join(' ').trim();
  final yt = YoutubeExplode();
  String videoId;
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(target)) {
    videoId = target;
  } else {
    final results = await yt.search.search(target);
    videoId = results.first.id.value;
    log('search "$target" -> $videoId "${results.first.title}"');
  }
  yt.close();

  final watch = await _watchContext(videoId);
  log('watch context: visitorData=${watch?.visitorData.length ?? 0} chars '
      'sts=${watch?.signatureTimestamp}');

  for (final spec in _specs) {
    final context = <String, dynamic>{
      'client': spec.client,
      ...spec.contextExtras,
    };
    if (spec.embedded) {
      context['thirdParty'] = {
        'embedUrl': 'https://www.youtube.com/embed/$videoId',
      };
    }
    final body = <String, dynamic>{
      'context': context,
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      if (watch != null && watch.signatureTimestamp.isNotEmpty)
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'signatureTimestamp':
                int.tryParse(watch.signatureTimestamp) ?? 0,
          },
        },
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Origin': 'https://www.youtube.com',
      'X-Youtube-Client-Name': spec.number,
      'X-Youtube-Client-Version': '${spec.client['clientVersion']}',
      if (spec.client['userAgent'] is String)
        'User-Agent': '${spec.client['userAgent']}',
      if (watch != null) ...{
        'X-Goog-Visitor-Id': watch.visitorData,
        'Cookie': watch.cookie,
      },
    };

    String text;
    try {
      final http = HttpClient();
      final request = await http.postUrl(
        Uri.parse(
          'https://www.youtube.com/youtubei/v1/player?prettyPrint=false'
          '&key=$_key',
        ),
      );
      headers.forEach((k, v) => request.headers.set(k, v));
      request.write(json.encode(body));
      final response = await request.close();
      text = await response.transform(utf8.decoder).join();
      http.close(force: true);
    } catch (e) {
      log('${spec.label}: FAILED ${e.runtimeType}');
      continue;
    }

    Map<String, dynamic> decoded;
    try {
      decoded = json.decode(text) as Map<String, dynamic>;
    } catch (_) {
      log('${spec.label}: not JSON (${text.length} chars)');
      continue;
    }
    final playability = decoded['playabilityStatus'] as Map<String, dynamic>?;
    final streaming = decoded['streamingData'] as Map<String, dynamic>?;
    final formats = <dynamic>[
      ...?streaming?['adaptiveFormats'] as List<dynamic>?,
      ...?streaming?['formats'] as List<dynamic>?,
    ];
    log(
      '${spec.label}: ${playability?['status']} '
      '"${playability?['reason'] ?? ''}" formats=${formats.length} '
      'hls=${(decoded['streamingData'] as Map<String, dynamic>?)?['hlsManifestUrl'] != null}',
    );

    Map<String, dynamic>? best;
    var bestBitrate = -1;
    for (final raw in formats) {
      final f = raw as Map<String, dynamic>;
      if (!(f['mimeType'] as String? ?? '').startsWith('audio/')) continue;
      final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
      if (bitrate > bestBitrate) {
        bestBitrate = bitrate;
        best = f;
      }
    }
    final url = best?['url'] as String?;
    if (url == null) {
      log('  no direct audio url');
      continue;
    }
    final q = Uri.parse(url).queryParameters;
    log(
      '  itag=${best!['itag']} c=${q['c']} n=${q['n'] == null ? '-' : 'present'} '
      'pot=${q['pot'] == null ? '-' : 'present'} clen=${q['clen']}',
    );
    await _probe(url);
  }
}
