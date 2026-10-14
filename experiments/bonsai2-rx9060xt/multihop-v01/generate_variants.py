"""Create placement-control variants preserving all original answers and evidence IDs."""
import argparse
import hashlib
import json
import random
import re
from pathlib import Path
from generate import create

RECORD=re.compile(r'^\[(\S+)\] VERSION=(\S+) KEY=(\S+) VALUE=(\S+)$')
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--output',default='variants')
    p.add_argument('--target-chars',type=int,default=80000)
    p.add_argument('--seeds',nargs='+',type=int,default=[11,29,47])
    a=p.parse_args()
    original,gold=create(a.target_chars)
    records=[]
    for line in original.splitlines():
        m=RECORD.match(line)
        if m:records.append(line)
    assert len(gold)==40 and len(records)>40
    out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
    baseline_answers={c['id']:(c['answer'],c['evidence_ids']) for c in gold}
    manifest=[]
    for seed in a.seeds:
        rng=random.Random(seed)
        # Reposition each evidence record. The same answer mapping, versions
        # and evidence identifiers are preserved across all variants.
        # New placements are reported; nominal near/far labels from v01
        # are not used as evidence of controlled distances here.
        positions=list(range(101))
        slots=[[] for _ in positions]
        shuffled=records[:]
        rng.shuffle(shuffled)
        for idx,record in enumerate(shuffled):
            position=(idx*37+seed*13)%101
            slots[position].append(record)
        filler='OPS-CONTEXT: Routine monitoring and document retention were reviewed. This sentence does not change an active mapping.\n'
        lines=['Synthetic archive. For identical KEY, prefer the later VERSION regardless of physical position. Follow KEY to a terminal VALUE-.\n']
        for ix in positions:
            rng.shuffle(slots[ix])
            lines.extend(s+'\n' for s in slots[ix])
            lines.extend([filler]*(max(1,a.target_chars//(len(positions)*len(filler)))))
        doc=''.join(lines)
        # Validate exact evidence set and official value mapping after shuffling.
        parsed={}
        ids=set()
        for line in doc.splitlines():
            m=RECORD.match(line)
            if m:
                rid,version,key,val=m.groups()
                assert rid not in ids
                ids.add(rid)
                if key not in parsed or parsed[key][0]<version:
                    parsed[key]=(version,val)
        for c in gold:
            key=c['root']; hops=0
            while not key.startswith('VALUE-'):
                key=parsed[key][1];hops+=1
                assert hops<=10
            assert key==baseline_answers[c['id']][0]
            assert all(x in ids for x in baseline_answers[c['id']][1])
        folder=out/('seed_'+str(seed));folder.mkdir(parents=True,exist_ok=True)
        (folder/'source.txt').write_text(doc,encoding='utf-8')
        (folder/'gold.json').write_text(json.dumps(gold,ensure_ascii=False,indent=2),encoding='utf-8')
        checksum=hashlib.sha256(doc.encode('utf-8')).hexdigest()
        manifest.append({'seed':seed,'folder':str(folder),'source_sha256':checksum,'characters':len(doc),'records':len(records),'cases':len(gold)})
        print('OK seed',seed,'chars',len(doc),'SHA256',checksum,flush=True)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
if __name__=='__main__': main()
