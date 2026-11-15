// 云端语音识别 provider（OpenAI 兼容 /v1/audio/transcriptions），挂在 speech-to-text 服务上。
// 只支持引用已配置服务商：baseURL 和 key 都从该服务商取（key 经 credentials），插件配置里不出现任何地址或密钥。
//
// 配置两条来源，运行时文件优先：
//   /opt/dsh-app/speech/cloud.json   App 写，{ provider, model, timeoutMs?, language? }，只放选择、绝不放 key
//   patch 里的 config                 provider / model / language / languages / timeoutMs，启动时固定
// 每次转写现读 JSON：改完立即生效，不用重启引擎；文件不存在就退回 patch 配置。
//
// 失败前缀：cloud-auth / cloud-quota / cloud-rate-limit / cloud-timeout / cloud-network /
//          cloud-server / cloud-model / cloud-bad-audio / cloud-endpoint / cloud-provider-missing

import { readFileSync } from 'node:fs';

export const name = 'speech-to-text-openai';
export const inject = ['speechToText', 'settings', 'credentials'];

const PI_AI = 'llm-pi-ai';
const fail = (code, message) => new Error(`${code}: ${message}`);

function checkConfig(config) {
  // provider / model 可以只在运行时 JSON 里给：patch 里写死了就得重启引擎才改得动。
  const provider = String(config?.provider ?? '').trim();
  const model = String(config?.model ?? '').trim();
  return {
    provider,
    configPath: typeof config?.configPath === 'string' && config.configPath.trim() !== '' ? config.configPath.trim() : '/opt/dsh-app/speech/cloud.json',
    model,
    language: typeof config?.language === 'string' && config.language.trim() !== '' ? config.language.trim() : undefined,
    languages: Array.isArray(config?.languages) && config.languages.length > 0 ? config.languages.map(String) : ['auto', 'zh', 'en', 'ja', 'ko', 'yue'],
    timeoutMs: Number.isFinite(config?.timeoutMs) && config.timeoutMs > 0 ? config.timeoutMs : 25000,
  };
}

// App 写这个文件（只放 provider/model/timeoutMs，绝不放 key），插件每次转写现读：
// 改完立即生效，不用重启引擎，也不用重写 patch。
function readRuntime(ctx, cfg) {
  let raw;
  try {
    raw = readFileSync(cfg.configPath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') return { live: {}, present: false, invalid: false };
    ctx.logger?.warn?.('cloud-config: unreadable', cfg.configPath, String(error?.message ?? error));
    return { live: {}, present: true, invalid: true };
  }
  try {
    const value = JSON.parse(raw);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('not a JSON object');
    return { live: value, present: true, invalid: false };
  } catch (error) {
    // 契约：坏文件不静默吞，诊断里要能看到，然后才回退 patch 配置。
    ctx.logger?.warn?.('cloud-config: invalid', cfg.configPath, String(error?.message ?? error));
    return { live: {}, present: true, invalid: true };
  }
}

function effectiveConfig(ctx, cfg) {
  const { live, present, invalid } = readRuntime(ctx, cfg);
  const provider = typeof live.provider === 'string' && live.provider.trim() !== '' ? live.provider.trim() : cfg.provider;
  const model = typeof live.model === 'string' && live.model.trim() !== '' ? live.model.trim() : cfg.model;
  const timeoutMs = Number.isFinite(live.timeoutMs) && live.timeoutMs > 0 ? live.timeoutMs : cfg.timeoutMs;
  if (present && live.provider === undefined && cfg.provider !== '') ctx.logger?.warn?.('cloud-config: fallback patch');
  if (provider === undefined || provider === '') throw fail('cloud-provider-missing', '还没有选择服务商');
  if (model === undefined || model === '') throw fail('cloud-model', '还没有选择转写模型');
  void invalid; void present;
  return { provider, model, timeoutMs, language: typeof live.language === 'string' && live.language.trim() !== '' ? live.language.trim() : cfg.language, languages: cfg.languages };
}

// 每次转写现解析：服务商被删/改地址/换 key 立刻生效，不用重启。
async function resolveEndpoint(ctx, provider) {
  const section = ctx.settings.describe({ redactSecrets: true }).find((s) => s.ns === PI_AI);
  const profile = section?.value?.providers?.[provider];
  if (profile === undefined) throw fail('cloud-provider-missing', `服务商 ${provider} 已不存在`);
  if (typeof profile.baseURL !== 'string' || profile.baseURL === '') throw fail('cloud-provider-missing', `服务商 ${provider} 没有地址`);
  const ref = typeof profile.apiKeyEnv === 'string' && profile.apiKeyEnv !== '' ? profile.apiKeyEnv : undefined;
  const found = ref === undefined ? undefined : await ctx.credentials.resolve(ref);
  if (found?.value === undefined || found.value === '') throw fail('cloud-auth', '这个服务商还没有可用的 key，去模型设置里补上');
  return { baseURL: profile.baseURL.replace(/\/+$/, ''), key: found.value };
}

function redact(text, key) {
  return key === undefined || key === '' ? text : String(text).split(key).join('***');
}

function classifyNetwork(error) {
  const name = error?.name ?? '';
  if (name === 'AbortError' || name === 'TimeoutError') return fail('cloud-timeout', '云端识别超时');
  const cause = error?.cause ?? error;
  return fail('cloud-network', String(cause?.message ?? error?.message ?? '请求失败'));
}

function classifyHttp(status, body, key) {
  const detail = redact(body.slice(0, 200), key);
  if (status === 401 || status === 403) return fail('cloud-auth', 'API key 无效或没有权限');
  if (status === 402) return fail('cloud-quota', '额度不足');
  if (status === 429) return fail('cloud-rate-limit', '请求太频繁');
  if (status === 404) return fail('cloud-endpoint', '这个地址没有转写接口，检查地址是否以 /v1 结尾');
  if (status === 413 || status === 415 || status === 422) return fail('cloud-bad-audio', `音频被拒绝（HTTP ${status}）`);
  if (status === 400) return /model/i.test(body) ? fail('cloud-model', `模型名不对：${detail}`) : fail('cloud-bad-audio', `请求被拒绝：${detail}`);
  return fail('cloud-server', `HTTP ${status} ${detail}`);
}

async function transcribe(ctx, cfg, { audio, language }, signal) {
  const live = effectiveConfig(ctx, cfg);
  const endpoint = await resolveEndpoint(ctx, live.provider);
  const controller = new AbortController();
  const combined = AbortSignal.any([signal, controller.signal]);
  const timer = setTimeout(() => controller.abort(new Error('timeout')), live.timeoutMs);
  try {
    const form = new FormData();
    form.append('file', new Blob([audio], { type: 'audio/wav' }), 'audio.wav');
    form.append('model', live.model);
    form.append('response_format', 'json');
    const hint = language ?? live.language;
    if (hint !== undefined && hint !== '' && hint !== 'auto') form.append('language', hint);
    let response;
    try {
      response = await fetch(`${endpoint.baseURL}/audio/transcriptions`, {
        method: 'POST', body: form, headers: { Authorization: `Bearer ${endpoint.key}` }, signal: combined,
      });
    } catch (error) {
      throw classifyNetwork(error);
    }
    const text = await response.text().catch(() => '');
    if (!response.ok) throw classifyHttp(response.status, text, endpoint.key);
    let parsed;
    try { parsed = JSON.parse(text); } catch { throw fail('cloud-server', `返回不是 JSON：${redact(text.slice(0, 120), endpoint.key)}`); }
    const transcript = typeof parsed?.text === 'string' ? parsed.text : '';
    if (transcript === '') throw fail('cloud-server', '返回里没有 text');
    return transcript;
  } finally {
    clearTimeout(timer);
  }
}

export function apply(ctx, config) {
  const cfg = checkConfig(config);
  const info = {
    id: 'openai-compatible',
    name: cfg.model === '' ? 'Cloud' : `Cloud (${cfg.model})`,
    location: 'cloud',
    languages: cfg.languages,
    downloadSources: [],
  };
  ctx.effect(() => {
    const unregister = ctx.speechToText.register({
      info,
      transcribe: async (input, signal) => await transcribe(ctx, cfg, input, signal),
    });
    return async () => { await unregister(); };
  });
}
