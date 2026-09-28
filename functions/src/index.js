import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineString } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { weekId } from './domain.js';
import { runWeekly } from './pipeline.js';

const project = 'puzzle-time-72ad9';
const app = initializeApp({projectId: project, storageBucket: `${project}.firebasestorage.app`});
const model = defineString('PUZZLE_MODEL', {default: 'gemini-3.5-flash', description: 'Vertex AI model used for puzzle writing and visual checks'});

export const generateWeeklyPuzzles = onSchedule({
  schedule: '0 9 * * 1', timeZone: 'America/Chicago', region: 'us-central1',
  timeoutSeconds: 1800, memory: '1GiB', maxInstances: 1, concurrency: 1,
  retryCount: 1, minBackoffSeconds: 300, maxBackoffSeconds: 300,
}, async event => {
  // The event's original schedule time keeps a retry in its original week.
  const week = weekId(new Date(event.scheduleTime));
  const db = getFirestore(app);
  if ((await db.collection('adminSettings').doc('weeklyPuzzles').get()).data()?.enabled === false) {
    logger.info('Weekly puzzle generation is paused'); return;
  }
  return runWeekly({db, bucket: getStorage(app).bucket(), project, model: model.value(), week, logger});
});
