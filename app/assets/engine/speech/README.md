# 云端语音转写 provider（交给 SpeechGuest 接入）

`remote-stt.mjs` 挂在引擎的 speech-to-text 服务上，作为 `location: 'cloud'` 的 provider（id `openai-compatible`），
实现 OpenAI 兼容 `POST {baseURL}/audio/transcriptions`（multipart：`file=audio.wav`、`model`、可选 `language`、`response_format=json`）。

**只支持引用已配置服务商**：没有手填模式，配置里不出现地址、也不出现任何密钥。

## 配置来源（运行时 `cloud.json` 优先，patch 兜底）

1. **运行时 JSON**：`/opt/dsh-app/speech/cloud.json`，App 在用户改选择时写入，插件**每次转写现读**——
   改完立即生效，不用重启引擎、不用重写 patch。内容只有选择，绝不放 key：

```json
{ "provider": "deepseek", "model": "whisper-1", "timeoutMs": 30000, "language": "" }
```

- 只放这四项；`language` 为空字符串表示自动。
- **key 永不进文件**，仍走引擎 credentials。
- 未知字段忽略。
- App 侧必须**原子写**（临时文件 + rename），不要让插件读到半截 JSON。

2. **patch 里的 config**（启动时固定，作为兜底/初始值）：

```yaml
- id: speech-to-text-openai
  name: /opt/dsh-app/speech/remote-stt.mjs
  config:
    provider: <已配置服务商 route key>
    model: <转写模型名>
    timeoutMs: 25000
```

文件不存在：直接走 patch 配置（初始状态，不算错）。
文件存在但坏/缺字段：引擎日志记 `cloud-config: invalid`，然后回退 patch 配置。
文件存在但没给 provider、用了 patch 的：记 `cloud-config: fallback patch`，诊断里能看出走了兜底。
两者都没有 `provider` → `cloud-provider-missing`，没有 `model` → `cloud-model`。

## SpeechGuest 要做的

1. 引擎启动前把 `remote-stt.mjs` 写到 `/opt/dsh-app/speech/remote-stt.mjs`（同 `assets/engine/auth` 的方式）。
2. 在 `speech.patch.yml` 生成逻辑里加上面那条 insert（config 可只作为初始值）。
3. 用户改服务商/模型时，把 `cloud.json` 写进 `/opt/dsh-app/speech/`（经现有 Flutter→Kotlin 通道），下次转写即生效。

**前提**：`@deepseek-ai/dsh-experimental-voice-input-bundle` 必须在 profile 的 bundles 里启用，
否则树里没有 `speech-to-text` 服务，本插件 insert 会因缺少依赖而挂不上。

## 错误前缀（App 按前缀映射文案，不静默回落）

`cloud-auth`（key 无效/没配）· `cloud-quota`（额度）· `cloud-rate-limit`（太频繁）· `cloud-timeout` ·
`cloud-network`（连不上）· `cloud-server`（5xx/解析失败）· `cloud-model`（模型名不对/没选）·
`cloud-bad-audio`（音频被拒）· `cloud-endpoint`（404，地址没有转写接口）· `cloud-provider-missing`（服务商不存在/没选）

## 本地跑

```bash
python3 mock-asr.py 8791 &
node test.mjs     # 12 项：patch 配置、JSON 覆盖、坏 JSON 记诊断并回退、兜底可见、空语言、缺模型、
                  #       没服务商、服务商被删、没 key、401、404、连不上
```
