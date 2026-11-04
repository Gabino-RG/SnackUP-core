#!/usr/bin/env python3
"""Render the real UI audit ledger as a standalone Spanish HTML report.

Python standard library only. Reads documentation and writes the HTML artifact;
never imports the backend, calls an API, or connects to a database.

Usage:
  python -B tools/render_real_ui_report.py
  python -B tools/render_real_ui_report.py --input docs/qa-real-ui-2026-11-04.json
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
from html import escape
import json
import os
from pathlib import Path
import re
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER = ROOT / "docs/qa-real-ui-2026-11-04.json"

LABELS = {
    "actions": "Acciones realizadas", "observed": "Resultado observado",
    "notEstablished": "Lo que esta observación no demuestra",
    "findingIds": "Hallazgos relacionados", "evidenceIds": "Evidencias",
    "evidenceId": "Evidencia", "sourceEvidenceIds": "Evidencias de origen",
    "sourceCorroboration": "Referencias al código",
    "impact": "Impacto", "fixOrRetest": "Corrección y repetición de la prueba",
    "observedViaUi": "Defecto observado desde la interfaz",
    "verificationLimits": "Límites de la verificación",
    "remainingChecks": "Comprobaciones pendientes", "inventoryIds": "Referencias al inventario",
    "nextUiCheck": "Siguiente comprobación desde UI", "scopeNote": "Alcance",
    "commentRef": "Comentario de referencia", "comments": "Comentarios",
    "businessRating": "Opinión del negocio", "productReview": "Reseña del platillo",
    "rating": "Estrellas", "metricsShown": "Métricas observadas",
    "reviews": "Opiniones", "average": "Promedio", "negative": "Opiniones negativas",
    "negativePercentage": "Porcentaje de negativas", "distribution": "Distribución",
    "career": "Carrera", "name": "Nombre", "businessReview": "Opinión del negocio",
    "stars": "Estrellas", "timeShownLocal": "Hora mostrada",
    "createdTimeShownLocal": "Hora de creación mostrada",
    "scheduledPickupTimeShownLocal": "Recogida programada mostrada",
    "aggregateContext": "Contexto del total", "ordersShown": "Pedidos mostrados",
    "amountShown": "Importe mostrado", "priorOrdersIncluded": "Pedidos anteriores incluidos",
    "newUiScenarioOrders": "Pedidos nuevos de este recorrido",
    "followup": "Seguimiento", "assignee": "Responsable", "inReviewNote": "Nota de revisión",
    "resolvedNote": "Nota de resolución", "inReviewTimeShownLocal": "Hora de seguimiento",
    "pendingCounters": "Evolución del contador de pendientes",
    "textFilter": "Texto buscado", "filterCombination": "Combinación de filtros",
    "viewport": "Tamaño de pantalla", "width": "Anchura", "height": "Altura",
    "themes": "Temas", "scope": "Alcance", "result": "Resultado",
    "message": "Mensaje", "restoredDraft": "Borrador recuperado",
    "automaticClosure": "Cierre automático", "timePicker": "Selector de hora",
    "newUiAutomaticExecutionVerified": "Nueva ejecución automática verificada en este recorrido",
    "configuredTime": "Hora configurada", "priorProcessedTime": "Cierre anterior",
    "priorProcessedDate": "Fecha ya procesada", "postponementError": "Respuesta a la prórroga",
    "readOnlyCorroboration": "Corroboración de solo lectura",
    "status": "Estado", "reason": "Motivo", "observation": "Observación",
    "finalPickupTimeoutMinutes": "Espera de recogida al terminar, en minutos",
    "finalBusinessOpen": "Local abierto al terminar",
    "order": "Pedido", "number": "Folio", "orderNumber": "Pedido",
    "createdDateLocal": "Fecha local", "product": "Producto", "quantity": "Cantidad",
    "unitPrice": "Precio unitario", "total": "Total", "orderTotal": "Total del pedido",
    "currency": "Moneda", "paymentMethod": "Forma de pago", "notes": "Indicaciones",
    "finalStatus": "Estado final", "cancelledByRole": "Cancelado desde",
    "cancellationReason": "Nota de cancelación", "kitchenVerification": "Comprobación en Cocina",
    "rawLabelShown": "Etiqueta que se mostró", "delivered": "Entregados",
    "cancelled": "Cancelados", "active": "Activos", "totalSold": "Ventas mostradas",
    "newBuildSuccessfulSendVerified": "Envío comprobado en la nueva compilación",
    "postSendDraftCacheCleanupVerified": "Borrador vacío comprobado después del envío",
    "screenshotObserved": "Se observó una captura durante la prueba",
    "screenshotPathCommunicated": "Se proporcionó archivo de captura",
    "stockShownAfterScenario": "Existencias mostradas tras el recorrido",
    "averageRatingShown": "Promedio mostrado", "coverage": "Cobertura",
    "observedSubset": "Subconjunto realmente observado",
    "execution": "Ejecución", "documentation": "Documentación",
    "newDataRule": "Origen de los datos nuevos", "priorData": "Datos anteriores",
    "evidenceType": "Tipo de evidencia", "screenshots": "Capturas adjuntas",
    "screenshotNote": "Disponibilidad de capturas", "viewportCoverage": "Cobertura visual",
    "inventoryPolicy": "Criterio de cobertura del inventario",
    "laterReadOnlyCorroboration": "Consulta de solo lectura posterior",
    "serviceFailureTesting": "Caídas reales y recuperación",
    "buildObservation": "Compilación utilizada",
    "staffReleaseBuild": "Compilación de Cocina y Administración",
    "studentUiEdited": "Código de Alumnos modificado",
    "studentUiModificationAuthorization": "Autorización para modificar Alumnos",
    "newStaffBuildChatSendAndPostSendDraftCleanupVerified": "Envío y limpieza de borrador en la nueva compilación",
    "qualification": "Alcance del estado registrado",
    "policy": "Criterio aplicado", "examplesPending": "Ejemplos concretos pendientes",
    "inconclusiveCases": "Casos sin conclusión", "inconclusiveActions": "Acciones sin conclusión",
    "verifiedFixedDefects": "Correcciones verificadas",
    "partiallyVerifiedFixes": "Correcciones verificadas parcialmente",
    "unfixedDefects": "Defectos pendientes", "classification": "Clasificación",
    "report": "Reporte de origen", "studentPassed": "Pruebas anteriores de Alumnos",
    "panelsPassed": "Pruebas anteriores de paneles", "totalPassed": "Total anterior",
    "authorization": "Autorización", "requiredAuthorization": "Autorización requerida",
    "source": "Fuente", "sources": "Fuentes", "sourceIds": "Referencias",
    "basis": "Fundamento", "title": "Descripción", "detail": "Detalle",
    "note": "Nota", "uiEvidence": "Evidencia UI", "evidence": "Evidencia",
    "limitations": "Limitaciones", "remainingCoverage": "Cobertura pendiente",
    "scopeAndConfigurationLimits": "Límites de alcance y configuración",
    "endingStateObserved": "Último estado observado",
    "viewportObservations": "Pantallas y tamaños observados",
}

STATUS = {
    "observed_as_expected": ("Observado según lo esperado", "good"),
    "defect_observed": ("Defecto observado", "bad"),
    "defects_observed": ("Defectos observados", "bad"),
    "observed_with_localization_defect": ("Observado con defecto de idioma", "bad"),
    "observed_with_presentation_defect": ("Observado con defecto de presentación", "bad"),
    "inconclusive": ("Sin conclusión", "warn"),
    "partially_observed_new_automatic_closure_not_executed": ("Parcial; no hubo un nuevo cierre automático", "warn"),
    "partial_pending_draft_cleanup_check": ("Parcial en ese momento; faltaba comprobar limpieza", "warn"),
    "fix_partially_verified": ("Corrección verificada parcialmente en ese momento", "warn"),
    "fix_verified_for_observed_cases": ("Corrección repetida en los casos observados", "good"),
    "fix_verified_for_reported_ui_cases": ("Corrección repetida en los casos registrados", "good"),
    "fixed_verified_for_reported_ui_cases": ("Corregido y repetido desde UI", "good"),
    "confirmed_not_fixed": ("Abierto", "bad"),
    "confirmed_fix_in_progress_not_retested": ("Corrección pendiente de repetir desde UI", "warn"),
    "pending": ("Pendiente", "warn"), "blocked": ("Bloqueado", "warn"),
    "partial": ("Cobertura parcial", "warn"),
    "partial_with_defect": ("Cobertura parcial con defecto", "warn"),
    "partial_with_localization_defect": ("Cobertura parcial con defecto de idioma", "warn"),
    "completed": ("Entregado en la aplicación", "good"),
    "cancelled": ("Cancelado", "neutral"),
}

ROLES = {
    "student": "Alumnos", "kitchen": "Cocina", "administrator": "Administración",
    "student_and_kitchen": "Alumnos y Cocina", "kitchen_and_student": "Cocina y Alumnos",
    "kitchen_and_administrator": "Cocina y Administración",
}

CSS = """
:root{--navy:#0b2947;--ink:#19344b;--muted:#51667a;--line:#d7e1e8;--bg:#f3f6f9;--teal:#006e63;--amber:#835400;--red:#a12d35}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:85px}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 system-ui,-apple-system,Segoe UI,sans-serif}
a{color:#006d80;text-underline-offset:3px;overflow-wrap:anywhere}a:hover{text-decoration-thickness:2px}
.skip{position:absolute;top:-60px;background:white;padding:10px}.skip:focus{top:0;z-index:9}
.hero{background:var(--navy);color:white;padding:48px max(24px,calc((100vw - 1180px)/2));border-bottom:5px solid #00a48f}
.eyebrow{color:#8cddd1;text-transform:uppercase;letter-spacing:.13em;font-size:.77rem;font-weight:750}
h1{font-size:clamp(2rem,4vw,3.2rem);line-height:1.15;letter-spacing:-.035em;margin:12px 0 20px;max-width:850px}
.lead{font-size:1.15rem;max-width:900px;color:#dce7f0}.hero a{color:#a9ebe2}
.topnav{position:sticky;top:0;background:#fffefb;z-index:5;border-bottom:1px solid var(--line);overflow-x:auto;white-space:nowrap}
.nav-inner{max-width:1230px;margin:auto;padding:14px 24px;display:flex;gap:24px}.topnav a{color:var(--navy);font-size:.9rem;font-weight:700;text-decoration:none}
main{max-width:1230px;margin:auto;padding:30px 24px 70px}section{margin-bottom:42px}h2{font-size:1.65rem;line-height:1.3;margin:0 0 15px;letter-spacing:-.02em}h3{font-size:1.1rem;line-height:1.4;margin:0 0 10px}h4{margin:12px 0 5px;font-size:.95rem}
p{margin:0 0 14px}ul,ol{padding-left:24px;margin:8px 0 15px}li+li{margin-top:6px}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}.grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}
.card,.record{background:white;border:1px solid var(--line);border-radius:15px;overflow:hidden}.card{padding:22px}.metric strong{font-size:2rem;display:block;color:var(--navy);line-height:1.2}.metric span{color:var(--muted);font-size:.91rem}
.metric small{display:block;color:var(--muted);margin-top:8px}.note{border-left:4px solid #008f80;padding:16px 20px;background:#e7f4f0;border-radius:5px;margin:16px 0}.note.warn{border-color:#c99320;background:#fff4d9}
.muted{color:var(--muted);font-size:.91rem}.badge{display:inline-block;border-radius:20px;padding:3px 10px;font-size:.75rem;font-weight:750;background:#edf1f5;color:#3f5469;white-space:normal;line-height:1.5}
.badge.good{background:#dff2e8;color:#145f42}.badge.bad{background:#fce6e7;color:#922833}.badge.warn{background:#fff1ce;color:#805400}
.id{font:700 .8rem ui-monospace,Consolas,monospace;color:#486379}.hero .id{color:#bbd6e8}.tagrow{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:0 0 8px}
.record{margin:12px 0}.record>summary{padding:19px 22px;cursor:pointer;display:list-item;list-style-position:inside}.record>summary h3{display:inline;font-size:1.04rem}.record>summary .summary-body{display:inline-block;max-width:calc(100% - 24px);vertical-align:top}
.record[open]>summary{border-bottom:1px solid var(--line);background:#f9fbfd}.record-body{padding:20px 24px}.record-body>.grid{gap:24px}.record:target{outline:3px solid #33b8a8;outline-offset:3px}
.subdetails{margin:12px 0;padding:12px 16px;background:#f5f8fb;border-radius:8px}.subdetails>summary{cursor:pointer;font-weight:650}
.fields{margin:0}.field{margin:0 0 15px}.field>dt{font-weight:700;font-size:.89rem;color:#3a566f}.field>dd{margin:4px 0 0;overflow-wrap:anywhere}.field-list{padding-left:20px}.field-list>li{margin-bottom:9px}.ref{font-size:.84rem;margin-right:8px;display:inline-block}
blockquote{margin:12px 0;padding:14px 18px;border-left:3px solid #00a48f;background:#f1f8f7;font-style:normal;overflow-wrap:anywhere}
.filters{display:flex;gap:10px;align-items:end;flex-wrap:wrap;margin:18px 0}.filters label{font-size:.85rem;font-weight:700;display:flex;flex-direction:column;gap:5px}.filters label:first-child{flex:1;min-width:220px}
input,select,button{font:inherit;color:var(--ink);border:1px solid #aebfcd;border-radius:8px;background:white;padding:9px 12px;min-height:44px}button{cursor:pointer;font-size:.88rem;font-weight:650}button:hover{background:#e9f4f2}input:focus,select:focus,button:focus,a:focus,summary:focus{outline:3px solid #46b9a9;outline-offset:3px}
code,pre{font: .84rem/1.5 ui-monospace,Consolas,monospace}code{background:#edf2f6;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#102c43;color:#e3eff8;padding:18px;border-radius:9px;max-height:520px;overflow:auto}
.small-links{display:flex;gap:16px;flex-wrap:wrap;font-size:.9rem}.flow{font-size:.86rem;color:var(--teal);font-weight:700;margin-top:14px}.order-number{font-size:1.7rem;font-weight:800;margin-bottom:5px;color:var(--navy)}
.footer{border-top:1px solid var(--line);padding-top:24px;color:var(--muted);font-size:.82rem}.hash{font-family:ui-monospace,Consolas,monospace;word-break:break-all;font-size:.72rem}
[hidden]{display:none!important}
@media(max-width:760px){.hero{padding:30px 20px}main{padding:24px 16px 45px}.grid,.grid.two{grid-template-columns:1fr}.card{padding:18px}.record>summary{padding:16px}.record-body{padding:16px}.nav-inner{padding:12px 16px;gap:20px}.filters label{flex:1;min-width:100%}.filters button{flex:1}h2{font-size:1.4rem}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
@media print{.topnav,.filters,.no-print{display:none}.hero{padding:20px;background:white;color:#19344b;border-bottom:2px solid #006e63}.hero .lead,.hero .eyebrow{color:#19344b}main{padding:20px 0}.card,.record{break-inside:avoid}body{background:white}pre{max-height:none}.grid{gap:10px}a{color:#19344b}}
"""

JS = """
const cards = Array.from(document.querySelectorAll('.evidence-record'));
function filterEvidence(){
  const term = document.getElementById('search').value.toLocaleLowerCase('es');
  const role = document.getElementById('role').value;
  let visible = 0;
  cards.forEach(card => {
    const matches = card.textContent.toLocaleLowerCase('es').includes(term) &&
      (!role || card.dataset.role.includes(role));
    card.hidden = !matches;
    if(matches) visible++;
  });
  document.getElementById('visible-count').textContent = 'Mostrando ' + visible + ' de ' + cards.length + ' registros de observación.';
}
document.getElementById('search').addEventListener('input',filterEvidence);
document.getElementById('role').addEventListener('change',filterEvidence);
document.getElementById('expand').addEventListener('click',()=>cards.filter(c=>!c.hidden).forEach(c=>c.open=true));
document.getElementById('collapse').addEventListener('click',()=>cards.forEach(c=>c.open=false));
function revealTarget(){
  const id = decodeURIComponent(location.hash.slice(1));
  const target = document.getElementById(id);
  if(!target) return;
  if(target.matches('details')) target.open = true;
  target.hidden = false;
  let parent = target.parentElement;
  while(parent){if(parent.matches('details')) parent.open=true;parent=parent.parentElement;}
}
window.addEventListener('hashchange',revealTarget);
revealTarget();
"""


def e(value) -> str:
    return escape(str(value), quote=True)


def label(key: str) -> str:
    return LABELS.get(key, re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", key).replace("_", " ").capitalize())


def status_info(value) -> tuple[str, str]:
    text = str(value or "")
    return STATUS.get(text, (text.replace("_", " ") or "Sin estado informado", "neutral"))


def badge(value) -> str:
    text, kind = status_info(value)
    return f'<span class="badge {kind}">{e(text)}</span>'


def is_verified_fix(finding: dict) -> bool:
    state = str(finding.get("status", ""))
    return state.startswith("fixed_verified_") or state.startswith("fix_verified_")


class Report:
    def __init__(self, ledger: dict, source: Path, output: Path, digest: str):
        self.data, self.source, self.output, self.digest = ledger, source, output, digest
        self.records = {row["id"]: row for row in ledger.get("evidence", [])}
        self.findings = ledger.get("findings", [])
        self.ids = set(self.records) | {row["id"] for row in self.findings}

    def link(self, path: str | Path, text: str | None = None) -> str:
        candidate = Path(path)
        if not candidate.is_absolute():
            candidate = ROOT / candidate
        try:
            relative = os.path.relpath(candidate.resolve(), self.output.parent.resolve()).replace("\\", "/")
            href = quote(relative, safe="/:.-_")
        except ValueError:
            href = candidate.resolve().as_uri()
        return f'<a href="{e(href)}">{e(text or str(path))}</a>'

    def refs(self, values) -> str:
        return " ".join(
            f'<a class="ref" href="#{e(value)}">{e(value)}</a>' if value in self.ids else f'<code>{e(value)}</code>'
            for value in values
        )

    def value(self, value, key: str = "") -> str:
        if value is None:
            return '<span class="muted">No informado</span>'
        if isinstance(value, bool):
            return "Sí" if value else "No"
        if isinstance(value, dict):
            if "file" in value and "line" in value:
                ref = self.link(value["file"], str(value["file"]) + ":" + str(value["line"]))
                return ref + (f'<p>{e(value["detail"])}</p>' if value.get("detail") else "")
            return '<dl class="fields">' + "".join(
                f'<div class="field"><dt>{e(label(k))}</dt><dd>{self.value(v,k)}</dd></div>' for k, v in value.items()
            ) + "</dl>"
        if isinstance(value, list):
            if not value:
                return '<span class="muted">Sin elementos registrados.</span>'
            if all(isinstance(v, str) and v in self.ids for v in value):
                return self.refs(value)
            return '<ul class="field-list">' + "".join(f"<li>{self.value(v,key)}</li>" for v in value) + "</ul>"
        if key == "status" or key == "result":
            return badge(value)
        if key in {"role", "cancelledByRole"}:
            return e(ROLES.get(str(value), str(value)))
        if str(value) in self.ids:
            return self.refs([str(value)])
        if key == "commentRef" and str(value).startswith("comments."):
            comment = self.data.get("comments", {}).get(str(value).split(".", 1)[1])
            return f"<blockquote>{e(comment)}</blockquote>" if comment else e(value)
        return e(value)

    def details(self, title: str, value, *, open_: bool = False) -> str:
        return f'<details class="subdetails"{" open" if open_ else ""}><summary>{e(title)}</summary>{self.value(value)}</details>'

    def evidence_card(self, row: dict) -> str:
        key = row["id"]
        extra = {k: v for k, v in row.items() if k not in {"id", "screen", "role", "result", "actions", "observed", "notEstablished"}}
        return (
            f'<details class="record evidence-record" id="{e(key)}" data-role="{e(row.get("role",""))}">'
            f'<summary><span class="summary-body"><span class="tagrow"><span class="id">{e(key)}</span>'
            f'<span class="badge">{e(ROLES.get(row.get("role"),row.get("role","Sin rol")))}</span>'
            f'{badge(row.get("result"))}</span><h3>{e(row.get("screen",key))}</h3></span></summary>'
            '<div class="record-body"><div class="grid two"><div><h4>Qué se hizo</h4>'
            f'{self.value(row.get("actions",[]))}</div><div><h4>Qué se observó</h4>'
            f'{self.value(row.get("observed",[]))}</div></div>'
            + (self.details("Límites de esta observación", row["notEstablished"]) if row.get("notEstablished") else "")
            + (self.details("Datos y referencias registrados", extra) if extra else "")
            + "</div></details>"
        )

    def finding_card(self, row: dict) -> str:
        fields = {k: v for k, v in row.items() if k not in {"id", "title", "severity", "status"}}
        return (
            f'<details class="record" id="{e(row["id"])}">'
            '<summary><span class="summary-body"><span class="tagrow">'
            f'<span class="id">{e(row["id"])}</span><span class="badge">{e(row.get("severity",""))}</span>'
            f'{badge(row.get("status"))}</span><h3>{e(row.get("title","Hallazgo"))}</h3></span></summary>'
            f'<div class="record-body">{self.value(fields)}</div></details>'
        )

    def scenarios(self) -> str:
        rows = [self.data.get("scenario", {})] + self.data.get("additionalScenarios", [])
        cards = []
        for row in rows:
            number = row.get("orderNumber", "?")
            state = row.get("finalStatus") or row.get("completion", "Sin estado informado")
            scope = ("Entrega y valoración del negocio desde las pantallas." if number == 4 else
                     "Recogida programada y cancelación desde Cocina." if number == 5 else
                     "Pedido inmediato y cancelación desde Alumnos." if number == 6 else "")
            fields = {k: v for k, v in row.items() if k != "orderNumber"}
            cards.append(
                f'<article class="card"><div class="order-number">Pedido #{e(number)}</div>{badge(state)}'
                f'<p class="flow">{e(scope)}</p>{self.details("Ver datos del pedido",fields)}</article>'
            )
        return '<div class="grid">' + "".join(cards) + "</div>"

    def highlights(self) -> str:
        metrics = self.records.get("UI-13", {}).get("metricsShown", {})
        reviews = metrics.get("reviews", "No informado")
        average = metrics.get("average", "No informado")
        comment = self.data.get("comments", {}).get("businessRating", "")
        filtered = self.records.get("UI-16", {})
        return (
            '<div class="grid two"><article class="card"><h3>Del pedido a Administración</h3>'
            f'<p>El pedido #4 se creó, preparó y entregó en la aplicación. La opinión del negocio llegó a Administración.</p>'
            f'<p><strong>{e(average)} de promedio · {e(reviews)} opiniones</strong>, incluyendo registros anteriores.</p>'
            f'<blockquote>{e(comment)}</blockquote><p>{self.refs(["UI-04","UI-05","UI-08","UI-10","UI-13"])}</p></article>'
            '<article class="card"><h3>Filtro de la opinión nueva</h3>'
            + self.value(filtered.get("observed", []))
            + f'<p>{self.refs(["UI-16"])}</p>'
            '<p class="muted">La reseña del platillo usa otro comentario y otro conjunto de registros; no se suma al promedio del negocio.</p>'
            + self.details("Comentario público del platillo", self.data.get("comments", {}).get("productReview", "No informado"))
            + "</article></div>"
        )

    def render(self) -> str:
        d = self.data
        fixed = [f for f in self.findings if is_verified_fix(f)]
        unresolved = [f for f in self.findings if not is_verified_fix(f)]
        coverage = d.get("remainingCoverage", {})
        evidence = d.get("evidence", [])
        mapped = coverage.get("mappedActionsWithSomeObservation", "—")
        total = coverage.get("inventoryActions", "—")
        unmapped = coverage.get("unmappedActions", "—")
        full = coverage.get("fullyCompletedInventoryActions", "—")
        end_state = d.get("endingStateObserved", {})
        created = datetime.now(timezone.utc).isoformat(timespec="seconds")
        intro = (
            '<header class="hero"><div class="eyebrow">SnackUP · Auditoría funcional local</div>'
            '<h1>Lo que se probó desde las pantallas y lo que falta</h1>'
            '<p class="lead">Recorridos reales de Alumnos, Cocina y Administración contra la API y PostgreSQL de la laptop. '
            'La validación sigue siendo parcial: este informe no certifica una aplicación terminada al 100% ni capacidad de producción.</p>'
            f'<p class="id">{e(d.get("date",""))} · {e(d.get("timezone",""))} · {e(d.get("applicationOrigin",""))}</p></header>'
        )
        navigation = '<nav class="topnav" aria-label="Secciones del informe"><div class="nav-inner">' + "".join(
            f'<a href="#{key}">{text}</a>' for key, text in [
                ("resumen","Resumen"),("metodo","Método"),("recorridos","Pedidos y opiniones"),
                ("hallazgos","Defectos y correcciones"),("pendientes","Pendientes"),
                ("evidencias","Evidencias"),("cobertura","Cobertura"),("fuentes","Fuentes")]
        ) + "</div></nav>"
        summary = (
            '<section id="resumen"><h2>Resultado de la revisión</h2><div class="grid">'
            f'<div class="card metric"><strong>{len(evidence)}</strong><span>registros de observación UI</span><small>No equivalen a botones únicos ni a pruebas aprobadas.</small></div>'
            f'<div class="card metric"><strong>{len(fixed)} / {len(self.findings)}</strong><span>defectos con corrección repetida desde UI</span><small>El alcance concreto de cada repetición se conserva abajo.</small></div>'
            f'<div class="card metric"><strong>{len(unresolved)}</strong><span>hallazgos aún sin cierre verificado</span><small>Estado derivado del registro actual, no de resultados anteriores.</small></div>'
            '</div><div class="note warn"><strong>Entrega con pendientes.</strong> '
            'Hay recorridos completos observados y correcciones comprobadas, pero quedan casos sin ejecutar, límites del entorno y cambios fuera del alcance autorizado.</div></section>'
        )
        method = (
            '<section id="metodo"><h2>Método y límites de la evidencia</h2>'
            '<div class="note"><strong>Acciones nuevas desde UI.</strong> Se usaron cuentas locales existentes y una base con datos anteriores. '
            'No se crearon los pedidos de este recorrido mediante nuevas semillas, fixtures ni escrituras API por scripts. '
            'Los scripts operativos de reinicio no ejecutan semillas por defecto.</div>'
            '<p>Las conexiones al backend y PostgreSQL son reales; las cuentas y el padrón son locales de prueba. '
            'No se acreditan personas de la universidad, cobros, preparación o entrega física de comida ni calidad del alimento.</p>'
            + self.details("Método completo registrado", d.get("method", {}))
            + self.details("Cuentas locales utilizadas", d.get("actors", {}))
            + '<p class="muted">No se adjuntan capturas sin archivo comunicado. La evidencia presentada es el relato de observaciones de interfaz registrado en el JSON.</p></section>'
        )
        scenarios = '<section id="recorridos"><h2>Tres pedidos nuevos; resultados distintos</h2>' + self.scenarios() + '<div style="height:18px"></div>' + self.highlights() + "</section>"
        fixes = '<section id="hallazgos"><h2>Defectos y correcciones</h2><p>Este es el estado más reciente de cada hallazgo. Las observaciones antiguas se conservan en las evidencias y no se reinterpretan como pruebas de la nueva compilación.</p>'
        fixes += "".join(self.finding_card(row) for row in self.findings)
        fixes += (
            '<article class="card"><h3>Arranque sin semillas automáticas</h3><p>'
            + self.link("tools/start_integrated_local.ps1", "El script de inicio")
            + ' utiliza <code>-SeedDemoData</code> solo como opción explícita. El reinicio habitual retoma la base existente y no repone datos de demostración. '
            'Este cambio operativo se documenta por separado de los defectos de interfaz.</p><p>'
            + self.link("INTEGRACION_LOCAL.md", "Guía de integración y política activa de pruebas")
            + "</p></article></section>"
        )
        pending = '<section id="pendientes"><h2>Lo que todavía requiere trabajo</h2>'
        if unresolved:
            pending += '<div class="card"><h3>Hallazgos abiertos o sin repetición final</h3><ul>'
            for row in unresolved:
                pending += f'<li><a href="#{e(row["id"])}">{e(row["id"])} · {e(row.get("title",""))}</a> — {e(status_info(row.get("status"))[0])}</li>'
            pending += "</ul></div>"
        pending += self.details("Pruebas pendientes concretas", coverage.get("examplesPending", []), open_=True)
        if d.get("scopeAndConfigurationLimits"):
            pending += self.details("Límites de configuración y alcance: no son pruebas UI ejecutadas", d["scopeAndConfigurationLimits"], open_=True)
        pending += self.details("Limitaciones del resultado", d.get("limitations", []))
        pending += '<p class="muted">SMTP, OAuth, push, interfaz de chat de Alumnos, capacidad para 1,000 usuarios y servidor final deben evaluarse conforme a su alcance documentado. Véase '
        pending += self.link("docs/qa-environment-limits.json", "el análisis de límites") + '; su inventario no demuestra ejecución de esas funciones.</p></section>'
        evidence_html = (
            '<section id="evidencias"><h2>Evidencias del recorrido</h2>'
            '<p>Abre un registro para ver qué se hizo, qué se observó y qué quedó sin establecer. Los estados parciales describen ese momento; la resolución más reciente está en Defectos y correcciones.</p>'
            f'<details class="subdetails"><summary>Explorar los {len(evidence)} registros de observación</summary>'
            '<div class="filters"><label>Buscar<input id="search" type="search" placeholder="Pedido, comentario, UI-57, cierre…"></label>'
            '<label>Rol<select id="role"><option value="">Todos</option><option value="student">Alumnos</option><option value="kitchen">Cocina</option><option value="administrator">Administración</option></select></label>'
            '<button id="expand" type="button">Expandir visibles</button><button id="collapse" type="button">Contraer</button></div>'
            f'<p class="muted" id="visible-count" aria-live="polite">Mostrando {len(evidence)} de {len(evidence)} registros de observación.</p>'
            + "".join(self.evidence_card(row) for row in evidence) + "</details></section>"
        )
        coverage_html = (
            '<section id="cobertura"><h2>Cobertura y último estado</h2>'
            f'<div class="note warn"><strong>{e(mapped)} de {e(total)} acciones del inventario de Alumnos tienen alguna observación vinculada.</strong> '
            f'Quedan {e(unmapped)} sin observación vinculada. El registro declara {e(full)} acciones compuestas completamente cerradas. No es un porcentaje de aplicación terminada.</div>'
            '<p>También falta recorrer controles y variantes locales, completar la matriz móvil/PC y resolver los hallazgos abiertos. Estos pendientes no dependen todos de recibir el servidor.</p>'
            + self.details("Mapeo parcial al inventario de Alumnos", d.get("studentInventoryMapping", []))
            + self.details("Pantallas y tamaños realmente observados", d.get("viewportObservations", []), open_=True)
            + self.details("Último estado observado al terminar", end_state)
            + self.details("Automatización anterior: separada de esta auditoría UI", d.get("priorAutomation", {}))
            + self.details("Criterios y conteos de cobertura del registro", coverage)
            + "</section>"
        )
        known = {"schemaVersion","date","timezone","acceptanceStatus","applicationOrigin","method","actors","scenario","comments","evidence","findings","studentInventoryMapping","remainingCoverage","priorAutomation","limitations","viewportObservations","endingStateObserved","additionalScenarios","scopeAndConfigurationLimits"}
        extra = {key:value for key,value in d.items() if key not in known}
        if extra:
            coverage_html += '<section><h2>Actualizaciones adicionales del registro</h2>' + self.value(extra) + "</section>"
        sources = (
            '<section id="fuentes"><h2>Fuentes y actualización</h2><div class="card"><div class="small-links">'
            + self.link(self.source, "Registro JSON de esta auditoría")
            + self.link("docs/qa-paneles-inventory.json", "Inventario de paneles")
            + self.link("docs/qa-alumnos-inventory.json", "Inventario de Alumnos")
            + self.link("docs/qa-environment-limits.json", "Límites del entorno")
            + self.link("INTEGRACION_LOCAL.md", "Guía local")
            + '</div><p class="muted" style="margin-top:16px">Los inventarios son planes trazables; no deben presentarse como controles ya ejecutados. Las fuentes de código de cada defecto aparecen dentro de su detalle cuando el registro las proporciona.</p>'
            '<p>Para regenerar este HTML después de actualizar el registro, desde la raíz del repositorio:</p>'
            '<pre>python -B tools/render_real_ui_report.py</pre>'
            '<p class="muted">El conversor usa únicamente la biblioteca estándar de Python, lee documentación y escribe este HTML. No se conecta a la API ni a PostgreSQL y no ejecuta pruebas o semillas.</p></div></section>'
        )
        footer = (
            f'<footer class="footer">Generado: {e(created)} · Fecha del registro: {e(d.get("date",""))}. '
            f'<p>Estado literal del registro: <code>{e(d.get("acceptanceStatus","No informado"))}</code></p>'
            f'<p class="hash">SHA-256 del JSON utilizado: {self.digest}</p></footer>'
        )
        return (
            '<!doctype html><html lang="es-MX"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
            '<meta name="color-scheme" content="light"><meta name="referrer" content="no-referrer">'
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; script-src \'unsafe-inline\'; img-src \'self\' data:; base-uri \'none\'; form-action \'none\'">'
            f'<title>SnackUP · Auditoría UI · {e(d.get("date",""))}</title><style>{CSS}</style></head><body>'
            '<a class="skip" href="#resumen">Ir al resultado</a>'
            + intro + navigation + "<main>" + summary + method + scenarios + fixes + pending
            + evidence_html + coverage_html + sources + footer + f"</main><script>{JS}</script></body></html>\n"
        )


def validate_ledger(data: object) -> None:
    if not isinstance(data, dict):
        raise ValueError("El registro debe ser un objeto JSON.")
    seen = set()
    for key in ("evidence", "findings"):
        records = data.get(key)
        if not isinstance(records, list):
            raise ValueError(f"Falta la lista {key}.")
        for row in records:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                raise ValueError(f"Registro inválido en {key}.")
            identifier = row["id"]
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", identifier) or identifier in seen:
                raise ValueError("Identificador inválido o duplicado en el registro.")
            seen.add(identifier)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_LEDGER, help="Registro JSON de observaciones")
    parser.add_argument("--output", type=Path, help="HTML de salida; por defecto usa el nombre del JSON")
    args = parser.parse_args()
    source = args.input.resolve()
    output = (args.output or source.with_suffix(".html")).resolve()
    if output == source or output.suffix.lower() != ".html":
        parser.error("La salida debe ser un HTML distinto del registro JSON.")
    payload = source.read_bytes()
    data = json.loads(payload.decode("utf-8-sig"))
    validate_ledger(data)
    report = Report(data, source, output, hashlib.sha256(payload).hexdigest())
    rendered = report.render()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    states = Counter("verified" if is_verified_fix(f) else "pending" for f in data["findings"])
    print(f"HTML generado: {output}")
    print(f"Observaciones UI: {len(data['evidence'])}; correcciones verificadas: {states['verified']}; hallazgos pendientes: {states['pending']}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
