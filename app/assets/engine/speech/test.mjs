// 端到端：真实插件代码 + settings/credentials 读取路径 → 本地 mock 转写接口
import { spawn } from 'node:child_process';
import { writeFileSync, rmSync } from 'node:fs';
import { apply } from './index.mjs';

const PORT = 8791;
const CONFIG = '/tmp/stt-cloud-test.json';
const wav = Buffer.alloc(44 + 16000);
wav.write('RIFF', 0); wav.writeUInt32LE(36 + 16000, 4); wav.write('WAVE', 8);
wav.write('fmt ', 12); wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(16000, 40);
const runtime = (value) => (value === undefined ? rmSync(CONFIG, { force: true }) : writeFileSync(CONFIG, JSON.stringify(value)));

const mock = spawn('python3', ['mock-asr.py', String(PORT)], { cwd: new URL('.', import.meta.url).pathname, stdio: 'ignore' });
await new Promise(r => setTimeout(r, 800));

const providers = { deepseek: { baseURL: `http://127.0.0.1:${PORT}/v1`, apiKeyEnv: 'DEEPSEEK_API_KEY' } };
const keys = { DEEPSEEK_API_KEY: 'sk-remote', WRONG_KEY: 'sk-wrong' };
const ctx = {
  effect: (fn) => { const d = fn(); return () => d?.(); },
  speechToText: { register: (reg) => { ctx.reg = reg; return async () => {}; } },
  settings: { describe: () => [{ ns: 'llm-pi-ai', value: { providers } }] },
  credentials: { resolve: async (ref) => (keys[ref] === undefined ? undefined : { value: keys[ref], source: 'file' }) },
  logger: { warn: (...a) => warnings.push(a.join(' ')) },
};

const warnings = [];
let fails = 0;
const check = async (name, fn) => {
  try { await fn(); console.log('PASS ', name); }
  catch (e) { fails++; console.log('FAIL ', name, '->', e.message); }
};
const run = async (cfg) => {
  apply(ctx, { configPath: CONFIG, ...cfg });
  return await ctx.reg.transcribe({ audio: wav, language: 'zh' }, new AbortController().signal);
};
const expectErr = async (cfg, prefix) => {
  try { await run(cfg); throw new Error('应当失败'); }
  catch (e) { if (!e.message.startsWith(prefix)) throw new Error(`拿到 ${e.message}`); }
};

await check('patch 配置（无 JSON）：转写成功', async () => {
  runtime(undefined);
  const text = await run({ provider: 'deepseek', model: 'whisper-1' });
  if (text !== '云端识别结果') throw new Error(`返回 ${JSON.stringify(text)}`);
});
await check('运行时 JSON 覆盖 patch：立即生效、不重启', async () => {
  runtime({ provider: 'deepseek', model: 'whisper-1' });
  // patch 里故意写坏，证明生效的是文件
  const text = await run({ provider: 'gone', model: 'gone' });
  if (text !== '云端识别结果') throw new Error(`返回 ${JSON.stringify(text)}`);
});
await check('JSON 缺模型 → cloud-model', async () => {
  runtime({ provider: 'deepseek' });
  await expectErr({}, 'cloud-model');
});
await check('没有服务商 → cloud-provider-missing', async () => {
  runtime(undefined);
  await expectErr({}, 'cloud-provider-missing');
});
await check('服务商被删 → cloud-provider-missing', async () => {
  runtime({ provider: 'gone', model: 'x' });
  await expectErr({}, 'cloud-provider-missing');
});
await check('服务商没有 key → cloud-auth（不发请求）', async () => {
  providers.nokey = { baseURL: `http://127.0.0.1:${PORT}/v1` };
  runtime({ provider: 'nokey', model: 'x' });
  await expectErr({}, 'cloud-auth');
  delete providers.nokey;
});
await check('key 无效（401）→ cloud-auth', async () => {
  providers.wrong = { baseURL: `http://127.0.0.1:${PORT}/v1`, apiKeyEnv: 'WRONG_KEY' };
  runtime({ provider: 'wrong', model: 'x' });
  await expectErr({}, 'cloud-auth');
  delete providers.wrong;
});
await check('地址没有转写接口 → cloud-endpoint', async () => {
  providers.broken = { baseURL: `http://127.0.0.1:${PORT}/nope`, apiKeyEnv: 'DEEPSEEK_API_KEY' };
  runtime({ provider: 'broken', model: 'x' });
  await expectErr({}, 'cloud-endpoint');
  delete providers.broken;
});
await check('坏 JSON：记诊断并回退 patch', async () => {
  writeFileSync(CONFIG, '{ "provider": "deepseek", ');
  warnings.length = 0;
  const text = await run({ provider: 'deepseek', model: 'whisper-1' });
  if (text !== '云端识别结果') throw new Error(`返回 ${JSON.stringify(text)}`);
  if (!warnings.some(w => w.includes('cloud-config: invalid'))) throw new Error(`没记诊断：${warnings.join(' | ')}`);
});
await check('JSON 有选择时走 patch 兜底要能看出来', async () => {
  runtime({});
  warnings.length = 0;
  await run({ provider: 'deepseek', model: 'whisper-1' });
  if (!warnings.some(w => w.includes('cloud-config: fallback patch'))) throw new Error(`没记兜底：${warnings.join(' | ')}`);
});
await check('language 空 = 自动（不发 language 字段也成功）', async () => {
  runtime({ provider: 'deepseek', model: 'whisper-1', language: '' });
  const text = await run({});
  if (text !== '云端识别结果') throw new Error(`返回 ${JSON.stringify(text)}`);
});
await check('连不上 → cloud-network', async () => {
  providers.down = { baseURL: 'http://127.0.0.1:1/v1', apiKeyEnv: 'DEEPSEEK_API_KEY' };
  runtime({ provider: 'down', model: 'x', timeoutMs: 3000 });
  await expectErr({}, 'cloud-network');
  delete providers.down;
});


console.log(fails === 0 ? '全部通过' : `${fails} 项失败`);
process.exit(fails === 0 ? 0 : 1);
