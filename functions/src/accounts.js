export function hasRecentAuthentication(auth, now = Date.now()) {
  const time = auth?.token?.auth_time;
  return !!auth?.uid && Number.isFinite(time) && time <= now / 1000 + 60 && now / 1000 - time <= 300;
}

export async function deleteAccountData(db, auth, uid) {
  await db.recursiveDelete(db.collection('users').doc(uid));
  for (const name of ['puzzleReports', 'contactUs']) {
    const records = await db.collection(name).where('userId', '==', uid).get();
    for (let offset = 0; offset < records.docs.length; offset += 400) {
      const batch = db.batch();
      for (const record of records.docs.slice(offset, offset + 400)) batch.delete(record.ref);
      await batch.commit();
    }
  }
  // Keep the identity usable for retry until every data deletion succeeds.
  await auth.deleteUser(uid);
}
