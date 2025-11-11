import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2/options";

admin.initializeApp();
// Wybierz region blisko PL. Jeśli masz inny region projektu – zmień tutaj.
setGlobalOptions({ region: "europe-west1", maxInstances: 5 });

/** Sprawdza czy wywołujący ma rolę admin w kolekcji /users/{uid}. */
async function assertAdmin(callerUid?: string) {
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Musisz być zalogowany.");
  }
  const snap = await admin.firestore().doc(`users/${callerUid}`).get();
  const role = snap.get("role");
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Tylko admin może to zrobić.");
  }
}

/** Pomocniczo: usuwa wszystkie dokumenty pasujące do zapytania partiami. */
async function deleteByQuery(query: FirebaseFirestore.Query, chunk = 400) {
  while (true) {
    const qs = await query.limit(chunk).get();
    if (qs.empty) break;
    const batch = admin.firestore().batch();
    qs.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (qs.size < chunk) break;
  }
}

/** ADMIN: ustaw hasło użytkownikowi. */
export const adminSetPassword = onCall(
  async (request) => {
    await assertAdmin(request.auth?.uid);

    const uid = request.data?.uid as string | undefined;
    const newPassword = request.data?.newPassword as string | undefined;

    if (!uid || !newPassword) {
      throw new HttpsError("invalid-argument", "Wymagane pola: uid, newPassword.");
    }
    if (newPassword.length < 6) {
      throw new HttpsError("invalid-argument", "Hasło musi mieć min. 6 znaków.");
    }

    await admin.auth().updateUser(uid, { password: newPassword });
    return { ok: true };
  }
);

/** ADMIN: wyłącz/włącz konto w Firebase Auth (twarda blokada logowania). */
export const adminDisableUser = onCall(
  async (request) => {
    await assertAdmin(request.auth?.uid);

    const uid = request.data?.uid as string | undefined;
    const disabled = request.data?.disabled as boolean | undefined;

    if (!uid || typeof disabled !== "boolean") {
      throw new HttpsError("invalid-argument", "Wymagane: uid, disabled:boolean.");
    }

    await admin.auth().updateUser(uid, { disabled });
    // (opcjonalnie) lustrzane pole w Firestore – by było widać w UI
    await admin.firestore().doc(`users/${uid}`).set({ disabled }, { merge: true });

    return { ok: true };
  }
);

/** ADMIN: ustaw rolę (user/exhibitor/admin) w Firestore. */
export const adminSetRole = onCall(
  async (request) => {
    await assertAdmin(request.auth?.uid);

    const uid = request.data?.uid as string | undefined;
    const role = request.data?.role as string | undefined;
    if (!uid || !role || !["user", "exhibitor", "admin"].includes(role)) {
      throw new HttpsError("invalid-argument", "Wymagane pola: uid, rola ∈ {user, exhibitor, admin}.");
    }

    await admin.firestore().doc(`users/${uid}`).set({ role }, { merge: true });
    return { ok: true };
  }
);

/** ADMIN: usuń konto użytkownika + jego dane w Firestore. */
export const adminDeleteUser = onCall(
  async (request) => {
    await assertAdmin(request.auth?.uid);

    const uid = request.data?.uid as string | undefined;
    if (!uid) {
      throw new HttpsError("invalid-argument", "Wymagane pole: uid.");
    }

    // 1) Usuń dane z Firestore
    const db = admin.firestore();
    await db.doc(`users/${uid}`).delete().catch(() => {});

    await deleteByQuery(db.collection("scans").where("userId", "==", uid));
    await deleteByQuery(db.collection("user_exhibitor_points").where("userId", "==", uid));
    await deleteByQuery(db.collection("user_exhibitor_points").where("exhibitorId", "==", uid));

    // 2) Usuń konto z Firebase Auth
    await admin.auth().deleteUser(uid).catch((e) => {
      // Jeśli konto już nie istnieje – ignoruj NOT_FOUND
      if (e?.errorInfo?.code !== "auth/user-not-found") throw e;
    });

    return { ok: true };
  }
);
