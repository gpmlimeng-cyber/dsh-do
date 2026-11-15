// 「想多久再回」：把模型的思考档位（reasoning effort）包成四档人话。
//
// 对标 Miffan 的 ImThinkTime，但数据源不同：DS Bot 的 `state` 只给
// `bot.model`（`provider/model`）和 `bot.effort`，档位列表在 DSH 的
// `session/modelCatalog` 里（[modelCatalogProvider] / `client.listModels()`）。
// 所以这里不新加客户端接口、不新造存储，只做「ref → 档位列表」的查表和双向映射。
//
// 四档（Chief 定的）：
//   秒回     → off → minimal（不思考）
//   看情况   → 清空 effort，让引擎自己决定（写空串，宿主按「清空」处理）
//   多想想   → high
//   深思熟虑 → max
//
// 模型没有任何思考档位时整行隐藏：[modelEffortsProvider] 返回空表。
// 存的是每只 Bot 自己的 `effort`，专业模式里原样保留。
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models_state.dart';

/// 四档人话。
enum ReplyPace { instant, adaptive, thoughtful, deep }

/// 「秒回」按这个优先级降级：模型没有 off 就用最小的一档。
const _instantOrder = ['off', 'minimal', 'low'];

/// 「多想想」：high 优先，没有就往两边退一级。
const _thoughtfulOrder = ['high', 'xhigh', 'medium'];

/// 「深思熟虑」：max 优先。
const _deepOrder = ['max', 'xhigh', 'high'];

/// 某一档要写进 `bot.effort` 的值；**空串表示清空**（自适应＝模型默认），
/// 和 `DsBotApi.updateBot(effort: '')` 的语义一致，不要传 null（null 是「不改」）。
String wireEffortFor(ReplyPace pace, List<ReasoningEffort> supported) {
  final ids = [for (final effort in supported) effort.id];
  if (ids.isEmpty) return '';
  String? pick(List<String> order) {
    for (final id in order) {
      if (ids.contains(id)) return id;
    }
    return null;
  }

  return switch (pace) {
    ReplyPace.adaptive => '',
    // 一个档都没匹配上时退到最低那一档，别给引擎一个不存在的值。
    ReplyPace.instant => pick(_instantOrder) ?? ids.first,
    ReplyPace.thoughtful => pick(_thoughtfulOrder) ?? ids.last,
    ReplyPace.deep => pick(_deepOrder) ?? ids.last,
  };
}

/// 反查：这只 Bot 现在存着的 effort 属于哪一档。
///
/// 没存（null / 空串）就是「看情况」；存了模型已经不支持的档位也按「看情况」显示，
/// 免得界面停在一个选不出来的值上。
ReplyPace paceOf(String? effort, List<ReasoningEffort> supported) {
  if (effort == null || effort.isEmpty) return ReplyPace.adaptive;
  if (!supported.any((entry) => entry.id == effort)) return ReplyPace.adaptive;
  return switch (effort) {
    'off' || 'minimal' || 'low' => ReplyPace.instant,
    'high' => ReplyPace.thoughtful,
    'max' || 'xhigh' => ReplyPace.deep,
    // medium 落在中间，和「看情况」是一回事。
    _ => ReplyPace.adaptive,
  };
}

/// `bot.model` 的档位列表；模型不支持思考时为空表（UI 整行隐藏）。
///
/// `bot.model` 是 `provider/model`；直接按路由精确匹配，找不到再按 model id
/// 兜一层（宿主偶尔给的是不带 provider 的 id）。
final modelEffortsProvider = Provider.family<List<ReasoningEffort>, String?>((ref, modelRef) {
  final catalog = ref.watch(modelCatalogProvider).value;
  return effortsOf(catalog, modelRef);
});

List<ReasoningEffort> effortsOf(ModelCatalog? catalog, String? modelRef) {
  if (catalog == null || modelRef == null || modelRef.isEmpty) return const [];
  final slash = modelRef.indexOf('/');
  if (slash <= 0) {
    for (final model in catalog.models) {
      if (model.id == modelRef) return model.efforts;
    }
    return const [];
  }
  final provider = modelRef.substring(0, slash);
  final id = modelRef.substring(slash + 1);
  final exact = findModel(catalog, ModelSelection(provider: provider, model: id));
  if (exact != null) return exact.efforts;
  for (final model in catalog.models) {
    if (model.id == id) return model.efforts;
  }
  return const [];
}
