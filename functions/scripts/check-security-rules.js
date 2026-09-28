import {readFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve, delimiter} from 'node:path';
import {applicationDefault} from 'firebase-admin/app';

const project = 'puzzle-time-72ad9';
const cliRoot = process.env.FIREBASE_CLI_ROOT || (process.env.PATH || '').split(delimiter)
  .map(entry => resolve(entry, '..', 'firebase-tools')).find(path => existsSync(resolve(path, 'lib/auth.js')));
let accessToken;
if (cliRoot) {
  const auth = createRequire(import.meta.url)(resolve(cliRoot, 'lib/auth.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw Error('Run firebase login first');
  accessToken = (await auth.getAccessToken(account.tokens.refresh_token,
    ['https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/firebase'])).access_token;
} else accessToken = (await applicationDefault().getAccessToken()).access_token;

async function verify(file, testCases) {
  const content = await readFile(new URL(`../../${file}`, import.meta.url), 'utf8');
  const response = await fetch(`https://firebaserules.googleapis.com/v1/projects/${project}:test`, {
    method:'POST', headers:{Authorization:`Bearer ${accessToken}`, 'Content-Type':'application/json'},
    body:JSON.stringify({source:{files:[{name:file,content}]},testSuite:{testCases}})
  });
  const result = await response.json();
  if (!response.ok) throw Error(JSON.stringify(result.error));
  const failures = result.testResults?.flatMap((test,index)=>test.state === 'SUCCESS' ? [] : [{case:testCases[index],test}]) || [];
  if (result.issues?.some(issue=>issue.severity==='ERROR') || failures.length || result.testResults?.length !== testCases.length) {
    throw Error(JSON.stringify({file,issues:result.issues,failures},null,2));
  }
  console.log(`${file}: ${testCases.length} security checks passed (no data written).`);
}
const cases=[];
function add(path,method,uid,expectation,data={}) {
  cases.push({expectation,request:{path:`/databases/(default)/documents/${path}`,method,
    time:'2027-01-01T00:00:00Z',auth:uid?{uid,token:{sub:uid}}:null,resource:{data}},resource:{data:{}}});
}
for (const path of ['users/alice','users/alice/riddleProgress/p1','users/alice/dailychallengeprogress/day',
  'users/alice/timerDailyChallengeProgress/day','users/alice/dailyTenRiddles/day'])
  for (const method of ['get','list','create','update','delete'])
    for (const uid of [null,'bob','alice']) add(path,method,uid,uid==='alice'?'ALLOW':'DENY');
for (const path of ['riddles/original','riddles/weekly_example','dailyChallenges/day','timerRiddlesDaily/day','adminSettings/riddleSettings'])
  for (const method of ['get','list','create','update','delete'])
    for (const uid of [null,'alice']) add(path,method,uid,['get','list'].includes(method)?'ALLOW':'DENY');
for (const path of ['riddleGenerationRuns/week','riddleGenerationRuns/week/candidates/p1','adminSettings/weeklyPuzzles','puzzleReviewAudit/p1','users/alice/private/p1'])
  for (const method of ['get','create','update','delete']) add(path,method,'alice','DENY');
for (const method of ['get','list','update','delete']) add('puzzleReports/p1',method,'alice','DENY');
const report={userId:'alice',riddleId:'p1',reason:'answer',answer:'guess',details:'',status:'open',createdAt:'2027-01-01T00:00:00Z'};
add('puzzleReports/p1','create','alice','ALLOW',report);
for (const patch of [{userId:'bob'},{status:'resolved'},{reason:'bad'},{details:'x'.repeat(1001)},{admin:true}]) add('puzzleReports/p1','create','alice','DENY',{...report,...patch});
const contact={userId:'alice',name:'test',email:'test@example.com',message:'test',timestamp:'2027-01-01T00:00:00Z'};
add('contactUs/c1','create','alice','ALLOW',contact);
add('contactUs/c1','create',null,'DENY',contact);
add('contactUs/c1','create','bob','DENY',contact);
await verify('firestore.rules',cases);
const storage=[];
for (const path of ['logo.png','avatars/user.png','riddles/old.png','riddles/generated/week/p.png'])
  for (const method of ['get','create','update','delete']) storage.push({expectation:method==='get'?'ALLOW':'DENY',
    request:{path:`/b/${project}.firebasestorage.app/o/${path}`,method,time:'2027-01-01T00:00:00Z',auth:null},resource:{size:100,contentType:'image/png'}});
await verify('storage.rules',storage);
