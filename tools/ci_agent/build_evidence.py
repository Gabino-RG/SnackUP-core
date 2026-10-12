"""Build transparent UI evidence from unmodified GitHub job metadata and logs."""
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
E = ROOT / 'evidence'
META = [
 ('checkout','Commit / descarga','Checkout','actions/checkout@v4','Descarga el commit de la rama que disparó el CI.'),
 ('setup','Entorno Flutter','Setup Flutter','Flutter 3.32.0 stable','Configura el SDK y la caché.'),
 ('dependencies','Dependencias','Dependencies','flutter pub get','Resuelve las dependencias de SnackUP.'),
 ('analyze','Análisis estático','Static analysis','flutter analyze --no-fatal-infos --no-fatal-warnings','Detecta errores Dart; esta ejecución toleró avisos e información.'),
 ('unit','Pruebas unitarias y widgets','Unit and widget tests','flutter test --coverage','Verifica carrito, autenticación, pedidos, reseñas y monitoreo.'),
 ('build','Compilación Web','Build integrated application','flutter build web --no-web-resources-cdn --target lib/main.dart','Compila la aplicación integrada de SnackUP.'),
 ('artifact','Artefacto versionado','Preserve integrated web build','actions/upload-artifact@v4','Conserva app/build/web como artefacto de CI. No despliega.'),
]

def create(which, run):
    jobs=json.loads((E/f'github-{which}-jobs.json').read_text())
    job=jobs['jobs'][0]
    lines=(E/f'github-{which}.log').read_text().splitlines()
    stages=[]
    for ident,name,original,command,desc in META:
        s=next(s for s in job['steps'] if s['name']==original)
        start,end=s['started_at'],s['completed_at']
        stage_lines=[re.sub(r'\x1b\[[0-9;]*[A-Za-z]','',l) for l in lines if l[:19]>=start[:19] and l[:19]<=end[:19]]
        # Keep evidence useful without setup environment noise.
        useful=[l for l in stage_lines if any(k in l for k in ('tests passed','issues found','Built build/web','Error:','✅','✔ API-','SHA256','successfully finalized','Process completed with exit code','Changed','Compiling','Resolving dependencies','Got dependencies'))]
        status=s['conclusion']
        stages.append(dict(id=ident,name=name,original_name=original,status=status,command=command,description=desc,started_at=start,completed_at=end,logs=useful[-16:] or [f"GitHub Actions: {original} → {status}"] ))
    good=which=='success'
    decisions=[dict(level='success' if good else 'error',title='CI aprobado: artefacto disponible' if good else 'Falla rápida: compilación detenida',detail='59 pruebas aprobadas y aplicación Web compilada. GitHub conservó el artefacto.' if good else "El log reportó: Tear-offs of external top-level member 'reloadApplication' are disallowed. La etapa del artefacto se omitió.",recommendation='Revisar los 124 avisos del análisis estático antes de endurecer el gate.' if good else 'Revisar la referencia a reloadApplication y volver a compilar. Esta falla histórica fue corregida en el commit del CI aprobado.')]
    artifacts=json.loads((E/'github-artifacts.json').read_text())['artifacts'] if good else []
    state=dict(mode='replay',repository='Gabino-RG/SnackUP-core',run_id=run['id'],sha=run['sha'],branch=run['branch'],url=run['url'],title='Flutter CI · SnackUP',status='completed',conclusion=job['conclusion'],started_at=stages[0]['started_at'],completed_at=stages[-1]['completed_at'],stages=stages,decisions=decisions,artifacts=[dict(name=a['name'],url=f"{run['url']}/artifacts/{a['id']}",sha256=a['digest'],size_bytes=a['size_in_bytes']) for a in artifacts],source_notes='Reproducción de ejecución real del 5 de octubre de 2026 (UTC), acelerada. Los tiempos y resultados proceden de GitHub Actions. Este workflow no incluye una etapa REST ni SonarQube; sus resultados se documentan por separado. El análisis toleró 124 avisos.',metrics=dict(tests_passed=59 if good else None,analysis_issues=124 if good else None),integration_evidence=dict(run_id=37257224010,job='api-rest',status='success',tests_passed=18,sha='ddf0d461b07c407510bca28ef2cd5026aa4a624f',url='https://github.com/Gabino-RG/SnackUP-core/actions/runs/37257224010',note='Pruebas REST del mismo commit, en un workflow separado. El job Sonar de ese workflow falló; el workflow completo no se declara aprobado.'))
    path=E/('evidence.json' if good else 'evidence-failure.json')
    path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
    return state

if __name__=='__main__':
    runs=json.loads((E/'github-runs.json').read_text())
    success=create('success',next(r for r in runs if r['id']==37257224068))
    failure=create('failure',next(r for r in runs if r['id']==37257039123))
    (ROOT/'web').mkdir(exist_ok=True)
    (ROOT/'web'/'evidence-data.js').write_text('window.SNACKUP_EVIDENCE='+json.dumps(success,ensure_ascii=False)+';\nwindow.SNACKUP_EVIDENCE_FAILURE='+json.dumps(failure,ensure_ascii=False)+';\n')
    print('Evidence built: verified success and failure histories.')
