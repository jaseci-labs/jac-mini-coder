"""Work around a byLLM bug so a config-supplied base URL actually reaches the
model on the plain litellm path (coding plans, OpenAI-compatible gateways).

The bug (byLLM ≤ current): BaseLLM.dispatch_no_streaming builds the call params
WITH `api_base`, then pops it out into `self.api_base` before dispatching:

    self.api_base = params.pop("api_base", DEFAULT_BASE_URL);
    ... self.model_call_no_stream(params);   # params no longer has api_base

Model.model_call_no_stream then has three branches. The `http_client` and
`proxy` branches read `self.api_base`, so they route correctly. The default
`litellm` branch calls `litellm.completion(**params)` — params no longer carries
api_base and self.api_base is never referenced — so litellm never learns the
base URL and sends e.g. `openai/<model>` to api.openai.com.

Fix (this patch): wrap model_call_no_stream / model_call_with_stream and, ONLY
on the litellm branch (not http_client, not proxy), re-inject the config's base
URL into params. litellm honors `api_base` for openai/* once it actually arrives
— verified live against a Z.ai GLM Coding Plan endpoint. Idempotent; a no-op for
models with no configured base.

Upstream: https://github.com/jaseci-labs/jac/issues/7645 — remove this patch once
byLLM forwards api_base on the litellm branch."""

import from jaclang.byllm.lib { Model }

def patch_byllm_api_base() {
    if getattr(Model, "_jmc_api_base_patched", False) { return; }

    def _wrap(orig: any) -> any {
        def wrapped(slf: any, params: any) -> any {
            b = slf.config.get("base_url") or slf.config.get("host") or slf.config.get("api_base");
            if b and (not getattr(slf, "http_client", False)) and (not getattr(slf, "proxy", False)) {
                if isinstance(params, dict) and (not params.get("api_base")) {
                    params["api_base"] = b;
                }
            }
            return orig(slf, params);
        }
        return wrapped;
    }

    for name in ["model_call_no_stream", "model_call_with_stream"] {
        if hasattr(Model, name) {
            setattr(Model, name, _wrap(getattr(Model, name)));
        }
    }
    setattr(Model, "_jmc_api_base_patched", True);
}
