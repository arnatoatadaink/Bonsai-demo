#!/usr/bin/env python3
"""Deterministic long-document test with distributed, answerable facts."""
import argparse
import json
import random
from pathlib import Path

FACTS = [
    ("F01","2026年1月のAlpha倉庫在庫数","3187"),
    ("F02","2026年2月のBeta倉庫在庫数","2714"),
    ("F03","2026年3月のGamma倉庫在庫数","4056"),
    ("F04","北部拠点の4月監査担当","佐伯"),
    ("F05","南部拠点の5月監査担当","長谷川"),
    ("F06","東部拠点の6月監査担当","河村"),
    ("F07","Nimbus計画の正式承認日","未承認"),
    ("F08","Orion計画の正式承認日","2026-07-18"),
    ("F09","Vega計画の正式承認日","2026-08-09"),
    ("F10","A製品の確定出荷日","2026-04-16"),
    ("F11","B製品の確定出荷日","2026-05-21"),
    ("F12","C製品の確定出荷日","2026-06-27"),
    ("F13","第1四半期の確定営業利益（百万円）","142"),
    ("F14","第2四半期の確定営業利益（百万円）","119"),
    ("F15","第3四半期の営業利益の確定値","未公表"),
    ("F16","例外規則R1の対象地域","北部のみ"),
    ("F17","例外規則R2の終了日","2026-12-31"),
    ("F18","例外規則R3の対象契約","2026-10-15より前の企業契約"),
    ("F19","事故INC-41の一次原因","冷却ポンプ停止"),
    ("F20","事故INC-42の一次原因","権限設定ミス"),
    ("F21","事故INC-43の一次原因","通信断"),
    ("F22","サービスDeltaの正式運用開始日","2026-09-04"),
    ("F23","サービスEchoの正式運用開始日","2026-09-19"),
    ("F24","サービスFoxtrotの正式運用開始日","延期・未定")
]
FILL = [
    "定例点検では個別の報告書番号を照合した。一般的な手続きの記述は各拠点に共通するが、確定値とはみなさない。",
    "週次会議は進捗とリスクを整理した。提案、予測、承認、実績を区別して記録する運用を続けている。",
    "関係部署は監査可能性を維持するために文書の改訂履歴を保存する。変更がなければ実績も変わらない。",
    "ログの保全計画が更新された。集約された統計は個別案件の状態を保証しない。",
    "手順書には一般的な例外処理が載るが、個別の条件と日付は別途正式記録で確認する。"
]
def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output",default="dataset")
    p.add_argument("--target-chars",type=int,default=65000)
    a = p.parse_args()
    out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
    rnd=random.Random(20261014)
    groups=[[] for _ in range(len(FACTS)+1)]
    target=max(a.target_chars,30000)
    while sum(len(x) for group in groups for x in group) < target:
        for group in groups:
            group.append(rnd.choice(FILL)+"\n")
    parts=["社内業務記録の合成データ。根拠ID付きの確定事項だけを回答根拠とする。\n"]
    for i,(fid,label,value) in enumerate(FACTS):
        parts.extend(groups[i])
        parts.append("【正式記録 "+fid+"】"+label+"： "+value+"。この行は確定事項の記録。\n")
    parts.extend(groups[-1])
    text="".join(parts)
    (out/"source.txt").write_text(text,encoding="utf-8")
    gold=[{"id":fid,"question":label+"は何ですか？","expected":value} for fid,label,value in FACTS]
    (out/"gold.json").write_text(json.dumps(gold,ensure_ascii=False,indent=2),encoding="utf-8")
    prompt="以下の文書だけを根拠として、質問24件に回答してください。推測は禁止です。回答は各行「F01: 値」の形式で1件1行、F01からF24まで順に出力してください。説明や挨拶は不要です。\n\n【文書】\n"+text+"\n【質問】\n"+"\n".join(f"{x['id']}: {x['question']}" for x in gold)
    (out/"prompt.txt").write_text(prompt,encoding="utf-8")
    print("created",out,"characters",len(text),"facts",len(gold))
if __name__=="__main__":main()
