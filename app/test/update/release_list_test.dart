// 预览版开关: 列表模式只取能取的那一档，坏数据不连坐。
import 'package:dsh_app/update/release.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _release(String tag, {bool prerelease = false, bool draft = false, bool apk = true}) => {
  'tag_name': tag,
  'name': tag,
  'body': '',
  'draft': draft,
  'prerelease': prerelease,
  'assets': apk
      ? [
          {
            'name': 'dsh-go-${tag.startsWith('v') ? tag.substring(1) : tag}-arm64.apk',
            'browser_download_url':
                'https://github.com/gpmlimeng-cyber/dsh-do/releases/download/$tag/dsh-go-${tag.startsWith('v') ? tag.substring(1) : tag}-arm64.apk',
            'size': 1024,
          },
        ]
      : <Object?>[],
  'html_url': 'https://github.com/gpmlimeng-cyber/dsh-do/releases/tag/$tag',
};

void main() {
  test('the newest stable is taken from the list', () {
    final release = parseGithubReleaseList([
      _release('v2.0.1'),
      _release('v2.1.0-rc.1', prerelease: true),
      _release('v2.0.2'),
    ]);
    expect(release, isNotNull);
    expect(release!.version.name, '2.0.2');
  });

  test('previews are taken only when asked for', () {
    final list = [_release('v2.0.2'), _release('v2.1.0-rc.1', prerelease: true)];
    expect(parseGithubReleaseList(list)!.version.name, '2.0.2');
    expect(parseGithubReleaseList(list, allowPrerelease: true)!.version.name, '2.1.0-rc.1');
  });

  test('a broken entry does not fail the list', () {
    final release = parseGithubReleaseList([
      {'tag_name': 'not-a-version'},
      'junk',
      _release('v2.0.3'),
    ]);
    expect(release, isNotNull);
    expect(release!.version.name, '2.0.3');
  });

  test('drafts are skipped', () {
    final release = parseGithubReleaseList([_release('v2.0.9', draft: true), _release('v2.0.4')]);
    expect(release!.version.name, '2.0.4');
  });

  test('a release with no APK asset yet is skipped', () {
    final release = parseGithubReleaseList([_release('v2.0.5', apk: false), _release('v2.0.4')]);
    expect(release!.version.name, '2.0.4');
  });

  test('nothing usable gives null', () {
    expect(parseGithubReleaseList(<Object?>[]), isNull);
    expect(parseGithubReleaseList({'tag_name': 'v2.0.0'}), isNull);
  });
}
