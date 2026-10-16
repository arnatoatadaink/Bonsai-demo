# Bonsai2-27B GPU status (2026-10-16)

- **RX 9060 XT 16 GB:** Prior Bonsai2-27B working setup verified by user. Earlier PP/TG records exist but their conditions need cross-check.
- **RX 9070 XT 16 GB:** PQ2_0 GGUF successfully loaded on Vulkan1 and PP executed (2271 prompt tokens, 529.177954 t/s), but the initial raw /completion request returned EOS after one token, with no textual content and TG=0. **Text generation and TG speed are not yet verified.**
- **llama.cpp:** PrismML fork 0.2.0-dev build 10772 commit e8fd209c9, AMD Adrenalin 26.3.1.
- **Test configuration:** -ngl 99 -sm none -c 4096, K/V q8_0, flash attention on, no speculative decoding; RX9070 XT via Vulkan1.
- **Evidence:** user-uploaded `bonsai2_rx9070xt_20261016_144101.zip`, including manifest, device listing, request, response, and summary. Exact model SHA256 and binary SHA256 in manifest.
- **Next step:** re-run `reports/verify_bonsai2_rx9070xt.ps1`, updated to use chat templating (`--jinja`, `/v1/chat/completions`) and reject one-token EOS. A completed generation of at least 32 tokens is required before claiming TG performance.
- Gemma4 and Qwen comparisons and long-run stability tests are out of scope for this branch.
