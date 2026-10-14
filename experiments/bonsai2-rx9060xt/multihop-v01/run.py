import argparse,csv,json,re,time,hashlib,urllib.request,urllib.error
from pathlib import Path
from datetime import datetime
def call(url,body=None,timeout=10):
 payload=None if body is None else json.dumps(body,ensure_ascii=False).encode('utf-8')
 req=urllib.request.Request(url,data=payload,headers={'Content-Type':'application/json; charset=utf-8'})
 try:
  with urllib.request.urlopen(req,timeout=timeout) as f:return json.loads(f.read().decode('utf-8'))
 except urllib.error.HTTPError as e:raise RuntimeError(f'HTTP {e.code}: {e.read(2000).decode("utf-8","replace")}') from e
def main():
 p=argparse.ArgumentParser();p.add_argument('--model',choices=['bonsai','gemma'],required=True);p.add_argument('--timeout',type=int,default=1200);a=p.parse_args()
 root=Path(__file__).resolve().parent;d=root/'dataset';out=root/'results'/(a.model+'_'+datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir(parents=True)
 base='http://127.0.0.1:'+('8078' if a.model=='bonsai' else '8081')
 try:
  doc=(d/'source.txt').read_text(encoding='utf-8');gold=json.loads((d/'gold.json').read_text(encoding='utf-8'))
  print(f'Dataset: {len(doc)} chars, {len(gold)} cases; SHA256 {hashlib.sha256(doc.encode()).hexdigest()}',flush=True)
  if len(doc)>180000:raise RuntimeError('Corpus exceeds conservative size guard')
  print('Health:',call(base+'/health',timeout=10),flush=True)
  (out/'models.json').write_text(json.dumps(call(base+'/v1/models'),indent=2),encoding='utf-8')
  rows=[];metrics=[]
  for group in ['G1','G2','G3','G4','G5']:
   subset=[x for x in gold if x['group']==group]
   qs='\n'.join(x['id']+': ROOT='+x['root'] for x in subset)
   prompt='Use the mapping archive below. For each requested root, repeatedly follow the latest VERSION for each KEY until a terminal VALUE-XXXXXXXXXXXX is reached. Report each final value plus all supporting active record IDs in order. Avoid stale versions. Output one line each: G1_01: VALUE-XXXXXXXXXXXX | G1_01_H1,G1_01_H2. No extra prose.\nARCHIVE:\n'+doc+'\nQUESTIONS:\n'+qs
   body={'messages':[{'role':'user','content':prompt}],'max_tokens':2048,'temperature':0,'top_k':1,'seed':42,'reasoning_effort':'none','chat_template_kwargs':{'enable_thinking':False}}
   (out/(group+'.request.json')).write_text(json.dumps(body,ensure_ascii=False),encoding='utf-8')
   print(f'[{group}] sending {len(subset)} questions, {len(prompt)} chars to {a.model}',flush=True)
   start=time.monotonic();res=call(base+'/v1/chat/completions',body,timeout=a.timeout);elapsed=time.monotonic()-start
   (out/(group+'.response.json')).write_text(json.dumps(res,ensure_ascii=False,indent=2),encoding='utf-8')
   answer=res['choices'][0]['message'].get('content') or ''
   (out/(group+'.answer.txt')).write_text(answer,encoding='utf-8')
   found={}
   for line in answer.splitlines():
    m=re.match(r'^\s*\*{0,2}(G[1-5]_\d\d)\*{0,2}\s*[:：]\s*([^|\n]+)(?:\|\s*(.*))?',line)
    if m:found[m[1]]=(m[2].strip(' *。.'),[x.strip(' *。.') for x in (m[3] or '').split(',') if x.strip()])
   for item in subset:
    val,ev=found.get(item['id'],('',[]));expected=item['answer'];required=item['evidence_ids']
    rows.append({'id':item['id'],'group':group,'depth':item['depth'],'distance':item['distance'],'revision':item['revision'],'expected':expected,'observed':val,'answer_exact':val==expected,'evidence_exact':ev==required,'expected_evidence':','.join(required),'observed_evidence':','.join(ev),'status':'MISSING' if not val else ('EXACT' if val==expected and ev==required else 'REVIEW')})
   timing=res.get('timings') or {};usage=res.get('usage') or {}
   metrics.append({'group':group,'elapsed_sec':round(elapsed,2),'prompt_tokens':usage.get('prompt_tokens'),'generated_tokens':usage.get('completion_tokens'),'pp_tok_s':timing.get('prompt_per_second'),'tg_tok_s':timing.get('predicted_per_second'),'finish_reason':res['choices'][0].get('finish_reason')})
   print(f'[{group}] finished {elapsed:.1f}s; finish={metrics[-1]["finish_reason"]}; exact answer={sum(x["answer_exact"] for x in rows if x["group"]==group)}/8',flush=True)
   with (out/'fact_checks.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
   (out/'metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
  print('FINAL',sum(x['answer_exact'] for x in rows),'/40 answer;',sum(x['evidence_exact'] for x in rows),'/40 evidence',flush=True)
  print('Results:',out,flush=True)
 except Exception as e:
  (out/'failure.txt').write_text(repr(e),encoding='utf-8');print('ERROR:',repr(e),'Results:',out,flush=True);raise
if __name__=='__main__':main()
