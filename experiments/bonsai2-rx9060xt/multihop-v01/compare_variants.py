"""Compare per-seed results. No model interaction."""
import argparse,csv,collections,json
from pathlib import Path
def main():
    p=argparse.ArgumentParser();p.add_argument('--results',default='results');a=p.parse_args()
    paths=sorted(Path(a.results).glob('*/fact_checks.csv'))
    rows=[]
    for path in paths:
        run=path.parent
        manifest=run/'run_manifest.json'
        if not manifest.exists():continue
        meta=json.loads(manifest.read_text(encoding='utf-8'))
        seed=Path(meta['dataset']).name
        for item in csv.DictReader(path.open(encoding='utf-8-sig',newline='')):
            if seed.startswith('seed_'):
                rows.append(dict(model=meta['model'],seed=seed,group=item['group'],id=item['id'],depth=item['depth'],revision=item['revision'],
                    answer_exact=item['answer_exact']=='True',evidence_exact=item['evidence_exact']=='True',run=str(run)))
    groups=collections.defaultdict(list)
    for x in rows:groups[(x['model'],x['seed'],x['group'])].append(x)
    print('model,seed,group,n,answers,evidence')
    for key,items in sorted(groups.items()):
        print(*key,len(items),sum(x['answer_exact'] for x in items),sum(x['evidence_exact'] for x in items),sep=',')
    print('\nReminder: repeated run directories of the same seed should not be pooled without specifying which run is canonical.')
if __name__=='__main__':main()
