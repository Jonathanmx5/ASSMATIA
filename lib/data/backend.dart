// Abstraction de stockage : documents JSON rangés par collection.
// Deux implémentations : Firestore (synchronisé, partage parents) et
// fichier local (repli si Firebase n'est pas configuré).
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

/// Collections partagées en lecture seule avec les parents.
const kSharedPlannings = 'sharedPlannings';
const kSummaries = 'monthlySummaries';

abstract class NannyBackend {
  bool get supportsSharing;
  Future<Map<String, Map<String, Map<String, dynamic>>>> loadAll();
  Future<void> put(String collection, String id, Map<String, dynamic> data);
  Future<void> delete(String collection, String id);
}

class FirestoreNannyBackend implements NannyBackend {
  final String nannyId;
  final FirebaseFirestore db;
  FirestoreNannyBackend(this.nannyId, this.db);

  @override
  bool get supportsSharing => true;

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> loadAll() async {
    final out = <String, Map<String, Map<String, dynamic>>>{};
    for (final c in [kChildren, kContracts, kLogs, kTaxScales, kSettings]) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        // Synchronisation à l'ouverture ; repli sur le cache hors ligne.
        snap = await db
            .collection(c)
            .where('nannyId', isEqualTo: nannyId)
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        snap = await db
            .collection(c)
            .where('nannyId', isEqualTo: nannyId)
            .get(const GetOptions(source: Source.cache));
      }
      out[c] = {for (final d in snap.docs) d.id: d.data()};
    }
    return out;
  }

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> data) =>
      db.collection(collection).doc(id).set({...data, 'nannyId': nannyId});

  @override
  Future<void> delete(String collection, String id) =>
      db.collection(collection).doc(id).delete();
}

class LocalFileBackend implements NannyBackend {
  Map<String, Map<String, Map<String, dynamic>>> _data = {};
  File? _file;

  @override
  bool get supportsSharing => false;

  Future<File> _f() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/assmatia_local.json');
  }

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>> loadAll() async {
    final f = await _f();
    if (await f.exists()) {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _data = raw.map((k, v) => MapEntry(
          k,
          (v as Map<String, dynamic>)
              .map((id, d) => MapEntry(id, Map<String, dynamic>.from(d)))));
    }
    return _data;
  }

  Future<void> _save() async =>
      (await _f()).writeAsString(jsonEncode(_data));

  @override
  Future<void> put(String collection, String id, Map<String, dynamic> data) {
    (_data[collection] ??= {})[id] = data;
    return _save();
  }

  @override
  Future<void> delete(String collection, String id) {
    _data[collection]?.remove(id);
    return _save();
  }
}

/// Lecture seule côté parent : uniquement les documents partagés dont
/// parentEmails contient l'e-mail du parent connecté.
class ParentReader {
  final FirebaseFirestore db;
  final String email;
  ParentReader(this.db, this.email);

  Future<List<Map<String, dynamic>>> _q(String c) async {
    final q = db.collection(c).where('parentEmails', arrayContains: email);
    QuerySnapshot<Map<String, dynamic>> s;
    try {
      s = await q.get();
    } catch (_) {
      s = await q.get(const GetOptions(source: Source.cache));
    }
    return s.docs.map((d) => d.data()).toList();
  }

  Future<List<Map<String, dynamic>>> plannings() => _q(kSharedPlannings);
  Future<List<Map<String, dynamic>>> summaries() => _q(kSummaries);
}
