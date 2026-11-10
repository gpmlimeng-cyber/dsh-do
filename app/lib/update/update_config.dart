/// Where in-app updates come from. Everything network-facing about updates is
/// configured here; the conventions and trade-offs are in `docs/release.md`.
///
/// Every build asks our own copy of the release files first
/// ([updateDownloadOrigin]: `/update.json`, `/download/<version>/<file>`), then
/// GitHub and the public accelerators, and the rate-limited GitHub API last.
/// Beta builds carry a channel token (`--dart-define=DSH_BETA_CHANNEL_TOKEN`,
/// put in by `tooling/build-apk.sh`): they ask the beta channel before all of
/// that ([UpdateChannel], `go.dshtui.com/beta/update.json`,
/// docs/design/share-links.md) and download from it with the token.
///
/// Build-time overrides (no code change needed):
/// - `--dart-define=DSH_BETA_CHANNEL_ORIGIN=https://example.com` moves the beta
///   channel;
/// - `--dart-define=DSH_UPDATE_MIRROR=https://example.com` moves the copy of
///   the release files (empty string = none);
/// - `--dart-define=DSH_UPDATE_FEED=https://example.com/dsh/update.json`
///   asks another manifest in place of the copy's (empty string = none);
/// - `--dart-define=DSH_UPDATE_MIRRORS=https://a.example/,https://b.example/`
///   replaces the public GitHub accelerator list (empty string = none).
library;

/// GitHub repository the releases live in. This is the MODO fork: builds here
/// update from its releases, not from upstream. `--dart-define=DSH_UPDATE_REPO=owner/name`
/// points a build elsewhere (upstream again, or a test repository).
const updateRepo = String.fromEnvironment('DSH_UPDATE_REPO', defaultValue: 'gpmlimeng-cyber/dsh-do');

/// The upstream project this line is based on. Star links, the community
/// feed and the project link in shared messages keep pointing here even
/// though this build's own updates come from [updateRepo].
const upstreamRepo = 'ccch1mneyyy/dsh-go';

/// The upstream version this line is based on, for 「2.2.0（基于上游 v1.0.15）」.
/// One place only: when upstream moves, this and the version's minor change.
const upstreamBaseline = 'v1.0.15';

/// `releases/latest` of the REST API: tag, notes, assets with sizes and
/// SHA-256 digests. Unauthenticated: 60 requests per hour per IP.
final githubLatestApi = Uri.parse('https://api.github.com/repos/$updateRepo/releases/latest');

/// The newest releases, newest first, when the person asked to see previews
/// too: `releases/latest` never carries a pre-release.
final githubReleasesApi = Uri.parse('https://api.github.com/repos/$updateRepo/releases?per_page=30');

/// The latest release's page, for "open in browser".
final githubReleasesPage = Uri.parse('https://github.com/$updateRepo/releases/latest');

/// A file attached to the latest release. github.com redirects to the asset
/// CDN; not rate limited like the API and reachable through download mirrors.
Uri githubLatestAsset(String name) => Uri.parse('https://github.com/$updateRepo/releases/latest/download/$name');

/// A file attached to the release tagged [tag].
Uri githubReleaseAsset(String tag, String name) =>
    Uri.parse('https://github.com/$updateRepo/releases/download/$tag/$name');

/// The share host (services/share-worker). It serves the beta channel under
/// `/beta/`; public files come from [updateDownloadOrigin].
const updateMirrorOrigin = 'https://go.dshtui.com';

/// Our public copy of the release files (an R2 bucket): `/update.json`, the
/// latest public manifest with absolute asset URLs, and
/// `/download/<version>/<file>` for every file of every release.
const updateDownloadOrigin = 'https://dl.dshtui.com';

/// The beta channel: `<origin>/beta/update.json` and `<origin>/beta/<version>/<file>`,
/// both behind `Authorization: Bearer <token>`. The token is compiled into beta
/// builds; it only ever goes to [origin] over HTTPS, under `/beta/` (dart:io
/// also drops it on a redirect to another origin).
class UpdateChannel {
  UpdateChannel._(this.origin, this.token);

  /// Null when [token] is empty or [origin] isn't an HTTPS origin (plain HTTP
  /// only for a loopback test server).
  static UpdateChannel? tryCreate({required String token, String origin = updateMirrorOrigin}) {
    final t = token.trim();
    final uri = Uri.tryParse(origin.trim().replaceFirst(RegExp(r'/+$'), ''));
    if (t.isEmpty || uri == null || uri.host.isEmpty || (uri.path.isNotEmpty && uri.path != '/')) return null;
    final loopback = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) return null;
    return UpdateChannel._(uri.replace(path: ''), t);
  }

  final Uri origin;
  final String token;

  static const endpointId = 'beta';

  Uri get manifest => origin.replace(path: '/beta/$updateManifestName');

  /// Whether [url] is one of the channel's files, i.e. may carry the token.
  bool covers(Uri url) =>
      url.scheme == origin.scheme &&
      url.host == origin.host &&
      url.port == origin.port &&
      url.path.startsWith('/beta/') &&
      !url.path.contains('/../');

  Map<String, String> get headers => {'authorization': 'Bearer $token'};

  @override
  String toString() => 'UpdateChannel <$origin>';
}

/// A way to reach github.com release files. [prefix] null is GitHub itself;
/// otherwise a "prefix + full URL" accelerator (`https://ghfast.top/https://github.com/…`).
/// With [releases] it is a copy of the release files instead:
/// `…/releases/download/v<version>/<file>` → `<releases><version>/<file>`.
class UpdateMirror {
  const UpdateMirror({required this.id, required this.label, this.prefix, this.releases});

  final String id;

  /// Shown under the download progress ("经由 ghfast.top").
  final String label;
  final String? prefix;

  /// Base URL of a self-hosted copy of tagged release files, ending in `/`.
  final String? releases;

  static const github = UpdateMirror(id: 'github', label: 'GitHub');

  /// The app's own mirror at [origin] (default [updateDownloadOrigin]).
  static UpdateMirror selfHosted([String origin = updateDownloadOrigin]) {
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    return UpdateMirror(id: 'dshgo', label: Uri.tryParse(base)?.host ?? base, releases: '$base/download/');
  }

  /// Rewrites a github.com URL to go through this mirror. URLs on other hosts
  /// (a self-hosted CDN) are not touched: the result is null. A copy of the
  /// release files only has tagged releases' files (not `releases/latest`).
  Uri? rewrite(Uri url) {
    if (url.host != 'github.com') return null;
    if (releases case final base?) {
      final segments = url.pathSegments;
      final repo = updateRepo.split('/');
      final tagged =
          segments.length == 6 &&
          segments[0] == repo[0] &&
          segments[1] == repo[1] &&
          segments[2] == 'releases' &&
          segments[3] == 'download' &&
          segments[4].startsWith('v') &&
          segments[4].length > 1;
      if (!tagged) return null;
      return Uri.parse('$base${Uri.encodeComponent(segments[4].substring(1))}/${Uri.encodeComponent(segments[5])}');
    }
    if (prefix == null) return url;
    return Uri.parse('$prefix$url');
  }
}

/// Public GitHub accelerators, tried in order after our copy and GitHub
/// itself. They come and go (domains change every few months, and some answer
/// 403 to whole networks); everything they serve is checked against the
/// release's SHA-256 and, at install time, against the installed app's
/// signing key.
const publicMirrors = [
  UpdateMirror(id: 'ghfast', label: 'ghfast.top', prefix: 'https://ghfast.top/'),
  UpdateMirror(id: 'gh-proxy', label: 'gh-proxy.com', prefix: 'https://gh-proxy.com/'),
];

const _unset = '\u0000';
const _mirrorDefine = String.fromEnvironment('DSH_UPDATE_MIRROR', defaultValue: updateDownloadOrigin);
const _feedDefine = String.fromEnvironment('DSH_UPDATE_FEED', defaultValue: _unset);
const _mirrorsDefine = String.fromEnvironment('DSH_UPDATE_MIRRORS', defaultValue: _unset);
const _betaTokenDefine = String.fromEnvironment('DSH_BETA_CHANNEL_TOKEN');
const _betaOriginDefine = String.fromEnvironment('DSH_BETA_CHANNEL_ORIGIN', defaultValue: updateMirrorOrigin);

/// The configuration the app ships with (see the library comment for overrides).
UpdateSources defaultUpdateSources({bool includePrerelease = false}) => buildUpdateSources(
  mirror: _mirrorDefine,
  feed: _feedDefine == _unset ? null : _feedDefine,
  accelerators: _mirrorsDefine == _unset ? null : _mirrorsDefine,
  channelToken: _betaTokenDefine,
  channelOrigin: _betaOriginDefine,
  includePrerelease: includePrerelease,
);

/// [defaultUpdateSources] from the defines' values: [mirror] is the origin of
/// a copy of the release files ('' = none); [feed] another manifest to ask
/// (null = the mirror's, '' = none); [accelerators] a comma list replacing
/// [publicMirrors] (null = keep them); [channelToken] turns on the beta
/// channel at [channelOrigin] ('' = off).
UpdateSources buildUpdateSources({
  String mirror = updateDownloadOrigin,
  String? feed,
  String? accelerators,
  String channelToken = '',
  String channelOrigin = updateMirrorOrigin,
  bool includePrerelease = false,
}) {
  final origin = mirror.trim().replaceFirst(RegExp(r'/+$'), '');
  final own = origin.isEmpty ? null : UpdateMirror.selfHosted(origin);
  final public = accelerators == null
      ? publicMirrors
      : [
          for (final (i, prefix) in accelerators.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).indexed)
            UpdateMirror(id: 'custom$i', label: Uri.tryParse(prefix)?.host ?? prefix, prefix: prefix),
        ];
  final feedUrl = feed ?? (origin.isEmpty ? '' : '$origin/$updateManifestName');
  return UpdateSources(
    channel: UpdateChannel.tryCreate(token: channelToken, origin: channelOrigin),
    feed: feedUrl.isEmpty ? null : Uri.tryParse(feedUrl),
    includePrerelease: includePrerelease,
    mirrors: [?own, UpdateMirror.github, ...public],
  );
}

/// How a metadata endpoint answers.
enum EndpointKind {
  /// GitHub REST `releases/latest` JSON.
  githubApi,

  /// GitHub REST `releases` JSON: a list, newest first, pre-releases included.
  githubApiReleases,

  /// An `update.json` manifest (release asset or self-hosted feed).
  manifest,
}

/// One place to ask "what is the latest release?".
class UpdateEndpoint {
  const UpdateEndpoint({
    required this.id,
    required this.kind,
    required this.url,
    required this.mirrorId,
    this.headers = const {},
  });

  /// Stable id, remembered when it works so the next check starts there.
  final String id;
  final EndpointKind kind;
  final Uri url;

  /// Mirror the endpoint goes through; downloads prefer the same one.
  final String? mirrorId;

  /// Sent with the request (the beta channel's token). Never printed.
  final Map<String, String> headers;

  @override
  String toString() => '$id <$url>';
}

/// The ordered list of update sources.
///
/// Metadata: the beta channel (beta builds only; always asked first, since a
/// GitHub release can lag behind it) → our `update.json` → `update.json` on
/// the latest release through each GitHub mirror, GitHub first → GitHub API.
/// Downloads: the asset's own URL (the channel's, with its token, when the
/// channel answered), then each mirror in order, our copy first. Apart from
/// the channel and the API, whatever worked last time moves to the front, so
/// a phone that can't reach one source stops waiting on it every time. The
/// API stays last even then: anonymous calls get 60 an hour per IP, shared
/// IPs often find them spent, and its answer carries no delta patches.
class UpdateSources {
  const UpdateSources({
    this.channel,
    this.feed,
    this.useGithubApi = true,
    this.includePrerelease = false,
    this.mirrors = const [UpdateMirror.github],
  });

  final UpdateChannel? channel;
  final Uri? feed;
  final bool useGithubApi;

  /// Ask the releases list instead of `releases/latest`, so a pre-release can
  /// be picked when the person turned that on.
  final bool includePrerelease;
  final List<UpdateMirror> mirrors;

  /// The same sources with the preview switch flipped (the update state keeps
  /// the person's choice; a test may override the sources as a whole).
  UpdateSources copyWith({bool? includePrerelease}) => UpdateSources(
    channel: channel,
    feed: feed,
    useGithubApi: useGithubApi,
    includePrerelease: includePrerelease ?? this.includePrerelease,
    mirrors: mirrors,
  );

  List<UpdateEndpoint> metadataEndpoints({String? preferred}) {
    final manifests = [
      if (feed case final feed?) UpdateEndpoint(id: 'feed', kind: EndpointKind.manifest, url: feed, mirrorId: null),

      for (final mirror in mirrors)
        if (mirror.rewrite(githubLatestAsset(updateManifestName)) case final url?)
          UpdateEndpoint(id: 'manifest:${mirror.id}', kind: EndpointKind.manifest, url: url, mirrorId: mirror.id),
    ];
    return [
      if (channel case final channel?)
        UpdateEndpoint(
          id: UpdateChannel.endpointId,
          kind: EndpointKind.manifest,
          url: channel.manifest,
          mirrorId: null,
          headers: channel.headers,
        ),
      ..._preferFirst(manifests, (e) => e.id == preferred),
      // 预览版: `releases/latest` never carries a pre-release, so an rc is only
      // visible through the list. Asked first: it is strictly more information.
      if (includePrerelease)
        UpdateEndpoint(
          id: 'api:releases',
          kind: EndpointKind.githubApiReleases,
          url: githubReleasesApi,
          mirrorId: UpdateMirror.github.id,
        ),
      if (useGithubApi)
        UpdateEndpoint(id: 'api', kind: EndpointKind.githubApi, url: githubLatestApi, mirrorId: UpdateMirror.github.id),
    ];
  }

  /// Where to download [urls] from (the asset's own URL first, then any
  /// fallbacks), expanded through the mirrors with [preferredMirror] first.
  /// Non-GitHub URLs are used as they are; the beta channel's carry its token.
  List<DownloadUrl> downloadUrls(List<Uri> urls, {String? preferredMirror}) {
    final ordered = _preferFirst(mirrors, (m) => m.id == preferredMirror);
    final seen = <Uri>{};
    final out = <DownloadUrl>[];
    for (final url in urls) {
      if (url.host != 'github.com') {
        if (seen.add(url)) {
          final channel = this.channel;
          final headers = channel != null && channel.covers(url) ? channel.headers : const <String, String>{};
          out.add(DownloadUrl(url, mirrorId: null, label: url.host, headers: headers));
        }
        continue;
      }
      for (final mirror in ordered) {
        final rewritten = mirror.rewrite(url);
        if (rewritten != null && seen.add(rewritten)) {
          out.add(DownloadUrl(rewritten, mirrorId: mirror.id, label: mirror.label));
        }
      }
    }
    return out;
  }

  static List<T> _preferFirst<T>(List<T> list, bool Function(T) test) {
    final i = list.indexWhere(test);
    if (i <= 0) return List.of(list);
    return [list[i], ...list.sublist(0, i), ...list.sublist(i + 1)];
  }
}

/// One candidate URL for a file download.
class DownloadUrl {
  const DownloadUrl(this.url, {required this.mirrorId, required this.label, this.headers = const {}});

  final Uri url;
  final String? mirrorId;
  final String label;

  /// Sent with every request for it (the beta channel's token). Never printed.
  final Map<String, String> headers;

  @override
  String toString() => url.toString();
}

/// Release asset names (docs/release.md).
const updateManifestName = 'update.json';
const checksumsName = 'SHA256SUMS';
