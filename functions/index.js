/* eslint-disable */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Jeżeli chcesz region EU, odkomentuj i użyj 'europe-central2':
// const r = functions.region('europe-central2');
const r = functions; // domyślne us-central1

async function assertIsAdmin(uid) {
  if (!uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Brak uwierzytelnienia.');
  }
  const snap = await db.collection('users').doc(uid).get();
  const role = snap.exists ? snap.data().role : null;
  if (role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Tylko admin może to zrobić.');
  }
}

exports.adminSetPassword = r.https.onCall(async (data, context) => {
  const callerUid = context.auth ? context.auth.uid : null; // ← zamiast context.auth?.uid
  await assertIsAdmin(callerUid);

  const targetUid = data && data.uid;
  const newPassword = data && data.password;

  if (!targetUid || !newPassword || String(newPassword).length < 6) {
    throw new functions.https.HttpsError('invalid-argument', 'Podaj uid i hasło (min 6 znaków).');
  }

  await admin.auth().updateUser(targetUid, { password: newPassword });
  return { ok: true };
});

exports.adminDeleteUser = r.https.onCall(async (data, context) => {
  const callerUid = context.auth ? context.auth.uid : null; // ← zamiast context.auth?.uid
  await assertIsAdmin(callerUid);

  const targetUid = data && data.uid;
  if (!targetUid) {
    throw new functions.https.HttpsError('invalid-argument', 'Brak uid.');
  }

  // 1) Usuń konto z Auth
  await admin.auth().deleteUser(targetUid).catch((e) => {
    if (e.code !== 'auth/user-not-found') throw e;
  });

  // 2) Usuń dokument w 'users'
  await db.collection('users').doc(targetUid).delete().catch(() => {});

  // 3) Sprzątanie w powiązanych kolekcjach
  const batch = db.batch();

  const scansQ = await db.collection('scans').where('userId', '==', targetUid).get();
  scansQ.forEach(doc => batch.delete(doc.ref));

  const uep1 = await db.collection('user_exhibitor_points').where('userId', '==', targetUid).get();
  uep1.forEach(doc => batch.delete(doc.ref));

  const uep2 = await db.collection('user_exhibitor_points').where('exhibitorId', '==', targetUid).get();
  uep2.forEach(doc => batch.delete(doc.ref));

  await batch.commit();

  return { ok: true };
});
