import argparse,json,random,hashlib
from pathlib import Path
GROUPS=[('G1',[1]*8,0),('G2',[2,3]*4,0),('G3',[4,6]*4,0),('G4',[2,3]*4,1),('G5',[4,6]*4,1)]
def create(target=80000):
 r=random.Random(20261014);cases=[];records=[]
 for g,depths,revision in GROUPS:
  for i,depth in enumerate(depths):
   num=len(cases)+1;qid=f'{g}_{i+1:02d}';chain=[f'CASE{num:03d}']+[f'NODE{num:03d}_{j}' for j in range(1,depth)]
   answer=f'VALUE-{r.getrandbits(48):012X}';hops=[]
   for j in range(depth):
    rid=f'{qid}_H{j+1}';hops.append(rid)
    records.append((qid,rid,chain[j],chain[j+1] if j<depth-1 else answer,j,False))
   if revision:
    for j in range(min(2,depth)):
     records.append((qid,f'{qid}_OLD{j+1}',chain[j],f'STALE{num:03d}_{j}',j,True))
   for j in range(2):
    records.append((qid,f'{qid}_DIST{j+1}',chain[0]+f'_SIM{j+1}',f'VALUE-{r.getrandbits(48):012X}',-1,False))
   cases.append(dict(id=qid,group=g,depth=depth,distance='near' if g=='G1' and i<4 else 'far',revision=bool(revision),root=chain[0],answer=answer,evidence_ids=hops))
 lookup={x['id']:x for x in cases};slots=[[] for _ in range(101)]
 for qid,rid,key,val,hop,old in records:
  c=lookup[qid];idx=int(qid[-2:])
  if 'DIST' in rid:pos=(idx*11+len(rid))%95
  elif c['distance']=='near':pos=6+(idx-1)*2
  else:pos=[90,8,78,20,65,35][hop%6]+idx%3
  if old:pos=min(96,pos+4)
  slots[pos].append((rid,key,val,old))
 filler=['OPS-%04d: Routine monitoring recorded stable operations; do not infer a mapping from this entry. Budgets and staffing were reviewed independently.\n'%i for i in range(101)]
 lines=['Synthetic archive. For identical KEY, use later VERSION, regardless of physical position. Follow KEY-VALUE links until terminal VALUE-.\n']
 for i in range(101):
  for rid,key,val,old in slots[i]:
   lines.append(f'[{rid}] VERSION={"2026-01-10" if old else "2026-08-30"} KEY={key} VALUE={val}\n')
  lines.append(filler[i]*(max(1,target//101//len(filler[i]))+1))
 return ''.join(lines),cases
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',default='dataset');p.add_argument('--target-chars',type=int,default=80000);a=p.parse_args()
 doc,cases=create(a.target_chars);out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
 (out/'source.txt').write_text(doc,encoding='utf-8')
 (out/'gold.json').write_text(json.dumps(cases,indent=2),encoding='utf-8')
 print('cases',len(cases),'characters',len(doc),'sha256',hashlib.sha256(doc.encode()).hexdigest())
if __name__=='__main__':main()
