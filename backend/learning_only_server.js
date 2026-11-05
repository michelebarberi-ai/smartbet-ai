'use strict';

// Dedicated API for central learning. Does NOT create an OpenAI client,
// expose the paid /analyze route, or start background timers.
require('dotenv').config();
const express = require('express');
const {registerLearningRoutes} = require('./learning/learning_routes');

const API_FOOTBALL_ORIGIN = 'https://v3.football.api-sports.io';

async function requestFixture({path, query}, {env = process.env, fetchImpl = fetch} = {}) {
  if (path !== '/fixtures') throw new Error('Unsupported football request');
  const id = Number(query?.id);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid fixture id');
  const apiKey = env.FOOTBALL_API_KEY;
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new Error('Football provider not configured');
  }

  const url = new URL('/fixtures', API_FOOTBALL_ORIGIN);
  url.searchParams.set('id', String(id));
  const response = await fetchImpl(url, {
    method: 'GET',
    headers: {'x-apisports-key': apiKey, accept: 'application/json'},
    redirect: 'error',
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Football provider unavailable');
  const data = await response.json();
  const errors = data?.errors;
  if ((Array.isArray(errors) && errors.length > 0) ||
      (errors && !Array.isArray(errors) && Object.keys(errors).length > 0) ||
      !Array.isArray(data?.response) || data.response.length !== 1 ||
      Number(data.response[0]?.fixture?.id) !== id) {
    throw new Error('Football provider response not verifiable');
  }
  return {data};
}

function createLearningOnlyApp({env = process.env, fetchImpl = fetch} = {}) {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {res.set('Cache-Control', 'no-store'); next();});
  app.use(express.json({limit: '64kb'}));

  // Process health is not a guarantee of database reachability.
  app.get('/health', (_req, res) => res.json({
    service: 'GoalVdLine Central Learning', running: true, databaseChecked: false,
  }));

  registerLearningRoutes(app, {
    env,
    requestApiFootball: (request) => requestFixture(request, {env, fetchImpl}),
  });
  return app;
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 3000;
  createLearningOnlyApp().listen(port, '0.0.0.0', () => {
    console.log(`GoalVdLine central learning listening on port ${port}`);
  });
}

module.exports = {createLearningOnlyApp, requestFixture};
