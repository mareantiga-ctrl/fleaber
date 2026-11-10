/** Sincronizar com tool/ps_ai/tiers.json */
export const PS_AI_TIERS = {
  lite: {
    label: "Lite",
    ollamaModel: "fleaber-ps-lite",
    baseModel: "llama3.2:3b",
  },
  pro: {
    label: "Pro",
    ollamaModel: "fleaber-ps-pro",
    baseModel: "qwen2.5:7b",
  },
};

export function resolveOllamaModel(tier, storedModel) {
  const t = String(tier || "auto").toLowerCase();
  if (t === "pro") return PS_AI_TIERS.pro.ollamaModel;
  if (t === "lite") return PS_AI_TIERS.lite.ollamaModel;
  if (storedModel && /fleaber-ps-(lite|pro)/.test(storedModel)) return storedModel;
  return PS_AI_TIERS.lite.ollamaModel;
}
