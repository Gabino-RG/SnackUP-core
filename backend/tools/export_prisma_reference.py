#!/usr/bin/env python3
"""Export a Prisma 7 reference from the authoritative SQLAlchemy metadata.

This tool never opens a database and does not install or invoke Prisma. Python
defaults are documented, not converted to SQL DEFAULTs or Prisma @updatedAt.
Alembic owns CHECK constraints and partial indexes that this reference explains
in comments. Run from backend with ``python tools/export_prisma_reference.py``;
``--check`` fails if the checked-in reference has drifted from the runtime models.
"""
from __future__ import annotations

import argparse
from importlib import import_module
import json
from pathlib import Path
import sys

from sqlalchemy import (Boolean, CheckConstraint, DateTime, ForeignKeyConstraint,
                        Integer, JSON, Numeric, String, Text, UniqueConstraint)

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

# Preserve the vocabulary of the supplied V3 schema while mapping every table
# that exists in the Python implementation, including the legacy workflows.
MODELS = {
    "users": "Usuario",
    "careers": "Carrera",
    "academic_groups": "GrupoAcademico",
    "academic_records": "RegistroInstitucional",
    "access_requests": "SolicitudAcceso",
    "access_decisions": "DecisionAcceso",
    "verification_tokens": "TokenVerificacion",
    "refresh_sessions": "RefreshToken",
    "devices": "Dispositivo",
    "businesses": "Negocio",
    "products": "Platillo",
    "orders": "Pedido",
    "order_items": "DetallePedido",
    "order_transitions": "EventoPedido",
    "product_reviews": "Resena",
    "reviews": "CalificacionNegocio",
    "followups": "SeguimientoOpinion",
    "followup_events": "EventoSeguimiento",
    "media_files": "Medio",
    "idempotency_records": "ClaveIdempotencia",
    "account_audit_events": "EventoAuditoriaCuenta",
    "outbox_events": "EventoSalida",
    "push_deliveries": "EntregaPush",
}

FIELDS = {
    "name": "nombre", "display_name": "nombre", "email": "correo",
    "password_hash": "passwordHash", "role": "rol", "business_id": "negocioId",
    "is_active": "estaActivo", "is_master": "esMaestro", "approval_status": "estadoAprobacion",
    "email_verified": "correoVerificado", "auth_version": "versionAutenticacion",
    "numero_de_control": "numeroDeControl", "avatar_url": "avatarUrl",
    "institutional_verified_at": "verificadoInstitucionalAt", "last_login_at": "ultimoLoginAt",
    "created_at": "createdAt", "updated_at": "updatedAt", "career_id": "carreraId",
    "group_id": "grupoId", "institutional_id": "identificadorInstitucional", "kind": "tipo",
    "source": "fuente", "user_id": "usuarioId", "request_id": "solicitudId",
    "actor_id": "actorId", "decision": "decision", "note": "nota", "requested_role": "rolSolicitado",
    "request_context": "contextoSolicitud", "provider": "proveedor", "reviewed_by": "revisorId",
    "decided_at": "decididoAt", "purpose": "proposito", "token_hash": "tokenHash",
    "expires_at": "expiraAt", "used_at": "utilizadoAt", "registration_data": "datosRegistro",
    "family_id": "familiaId", "rotated_at": "rotadoAt", "revoked_at": "revocadoAt",
    "device_id": "dispositivoId", "replaced_by_id": "reemplazadoPorId", "platform": "plataforma",
    "session_family_id": "familiaSesionId", "last_active_at": "ultimaActividadAt",
    "category": "categoria", "description": "descripcion", "image_url": "imagenUrl",
    "timezone": "zonaHoraria", "cafeteria_id": "cafeteriaId", "cafeteria_name": "nombreCafeteria",
    "is_open": "estaAbierto", "next_order_number": "siguienteNumeroPedido",
    "subcategory": "subcategoria", "preparation_minutes": "tiempoPreparacion", "calories": "calorias",
    "price": "precio", "is_available": "estaDisponible", "manual_available": "disponibilidadManual",
    "is_featured": "esDestacado", "is_deleted": "estaEliminado", "deleted_at": "eliminadoAt",
    "student_id": "alumnoId", "order_number": "numeroPedido", "status": "estado",
    "customer_name": "nombreAlumnoSnapshot", "customer_institutional_id": "numeroControlSnapshot",
    "payment_method": "metodoPago", "payment_status": "estadoPago", "pickup_code": "codigoQr",
    "scheduled_pickup_time": "recogidaProgramadaAt", "accepted_at": "aceptadoAt",
    "preparing_at": "preparandoAt", "ready_at": "listoAt", "completed_at": "entregadoAt",
    "cancelled_at": "canceladoAt", "cancel_reason": "motivoCancelacion", "cancel_notes": "notasCancelacion",
    "cancelled_by": "canceladoPorId", "cancelled_by_role": "canceladoPorRol",
    "stock_restored": "stockRestaurado", "verification_method": "metodoVerificacion",
    "verified_by": "verificadoPorId", "verified_at": "verificadoAt", "order_id": "pedidoId",
    "product_id": "platilloId", "quantity": "cantidad", "notes": "notas",
    "reserved_quantity": "cantidadReservada", "from_status": "estadoAnterior", "to_status": "estadoNuevo",
    "action": "accion", "actor_role": "actorRol", "payload": "datos", "rating": "puntuacion",
    "comment": "comentario", "food_rating": "puntuacionComida", "service_rating": "puntuacionServicio",
    "career_name": "nombreCarreraSnapshot", "group_name": "nombreGrupoSnapshot",
    "review_id": "calificacionId", "assignee": "responsable", "owner_id": "propietarioId",
    "filename": "claveAlmacenamiento", "mime_type": "tipoMime", "size": "tamanoBytes",
    "width": "ancho", "height": "alto", "key": "clave", "payload_hash": "hashSolicitud",
    "response_json": "respuesta", "target_type": "tipoRecurso", "target_id": "recursoId",
    "data": "datos", "event_id": "eventoId", "topic": "canal", "event_type": "tipo",
    "published_at": "publicadoAt", "publish_attempts": "intentosPublicacion", "last_error": "ultimoError",
    "next_attempt_at": "proximoIntentoAt", "outbox_event_id": "eventoSalidaId", "state": "estado",
    "attempts": "intentos", "locked_until": "bloqueadoHasta", "lease_id": "reservaId",
    "provider_message_id": "mensajeProveedorId", "sent_at": "enviadoAt",
}
FIELD_OVERRIDES = {
    ("product_reviews", "user_id"): "alumnoId",
    ("reviews", "user_id"): "alumnoId",
    ("order_items", "name"): "nombreSnapshot",
    ("order_items", "price"): "precioUnitario",
}

# (referencing table, FK columns): (forward relation, inverse relation).
# Cardinality comes from actual PK/UNIQUE constraints, never from DTO assumptions.
RELATIONS = {
    ("academic_groups", "career_id"): ("carrera", "grupos"),
    ("academic_records", "career_id"): ("carrera", "registrosInstitucionales"),
    ("academic_records", "group_id"): ("grupo", "registrosInstitucionales"),
    ("access_decisions", "request_id"): ("solicitud", "decision"),
    ("access_decisions", "user_id"): ("usuario", "decisionesRecibidas"),
    ("access_decisions", "actor_id"): ("actor", "decisionesEmitidas"),
    ("access_decisions", "business_id"): ("negocio", "decisionesAcceso"),
    ("access_requests", "user_id"): ("usuario", "solicitudAcceso"),
    ("access_requests", "reviewed_by"): ("revisor", "solicitudesRevisadas"),
    ("account_audit_events", "actor_id"): ("actor", "eventosAuditoria"),
    ("devices", "user_id"): ("usuario", "dispositivos"),
    ("followup_events", "review_id"): ("seguimiento", "eventos"),
    ("followup_events", "business_id"): ("negocio", "eventosSeguimiento"),
    ("followup_events", "actor_id"): ("actor", "eventosSeguimiento"),
    ("followups", "review_id"): ("calificacion", "seguimiento"),
    ("followups", "business_id"): ("negocio", "seguimientos"),
    ("idempotency_records", "user_id"): ("usuario", "clavesIdempotencia"),
    ("idempotency_records", "order_id"): ("pedido", "clavesIdempotencia"),
    ("media_files", "business_id"): ("negocio", "medios"),
    ("media_files", "owner_id"): ("propietario", "medios"),
    ("order_items", "order_id"): ("pedido", "detalles"),
    ("order_items", "product_id"): ("platillo", "detallesPedido"),
    ("order_transitions", "order_id"): ("pedido", "eventos"),
    ("order_transitions", "actor_id"): ("actor", "eventosPedido"),
    ("orders", "student_id"): ("alumno", "pedidos"),
    ("orders", "business_id"): ("negocio", "pedidos"),
    ("product_reviews", "order_id"): ("pedido", "resenas"),
    ("product_reviews", "product_id"): ("platillo", "resenas"),
    ("product_reviews", "user_id"): ("alumno", "resenas"),
    ("products", "business_id"): ("negocio", "platillos"),
    ("push_deliveries", "outbox_event_id"): ("eventoSalida", "entregasPush"),
    ("push_deliveries", "device_id"): ("dispositivo", "entregasPush"),
    ("push_deliveries", "user_id"): ("usuario", "entregasPush"),
    ("refresh_sessions", "user_id"): ("usuario", "refreshTokens"),
    ("refresh_sessions", "device_id"): ("dispositivo", "refreshTokens"),
    ("refresh_sessions", "replaced_by_id"): ("reemplazadoPor", "tokensReemplazados"),
    ("reviews", "order_id"): ("pedido", "calificacionNegocio"),
    ("reviews", "user_id"): ("alumno", "calificacionesNegocio"),
    ("reviews", "business_id"): ("negocio", "calificaciones"),
    ("reviews", "career_id"): ("carrera", "calificacionesNegocio"),
    ("reviews", "group_id"): ("grupo", "calificacionesNegocio"),
    ("users", "business_id"): ("negocio", "cuentasCocina"),
    ("verification_tokens", "user_id"): ("usuario", "tokensVerificacion"),
}

# Alembic names these new constraints explicitly while SQLAlchemy leaves them
# unnamed. Retain their deployed names without inventing new SQL constraints.
FK_NAMES = {
    ("refresh_sessions", "device_id"): "fk_refresh_sessions_device_id",
    ("refresh_sessions", "replaced_by_id"): "fk_refresh_sessions_replaced_by_id",
    ("media_files", "owner_id"): "fk_media_files_owner_id",
}
UNIQUE_NAMES = {("users", ("numero_de_control",)): "uq_users_numero_de_control"}

MODEL_NOTES = {
    "users": [
        "rol es VARCHAR: user -> ALUMNO, business -> COCINA, admin -> ADMIN; pending solo pertenece al flujo legacy.",
        "negocioId NO es único global: uq_active_business_operator limita solo operadores activos y aprobados.",
        "esMaestro conserva la protección administrativa existente; no es un cuarto rol público V3.",
    ],
    "academic_records": [
        "Padrón autorizado local. tipo student/staff y matrícula no los determina el cliente.",
        "La vinculación con Usuario usa correo en la aplicación; no existe una FK por correo en SQL.",
    ],
    "businesses": [
        "averageRating, totalRatings y totalOrders son agregados del DTO; no existen columnas cacheadas.",
        "ownerId del DTO deriva de la cuenta Cocina activa y aprobada; no existe administradorId en businesses.",
        "cuentasCocina es una relación plural en SQL; la restricción de operador vigente es parcial.",
    ],
    "products": [
        "averageRating y totalRatings/totalResenas se calculan desde product_reviews; no son columnas.",
        "stock NULL significa sin límite; disponibilidadManual conserva la pausa del operador al devolver stock.",
        "categoria es texto libre, sin enum PostgreSQL de categorías.",
    ],
    "orders": [
        "estado conserva pending/accepted/preparing/ready/completed/cancelled como VARCHAR con CHECK.",
        "isRated/fueCalificado se calcula por la existencia de reviews; no es una columna.",
        "codigoQr admite códigos históricos de hasta 32 caracteres; solo longitud 6 tiene unicidad parcial global.",
        "canceladoPorId y verificadoPorId son identificadores históricos TEXT sin FK, como en el ORM.",
        "stockRestaurado y DetallePedido.cantidadReservada previenen devoluciones duplicadas del inventario.",
        "subtotal permanece nullable para preservar filas históricas durante la transición.",
    ],
    "order_items": ["nombreSnapshot/precioUnitario son snapshots de venta; cantidadReservada registra la reserva real."],
    "reviews": [
        "Tabla histórica reviews = calificación del negocio, con carrera/grupo y seguimiento administrativo.",
        "puntuacion es nullable por compatibilidad histórica; los nuevos DTO exigen un entero 1..5.",
    ],
    "product_reviews": ["Reseña de producto comprado: unicidad por pedidoId + platilloId, distinta de reviews."],
    "media_files": [
        "propietarioId nullable preserva uploads legacy cuyo autor individual no está documentado.",
        "La URL pública deriva de public_origin + '/media/' + claveAlmacenamiento; no hay columna url.",
    ],
    "idempotency_records": [
        "El bloqueo/transacción SQL completa la solicitud; no existen columnas estado ni codigoHttp.",
        "pedidoId NO es único global en SQL; solo usuarioId + clave tiene unicidad.",
        "respuesta es un DTO privado y nunca debe publicarse como evento o registro de acceso.",
    ],
    "verification_tokens": [
        "datosRegistro contiene solo la intención temporal y, en recuperación pending, un hash; nunca contraseña plana.",
        "El consumo borra la intención; tokenHash almacena el hash de un token de un solo uso.",
    ],
    "refresh_sessions": [
        "tokenHash conserva solo el hash; familiaId permite revocar todos los sucesores ante replay.",
        "familiaId es una agrupación lógica sin tabla/FK propia; reemplazadoPor sí tiene FK autorreferencial.",
    ],
    "devices": [
        "El token crudo es privado. La unicidad SQL recae en tokenHash, no en un índice sobre token TEXT.",
        "familiaSesionId es una asociación lógica sin FK; logout elimina solo dispositivos de esa familia.",
    ],
    "account_audit_events": ["Auditoría de seguridad sin contraseñas, tokens ni códigos de retiro; recursoId es una referencia polimórfica sin FK."],
    "outbox_events": [
        "id es el consecutivo SQL interno; eventoId es el identificador público estable para deduplicación.",
        "La publicación registra intentos, error y próximo intento; payloads de eventos excluyen credenciales y pickupCode.",
    ],
    "push_deliveries": [
        "Una entrega durable por evento de outbox y dispositivo, con reintentos, reserva y resultado del proveedor.",
        "eventoSalidaId referencia el entero interno de outbox; eventoId duplica el ID público sin otra FK.",
        "sent significa aceptación del proveedor, no lectura o presentación por el sistema operativo.",
    ],
}

HEADER = """// SnackUP - referencia PostgreSQL / Prisma ORM 7 del backend Python/FastAPI.
// GENERADO: python tools/export_prisma_reference.py. Verificar: añadir --check.
// Fuente de autoridad: snackup/*.py (Base.metadata) + migrations/ (Alembic).
// No usar Prisma Migrate ni db push sobre esta base; Prisma no integra el runtime.
// Vocabulario adaptado del schema.prisma suministrado; @map/@@map conservan el SQL real.
// No se inventan enums PostgreSQL, unicidades globales, columnas agregadas ni FK históricas.
// Los IDs opacos de entidades/FK son TEXT. El outbox conserva su secuencia interna Int.
// Los defaults/onupdate de Python se documentan y NO se transforman en DEFAULT SQL.
// SQLAlchemy JSON corresponde a @db.Json, no al JsonB que Prisma usaría por omisión.
// TIMESTAMP WITH TIME ZONE sin precisión explícita conserva la precisión PostgreSQL 6.
// Los CHECK y los dos índices parciales se documentan al pie de su modelo; Alembic los mantiene.
// No se declara generator: este archivo permite validar/consultar la referencia sin generar cliente Node.
// Prisma 7 ubica URLs de conexión en prisma.config.ts; validate no necesita conexión.
// Referencias: https://www.prisma.io/docs/orm/v7/reference/prisma-schema-reference
// https://www.prisma.io/docs/orm/v7/prisma-schema/data-model/database-mapping

datasource db {
  provider     = "postgresql"
  relationMode = "foreignKeys"
}
"""


def metadata():
    for module in ("identity_models", "operation_models", "admin_models", "push_models", "review_models"):
        import_module("snackup." + module)
    from snackup.db import Base
    return Base.metadata


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def field_name(table, column):
    override = FIELD_OVERRIDES.get((table, column))
    if override:
        return override
    if column in FIELDS:
        return FIELDS[column]
    first, *rest = column.split("_")
    return first + "".join(part.title() for part in rest)


def scalar_type(column):
    datatype = column.type
    if isinstance(datatype, Text):
        return "String", "@db.Text"
    if isinstance(datatype, String):
        return "String", "@db.VarChar" + (f"({datatype.length})" if datatype.length is not None else "")
    if isinstance(datatype, Boolean):
        return "Boolean", "@db.Boolean"
    if isinstance(datatype, Integer):
        return "Int", "@db.Integer"
    if isinstance(datatype, DateTime):
        return "DateTime", "@db.Timestamptz(6)" if datatype.timezone else "@db.Timestamp(6)"
    if isinstance(datatype, Numeric):
        if datatype.precision is None or datatype.scale is None:
            raise ValueError(f"Numeric sin precisión explícita: {column}")
        return "Decimal", f"@db.Decimal({datatype.precision}, {datatype.scale})"
    if isinstance(datatype, JSON):
        return "Json", "@db.Json"
    raise ValueError(f"Tipo SQL aún no representado: {column}: {datatype}")


def columns_key(constraint):
    return tuple(column.name for column in constraint.columns)


def is_partial(index):
    return index.dialect_options["postgresql"].get("where") is not None


def unique_sets(table):
    result = {columns_key(table.primary_key)}
    result.update(columns_key(c) for c in table.constraints if isinstance(c, UniqueConstraint))
    result.update(tuple(c.name for c in index.columns) for index in table.indexes if index.unique and not is_partial(index))
    return result


def relation_fields(tables):
    fields = {table: [] for table in tables}
    observed = set()
    actions = {None: "NoAction", "NO ACTION": "NoAction", "RESTRICT": "Restrict", "CASCADE": "Cascade",
               "SET NULL": "SetNull", "SET DEFAULT": "SetDefault"}
    for table in tables.values():
        for constraint in sorted(table.foreign_key_constraints, key=columns_key):
            local = columns_key(constraint)
            key = (table.name, ",".join(local))
            observed.add(key)
            forward, inverse = RELATIONS[key]
            target = constraint.elements[0].column.table
            relation = table.name + "_" + "_".join(local)
            local_fields = ", ".join(field_name(table.name, col) for col in local)
            remote_fields = ", ".join(field_name(target.name, fk.column.name) for fk in constraint.elements)
            arguments = [quote(relation), f"fields: [{local_fields}]", f"references: [{remote_fields}]",
                         "onDelete: " + actions[constraint.ondelete], "onUpdate: " + actions[constraint.onupdate]]
            sql_name = constraint.name or FK_NAMES.get(key)
            if sql_name:
                arguments.append("map: " + quote(str(sql_name)))
            optional = "?" if any(table.c[col].nullable for col in local) else ""
            fields[table.name].append((forward, MODELS[target.name] + optional, "@relation(" + ", ".join(arguments) + ")"))
            reverse_type = MODELS[table.name] + ("?" if local in unique_sets(table) else "[]")
            fields[target.name].append((inverse, reverse_type, "@relation(" + quote(relation) + ")"))
    if observed != set(RELATIONS):
        raise ValueError("Actualiza RELATIONS para las claves foráneas añadidas o retiradas: " + str(observed ^ set(RELATIONS)))
    return fields


def app_default(default):
    if default is None:
        return None
    arg = default.arg
    if callable(arg):
        return getattr(arg, "__name__", type(arg).__name__) + "()"
    return json.dumps(arg, ensure_ascii=False, sort_keys=True, default=str)


def render_schema(model_metadata=None):
    model_metadata = model_metadata if model_metadata is not None else metadata()
    tables = model_metadata.tables
    if set(tables) != set(MODELS):
        raise ValueError("Actualiza MODELS para las tablas añadidas o retiradas: " + str(set(tables) ^ set(MODELS)))
    relations = relation_fields(tables)
    result = [HEADER.rstrip()]
    for name, model in MODELS.items():
        table = tables[name]
        lines = ["", ""] + ["// " + note for note in MODEL_NOTES.get(name, ())] + [f"model {model} {{"]
        pk = columns_key(table.primary_key)
        singular_unique = {}
        plural_unique = []
        for constraint in sorted((c for c in table.constraints if isinstance(c, UniqueConstraint)), key=columns_key):
            columns = columns_key(constraint)
            sql_name = str(constraint.name) if constraint.name else UNIQUE_NAMES.get((name, columns))
            if len(columns) == 1:
                singular_unique[columns[0]] = sql_name
            else:
                plural_unique.append((columns, sql_name))
        names = [field_name(name, c.name) for c in table.columns] + [entry[0] for entry in relations[name]]
        if len(set(names)) != len(names):
            raise ValueError(f"Nombres Prisma duplicados en {name}: {names}")
        for column in table.columns:
            if column.server_default is not None or column.server_onupdate is not None:
                raise ValueError(f"Añade traducción explícita del nuevo default SQL: {column}")
            default, onupdate = app_default(column.default), app_default(column.onupdate)
            notes = (["default=" + default] if default is not None else []) + (["onupdate=" + onupdate] if onupdate else [])
            if notes:
                lines.append("  // SQLAlchemy, aplicación (sin DEFAULT SQL): " + "; ".join(notes) + ".")
            datatype, native = scalar_type(column)
            attrs = []
            if pk == (column.name,):
                attrs.append("@id" + ("(map: " + quote(str(table.primary_key.name)) + ")" if table.primary_key.name else ""))
            if table._autoincrement_column is column:
                attrs.append("@default(autoincrement())")
            if column.name in singular_unique:
                sql_name = singular_unique[column.name]
                attrs.append("@unique" + ("(map: " + quote(sql_name) + ")" if sql_name else ""))
            attrs += ["@map(" + quote(column.name) + ")", native]
            lines.append(f"  {field_name(name, column.name)} {datatype}{'?' if column.nullable else ''} " + " ".join(attrs))
        if relations[name]:
            lines.append("")
            for field, datatype, attrs in sorted(relations[name]):
                lines.append(f"  {field} {datatype} {attrs}")
        lines.append("")
        if len(pk) > 1:
            extra = ", map: " + quote(str(table.primary_key.name)) if table.primary_key.name else ""
            lines.append("  @@id([" + ", ".join(field_name(name, col) for col in pk) + "]" + extra + ")")
        for columns, sql_name in plural_unique:
            extra = ", map: " + quote(sql_name) if sql_name else ""
            lines.append("  @@unique([" + ", ".join(field_name(name, col) for col in columns) + "]" + extra + ")")
        for index in sorted(table.indexes, key=lambda i: i.name):
            columns = tuple(getattr(expression, "name", None) for expression in index.expressions)
            if any(column not in table.c for column in columns):
                raise ValueError(f"Añade una traducción explícita del índice de expresión {index.name}")
            if is_partial(index):
                predicate = str(index.dialect_options["postgresql"]["where"])
                kind = "UNIQUE INDEX" if index.unique else "INDEX"
                lines.append(f"  // SQL/Alembic, índice parcial: {kind} {index.name} ({', '.join(columns)}) WHERE {predicate}.")
                lines.append("  // No convertir este predicado a @unique/@@unique global en Prisma.")
                continue
            directive = "unique" if index.unique else "index"
            lines.append("  @@" + directive + "([" + ", ".join(field_name(name, col) for col in columns)
                         + "], map: " + quote(index.name) + ")")
        for constraint in sorted((c for c in table.constraints if isinstance(c, CheckConstraint)),
                                 key=lambda c: (str(c.name or ""), str(c.sqltext))):
            label = str(constraint.name) if constraint.name else "sin nombre en metadata; PostgreSQL asigna el nombre"
            sql = " ".join(str(constraint.sqltext).split())
            lines.append(f"  // SQL/Alembic, CHECK [{label}]: {sql}.")
        lines += ["  @@map(" + quote(name) + ")", "}"]
        result.extend(lines)
    return "\n".join(result) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=BACKEND / "schema.prisma")
    parser.add_argument("--check", action="store_true", help="fallar si el archivo difiere del ORM")
    args = parser.parse_args(argv)
    content = render_schema()
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != content:
            print("La referencia Prisma no coincide con el ORM. Ejecuta python tools/export_prisma_reference.py.", file=sys.stderr)
            return 1
        print(f"Referencia Prisma actualizada: {len(MODELS)} modelos, {len(RELATIONS)} relaciones SQL.")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
        print(f"Referencia Prisma exportada: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
