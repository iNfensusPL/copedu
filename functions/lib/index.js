"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminDeleteUser = exports.adminSetRole = exports.adminDisableUser = exports.adminSetPassword = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const options_1 = require("firebase-functions/v2/options");
admin.initializeApp();
// Wybierz region blisko PL. Jeśli masz inny region projektu – zmień tutaj.
(0, options_1.setGlobalOptions)({ region: "europe-west1", maxInstances: 5 });
/** Sprawdza czy wywołujący ma rolę admin w kolekcji /users/{uid}. */
async function assertAdmin(callerUid) {
    if (!callerUid) {
        throw new https_1.HttpsError("unauthenticated", "Musisz być zalogowany.");
    }
    const snap = await admin.firestore().doc(`users/${callerUid}`).get();
    const role = snap.get("role");
    if (role !== "admin") {
        throw new https_1.HttpsError("permission-denied", "Tylko admin może to zrobić.");
    }
}
/** Pomocniczo: usuwa wszystkie dokumenty pasujące do zapytania partiami. */
async function deleteByQuery(query, chunk = 400) {
    while (true) {
        const qs = await query.limit(chunk).get();
        if (qs.empty)
            break;
        const batch = admin.firestore().batch();
        qs.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (qs.size < chunk)
            break;
    }
}
/** ADMIN: ustaw hasło użytkownikowi. */
exports.adminSetPassword = (0, https_1.onCall)(async (request) => {
    await assertAdmin(request.auth?.uid);
    const uid = request.data?.uid;
    const newPassword = request.data?.newPassword;
    if (!uid || !newPassword) {
        throw new https_1.HttpsError("invalid-argument", "Wymagane pola: uid, newPassword.");
    }
    if (newPassword.length < 6) {
        throw new https_1.HttpsError("invalid-argument", "Hasło musi mieć min. 6 znaków.");
    }
    await admin.auth().updateUser(uid, { password: newPassword });
    return { ok: true };
});
/** ADMIN: wyłącz/włącz konto w Firebase Auth (twarda blokada logowania). */
exports.adminDisableUser = (0, https_1.onCall)(async (request) => {
    await assertAdmin(request.auth?.uid);
    const uid = request.data?.uid;
    const disabled = request.data?.disabled;
    if (!uid || typeof disabled !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "Wymagane: uid, disabled:boolean.");
    }
    await admin.auth().updateUser(uid, { disabled });
    // (opcjonalnie) lustrzane pole w Firestore – by było widać w UI
    await admin.firestore().doc(`users/${uid}`).set({ disabled }, { merge: true });
    return { ok: true };
});
/** ADMIN: ustaw rolę (user/exhibitor/admin) w Firestore. */
exports.adminSetRole = (0, https_1.onCall)(async (request) => {
    await assertAdmin(request.auth?.uid);
    const uid = request.data?.uid;
    const role = request.data?.role;
    if (!uid || !role || !["user", "exhibitor", "admin"].includes(role)) {
        throw new https_1.HttpsError("invalid-argument", "Wymagane pola: uid, rola ∈ {user, exhibitor, admin}.");
    }
    await admin.firestore().doc(`users/${uid}`).set({ role }, { merge: true });
    return { ok: true };
});
/** ADMIN: usuń konto użytkownika + jego dane w Firestore. */
exports.adminDeleteUser = (0, https_1.onCall)(async (request) => {
    await assertAdmin(request.auth?.uid);
    const uid = request.data?.uid;
    if (!uid) {
        throw new https_1.HttpsError("invalid-argument", "Wymagane pole: uid.");
    }
    // 1) Usuń dane z Firestore
    const db = admin.firestore();
    await db.doc(`users/${uid}`).delete().catch(() => { });
    await deleteByQuery(db.collection("scans").where("userId", "==", uid));
    await deleteByQuery(db.collection("user_exhibitor_points").where("userId", "==", uid));
    await deleteByQuery(db.collection("user_exhibitor_points").where("exhibitorId", "==", uid));
    // 2) Usuń konto z Firebase Auth
    await admin.auth().deleteUser(uid).catch((e) => {
        // Jeśli konto już nie istnieje – ignoruj NOT_FOUND
        if (e?.errorInfo?.code !== "auth/user-not-found")
            throw e;
    });
    return { ok: true };
});
