import test from 'node:test';
import assert from 'node:assert/strict';
import {deleteAccountData, hasRecentAuthentication} from '../src/accounts.js';
test('account deletion requires a verified UID and recent authentication', () => {
  const now = 1000000;
  assert.equal(hasRecentAuthentication({uid:'alice',token:{auth_time:990}}, now), true);
  for (const auth of [undefined, {uid:'alice',token:{}}, {uid:'alice',token:{auth_time:600}},
    {uid:'alice',token:{auth_time:'990'}}, {uid:'alice',token:{auth_time:9999}}]) {
    assert.equal(hasRecentAuthentication(auth, now), false);
  }
});
test('deletion scopes all reads to the caller and removes identity last', async () => {
  const events=[];
  const db={collection: name => ({doc:uid=>`${name}/${uid}`,where:(field,op,uid)=>{
    assert.equal(field,'userId'); assert.equal(op,'=='); assert.equal(uid,'alice');
    return {get:async()=>({docs:[{ref:`${name}/report`}]})};
  }}),recursiveDelete:async ref=>events.push(ref),batch:()=>({delete:ref=>events.push(ref),commit:async()=>events.push('commit')})};
  await deleteAccountData(db,{deleteUser:async uid=>events.push(`auth/${uid}`)},'alice');
  assert.deepEqual(events,['users/alice','puzzleReports/report','commit','contactUs/report','commit','auth/alice']);
});
test('failed data deletion retains the account for a retry', async () => {
  let deleted = false;
  const db={collection:()=>({doc:()=>({})}),recursiveDelete:async()=>{throw Error('network');}};
  await assert.rejects(deleteAccountData(db,{deleteUser:async()=>{deleted=true;}},'alice'),/network/);
  assert.equal(deleted,false);
});
