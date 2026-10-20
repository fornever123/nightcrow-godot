const fs = require('fs');
try {
  const ts = require(require.resolve('typescript', {paths: ['/vercel/sandbox/node_modules/@remotion/bundler/dist/esbuild-loader']}));
  if (!ts.sys) ts.sys = {readFile: (p) => { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return undefined; } }};
  if (!ts.readConfigFile) ts.readConfigFile = (p, rf) => { const t = p && rf(p); try { return {config: t ? JSON.parse(t) : {}}; } catch (e) { return {config: {}}; } };
} catch (e) { console.error('tsshim', e.message); }
