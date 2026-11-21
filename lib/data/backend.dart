// Abstraction de stockage : documents JSON rangés par collection.
// Deux implémentations : Firestore (synchronisé, partage parents) et
// fichier local (repli si Firebase n'est pas configuré).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

/// Collections privées de l'assistante maternelle.
const kChildren = 'children';
const kContracts = 'contracts';
const kLogs = 'dailyLogs';
const kTaxScales = 'taxScales';
const kSettings = 'settings';
const kLeaves = 'leavePeriods';
const kLocked = 'lockedSummaries';
const kPrivateCollections = [kChildren, kContracts, kLogs, kTaxScales, kSettings, kLeaves, kLocked];

/// Collections partagées en lecture seule avec les parents.
const kSharedPlannings = 'sharedPlannings';
const kSummaries = 'monthlySummaries';

typedef Data = Map<String, Map<String, Map<String, dynamic>>>;

/// Écriture groupée : data == null => suppression.
class WriteOp {
  final String collection;
  final String id;
  final Map<String, dynamic>? data;
  const WriteOp(this.collection, this.id, this.data);
}

abstract class NannyBackend {
  bool get supportsSharing;
  /// Appelé quand une écriture échoue (les écritures ne bloquent pas l'UI).
  void Function(Object error)? onError;
  Future<Data> loadAll();
  /// N'attend pas la confirmation serveur : hors ligne, l'écriture est
  /// conservée dans le cache et synchronisée au retour du réseau.
  void write(List<WriteOp> ops);
  /// Identifiants des documents d'une collection pour lesquels field == value.
  Future<List<String>> idsWhere(String collection, String field, Object value);
}

class FirestoreNannyBackend implements NannyBackend {
  final String nannyId;
  final FirebaseFirestore db;
  @override
  void Function(Object error)? onError;
  FirestoreNannyBackend(this.nannyId, this.db);

  @override
  bool get supportsSharing => true;

  Query<Map<String, dynamic>> _mine(String c) => db.collection(c).where('nannyId', isEqualTo: nannyId);

  Future<QuerySnapshot<Map<String, dynamic>>> _get(Query<Map<String, dynamic>> q) async {
    try {
      // Synchronisation à l'ouverture ; repli sur le cache hors ligne.
      return await q.get().timeout(const Duration(seconds: 10));
    } catch (_) {
      return q.get(const GetOptions(source: Source.cache));
    }
  }

  @override
  Future<Data> loadAll() async {
    final out = <String, Map<String, Map<String, dynamic>>>{};
    await Future.wait(kPrivateCollections.map((c) async {
      final snap = await _get(_mine(c));
      out[c] = {for (final d in snap.docs) d.id: d.data()};
    }));
    return out;
  }

  @override
  void write(List<WriteOp> ops) {
    // Lots de 450 opérations maximum (limite Firestore : 500).
    for (var i = 0; i < ops.length; i += 450) {
      final batch = db.batch();
      for (final op in ops.skip(i).take(450)) {
        final ref = db.collection(op.collection).doc(op.id);
        if (op.data == null) {
          batch.delete(ref);
        } else {
          batch.set(ref, {...op.data!, 'nannyId': nannyId});
        }
      }
      unawaited(batch.commit().catchError((Object e) => onError?.call(e)));
    }
  }

  @override
  Future<List<String>> idsWhere(String collection, String field, Object value) async {
    final s = await _get(_mine(collection).where(field, isEqualTo: value));
    return s.docs.map((d) => d.id).toList();
  }
}

class LocalFileBackend implements NannyBackend {
  Data _data = {};
  File? _file;
  @override
  void Function(Object error)? onError;

  @override
  bool get supportsSharing => false;

  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/assmatia_local.json');
  }

  /// Données d'un éventuel usage en mode local (pour migration vers le cloud).
  static Future<Data?> readExisting() async {
    final f = await file();
    if (!await f.exists()) return null;
    final d = decode(await f.readAsString());
    return (d[kChildren]?.isEmpty ?? true) ? null : d;
  }

  static Data decode(String s) {
    final raw = jsonDecode(s) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(
        k, (v as Map<String, dynamic>).map((id, d) => MapEntry(id, Map<String, dynamic>.from(d)))));
  }

  @override
  Future<Data> loadAll() async {
    final f = _file ??= await file();
    if (await f.exists()) _data = decode(await f.readAsString());
    return _data;
  }

  @override
  void write(List<WriteOp> ops) {
    for (final op in ops) {
      if (op.data == null) {
        _data[op.collection]?.remove(op.id);
      } else {
        (_data[op.collection] ??= {})[op.id] = op.data!;
      }
    }
    unawaited(() async {
      try {
        await (_file ??= await file()).writeAsString(jsonEncode(_data));
      } catch (e) {
        onError?.call(e);
      }
    }());
  }

  @override
  Future<List<String>> idsWhere(String collection, String field, Object value) async =>
      [for (final e in (_data[collection] ?? {}).entries) if (e.value[field] == value) e.key];
}

/// Lecture seule côté parent : uniquement les documents partagés dont
/// parentEmails contient l'e-mail (vérifié) du parent connecté.
class ParentReader {
  final FirebaseFirestore db;
  final String email;
  ParentReader(this.db, this.email);

  Future<List<Map<String, dynamic>>> _q(String c) async {
    final q = db.collection(c).where('parentEmails', arrayContains: email);
    QuerySnapshot<Map<String, dynamic>> s;
    try {
      s = await q.get().timeout(const Duration(seconds: 10));
    } catch (_) {
      s = await q.get(const GetOptions(source: Source.cache));
    }
    return s.docs.map((d) => d.data()).toList();
  }

  Future<List<Map<String, dynamic>>> plannings() => _q(kSharedPlannings);
  Future<List<Map<String, dynamic>>> summaries() => _q(kSummaries);
}
