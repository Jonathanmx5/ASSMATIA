// Mise à jour de l'application hors Play Store : un manifeste JSON publié sur
// Firebase Hosting décrit la dernière version ; l'APK est téléchargé puis
// l'installateur Android est ouvert (l'utilisateur confirme l'installation).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const kUpdateManifestUrl = 'https://assmatia-38810.web.app/update/latest.json';

class UpdateInfo {
  final String version;
  final int build;
  final String apkUrl;
  final String notes;
  const UpdateInfo(this.version, this.build, this.apkUrl, this.notes);
  factory UpdateInfo.fromJson(Map<String, dynamic> j, Uri base) => UpdateInfo(
        j['version'] as String,
        (j['build'] as num).toInt(),
        base.resolve(j['apk'] as String).toString(),
        (j['notes'] ?? '') as String,
      );
}

enum UpdateState { idle, checking, upToDate, available, downloading, error }

class Updater extends ChangeNotifier {
  Updater._();
  static final instance = Updater._();

  UpdateState state = UpdateState.idle;
  String currentVersion = '';
  int currentBuild = 0;
  UpdateInfo? latest;
  double progress = 0;
  String? message;

  bool get hasUpdate => latest != null && latest!.build > currentBuild;

  void _set(UpdateState s, [String? msg]) {
    state = s;
    message = msg;
    notifyListeners();
  }

  /// Vérifie silencieusement (au démarrage) ou à la demande.
  Future<void> check() async {
    if (state == UpdateState.checking || state == UpdateState.downloading) return;
    _set(UpdateState.checking);
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
      currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('$kUpdateManifestUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await (await c.getUrl(uri)).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      c.close();
      latest = UpdateInfo.fromJson(jsonDecode(body) as Map<String, dynamic>, uri);
      _set(hasUpdate ? UpdateState.available : UpdateState.upToDate);
    } catch (e) {
      _set(UpdateState.error, 'Vérification impossible : $e');
    }
  }

  /// Télécharge l'APK puis ouvre l'installateur Android.
  Future<void> install() async {
    final u = latest;
    if (u == null) return;
    _set(UpdateState.downloading);
    progress = 0;
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/assmatia-${u.version}.apk');
      final c = HttpClient();
      final res = await (await c.getUrl(Uri.parse(u.apkUrl))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = f.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      c.close();
      final r = await OpenFilex.open(f.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) throw Exception(r.message);
      _set(UpdateState.available, "Confirmez l'installation dans la fenêtre Android.");
    } catch (e) {
      _set(UpdateState.error, 'Téléchargement impossible : $e');
    }
  }
}
