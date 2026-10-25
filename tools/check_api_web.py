"""Verify that a built student web app boots REST and does not load Firebase."""
import argparse
import hashlib
import json
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('directory',nargs='?',default='build/web')
parser.add_argument('--report',default='docs/evidence/api-client/web-build.json')
args=parser.parse_args()
root=Path(args.directory)
files=['index.html','flutter_bootstrap.js','main.dart.js']
for name in files:
    assert (root/name).is_file(), f'Missing build asset: {name}'
    content=(root/name).read_text(encoding='utf-8-sig')
    for forbidden in ['firebase.initializeApp','firebase-app-compat.js','firebase-auth-compat.js','firebase-firestore-compat.js','snackup-8fe96','firestore.googleapis.com']:
        assert forbidden not in content, f'Unexpected Firebase reference in {name}'
index=(root/'index.html').read_text(encoding='utf-8-sig')
assert '$FLUTTER_BASE_HREF' not in index, 'Unsubstituted Flutter base URL'
assert 'flutter_bootstrap.js' in index, 'Flutter bootstrap is missing'
result={'checks':['build assets present','Firebase bootstrap absent','base href substituted','Flutter bootstrap referenced'],'entrypoint':'lib/main.dart -> lib/student_api/student_root.dart',
    'firebaseLoaded':False,'buildFiles':{name:{'bytes':(root/name).stat().st_size,
        'sha256':hashlib.sha256((root/name).read_bytes()).hexdigest()} for name in files},
    'scope':'Static build verification only; not a deployed-server or browser end-to-end test'}
report=Path(args.report)
report.parent.mkdir(parents=True,exist_ok=True)
report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'verified':'REST web build, no Firebase bootstrap','report':str(report)}))
