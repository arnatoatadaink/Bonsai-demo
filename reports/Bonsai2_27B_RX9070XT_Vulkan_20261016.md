# Bonsai 2 27B — Radeon RX 9070 XT Vulkan 動作報告（検証中）

対象: **Bonsai 2 27B の単独動作実績と PP/TG 性能**。Gemma 4、Qwen、その他モデルとの比較・MTP横断試験は記載しない。

## 環境（2026-10-16整理）

| 項目 | 設定・記録 | 確度 |
|---|---|---|
| OS | Windows 11 Pro 64-bit | 過去セッション |
| CPU | AMD Ryzen 7 5700X | ユーザー確定 |
| System RAM | 32 GB | 過去セッション |
| GPU | AMD Radeon RX 9070 XT 16 GB | ユーザー確定 |
| Vulkanデバイス | `Vulkan1`（当時のGPU列挙順） | ベンチ設定 |
| AMD Adrenalin | 26.3.1 | ユーザー申告による動作確認 |
| 実装 | PrismML fork of llama.cpp、Vulkan backend | 過去セッション |
| バイナリ | `D:\AI\PrismML\dev\llama.cpp\build-vulkan-ucrt64\bin\llama-server.exe` | 過去セッション |
| 正確なビルドSHA | **未確定**（測定runのmanifest/server log要確認） | 未検証 |

### GPU電力・クロックプロファイル

ユーザー提供の `RX9070XT_UD65.xml`（GPU DevID=7550）における値:

| XML feature | Value | XMLでの状態 | 報告上の扱い |
|---|---:|---|---|
| Feature 3 State 0 | -30 | Feature Enabled=True; State Enabled=True | 電力制限 -30% として記録 |
| Feature 26 State 4 | -500 | Feature Enabled=True; **State Enabled=False** | 保存値（適用確証なし） |
| Feature 12 State 0 | -65 | **Feature Enabled=False; State Enabled=False** | 保存値（適用確証なし） |

`RX9060XT_UD80.xml` は別GPUのプロファイルであり、この9070XT報告には混ぜない。
XMLの機能IDの意味、ドライバーが実際に反映した電圧・実クロック・瞬時電力は、ログで追加確認が必要。

## Bonsai 2 27B 動作・速度

GGUF形式: **PQ2_0**（過去セッションにモデル使用実績あり）。
PrismML fork/Vulkanで実行した記録がある。ただし、**RX 9070 XTに確実に紐づくPP/TGの同一測定ログを、現時点で照合できていない**。

| 測定条件 | PP (tokens/s) | TG (tokens/s) | 状態 |
|---|---:|---:|---|
| RX 9070 XT / Bonsai 2 27B PQ2_0 | 未確定 | 未確定 | 元ログ照合待ち |

**誤転記防止:** 過去セッションの PP=44.16 t/s、TG=29.83 t/s は **RX 9060 XT / Vulkan0** に紐づく基準記録もあり、RX 9070 XTの単独実績として引用しない。また、過去にTG=55.68 t/sのMTP関連トレースが議論されたが、実行デバイス・具体的な条件・PPの同一測定を確認するまでは9070XT速度表に転記しない。

### 速度値の確定に必要な元データ

- RX 9070 XT (`--device Vulkan1`) とモデルファイル名が同一ログ内で確認できるもの
- `timings` の `prompt_per_second` と `predicted_per_second`、トークン数
- Context、KV型、MTP on/off、推論設定、モデル/バイナリのSHAまたはbuild identifier

**公開範囲:** Bonsai2-27Bの動作実績、測定条件、PP/TGのみ。比較・品質・他モデル長時間試験は別ブランチに分離。
