"""Package a verified CI build and exact-commit sources for Windows review.

Inputs come from the selected commit, its successful CI artifact and an existing
licensed embedded Python runtime. No deploy, account creation or SDK download.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

FORBIDDEN={'.env','credentials.json','service-account.json','serviceAccountKey.json'}

def digest(data):return hashlib.sha256(data).hexdigest()
def blob(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

def build(args):
    root=args.source.resolve();tree=json.loads(args.tree.read_text());files={}
    for entry in tree['tree']:
        if entry['type']!='blob':continue
        path=entry['path'];source=root/path
        if Path(path).name in FORBIDDEN or Path(path).suffix.lower() in {'.pem','.p12','.pfx','.key'}:
            raise ValueError('Source contains a potential secret file: '+path)
        data=source.read_bytes()
        if blob(data)!=entry['sha']:raise ValueError('Local source differs from committed source: '+path)
        files[path]=data
    # Git tree identity comes from the exact commit, not a moving branch name.
    if tree['sha']!=args.tree_sha:raise ValueError('Unexpected tree')
    payload={'FUENTE.txt':('Código versionado y documentación del commit:\nhttps://github.com/Gabino-RG/SnackUP-core/tree/'+args.commit+'\n').encode()}
    with zipfile.ZipFile(args.build) as z:
        require_files={'index.html','main.dart.js','flutter_bootstrap.js','vendor/zxing-0.21.3.min.js'}
        if not require_files.issubset(z.namelist()):raise ValueError('Missing web build files')
        for name in z.namelist():
            if name.endswith('/'):continue
            if name.startswith('/') or '..' in Path(name).parts:raise ValueError('Unsafe build path')
            payload['web/'+name]=z.read(name)
    with zipfile.ZipFile(args.runtime_package) as z:
        prefix='SnackUP-PC/runtime/'
        runtime=[n for n in z.namelist() if n.startswith(prefix) and not n.endswith('/')]
        if not any(n.endswith('/python.exe') for n in runtime):raise ValueError('Missing embedded Python')
        for name in runtime:payload['runtime/'+name[len(prefix):]]=z.read(name)
    for name in ['review_server.py','INICIAR_SNACKUP.cmd','LEEME.txt']:
        data=files['scripts/review/'+name]
        if name.endswith('.cmd'):data=data.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
        payload[name]=data
    for name in ['PANELES_ENTREGA.md','CONTRATO_PANELES.md','PORTAL_API_LOCAL.md','VALIDACION_PANELES.md']:
        key='docs/'+name
        if key in files:payload['documentos/'+name]=files[key]
    payload['VERSION.json']=json.dumps({'product':'SnackUP · Paneles de negocios y administración','mode':'revision_local','branch':'test/api-aaa-sonarqube','commit':args.commit,'tree':args.tree_sha,
        'ci_run':args.run,'artifact_sha256':digest(args.build.read_bytes()),'runtime_source_sha256':digest(args.runtime_package.read_bytes()),'database':'SQLite de prueba; no backend productivo','production_backend_integrated':False},ensure_ascii=False,indent=2).encode()
    payload['SHA256SUMS.txt']='\n'.join(f'{digest(data)}  {name}' for name,data in sorted(payload.items())).encode()+b'\n'
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name,data in sorted(payload.items()):z.writestr('SnackUP-Paneles-PC/'+name,data)
    with zipfile.ZipFile(args.output) as z:
        if z.testzip() is not None:raise ValueError('Corrupt ZIP')
    print(json.dumps({'file':str(args.output.resolve()),'bytes':args.output.stat().st_size,'sha256':digest(args.output.read_bytes()),'commit':args.commit,'source_files':len(files),'package_files':len(payload)}))

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--source',type=Path,required=True);p.add_argument('--tree',type=Path,required=True);p.add_argument('--tree-sha',required=True);p.add_argument('--commit',required=True)
    p.add_argument('--run',type=int,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--runtime-package',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    build(p.parse_args())
if __name__=='__main__':main()
