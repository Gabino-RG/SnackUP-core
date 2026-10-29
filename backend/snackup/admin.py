"""REST administration, authorized account assignment and student reviews."""
from .auth import request_user


import math

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy import func, literal, or_, select, union_all
from sqlalchemy.orm import Session

from .admin_models import AccessDecision, Followup, FollowupEvent, Review
from .auth import current_user, ensure_account, hash_password, require_admin, require_master, require_student, revoke_user_sessions
from .common import iso, page_result, require, validate_body, version_check
from .db import emit_event, get_db, new_id, utcnow
from .identity import normalize_email, queue_verification, serialize_access_request, serialize_user
from .identity_models import AcademicGroup, AcademicRecord, AccessRequest, Career, User
from .operations import business_dict
from .operation_models import Business, Order

router = APIRouter()


def review_dict(row: Review) -> dict:
    # No name, email, institutional ID, user ID or order ID in admin DTOs.
    return {
        "id": row.id, "businessId": row.business_id, "rating": row.rating,
        "foodRating": row.food_rating, "serviceRating": row.service_rating,
        "careerId": row.career_id, "groupId": row.group_id,
        "career": row.career_name, "group": row.group_name,
        "comment": row.comment, "createdAt": iso(row.created_at),
    }


def followup_dict(row: Followup | FollowupEvent) -> dict:
    result = {
        "reviewId": row.review_id, "businessId": row.business_id,
        "status": row.status, "assignee": row.assignee, "note": row.note,
        "version": row.version, "updatedAt": iso(row.updated_at),
    }
    if isinstance(row, FollowupEvent):
        result.update(id=row.id, actorId=row.actor_id)
    return result


def _domains(settings) -> list[str]:
    return [x.strip().lower() for x in settings.admin_email_domains.split(",") if x.strip()]


def _nonblank(value: str, label: str) -> str:
    value = value.strip()
    require(bool(value), 422, "INVALID_INPUT", f"{label} no puede estar vacío.")
    return value


def _lock_admins(db: Session) -> list[User]:
    # Serialize the rare account-management operations, not student traffic.
    # Prevent two admins being removed concurrently based on a stale count.
    return list(db.scalars(select(User).where(User.role == "admin", User.is_active.is_(True))
                           .order_by(User.id).with_for_update().execution_options(populate_existing=True)))


def _assignment(db: Session, settings, *, role: str, email: str,
                business_id: str | None, active: bool, exclude_user: str | None = None):
    if role == "admin":
        require(email.rsplit("@", 1)[-1] in _domains(settings), 422,
                "INSTITUTIONAL_EMAIL_REQUIRED", "Utiliza un correo institucional autorizado.")
        require(business_id is None, 422, "INVALID_INPUT", "Administración no tiene un local asignado.")
        return None
    require(bool(business_id), 422, "BUSINESS_REQUIRED", "Selecciona un local.")
    business = db.scalar(select(Business).where(Business.id == business_id).with_for_update())
    require(business is not None and (business.is_active or not active), 422,
            "BUSINESS_REQUIRED", "Selecciona un local habilitado.")
    if active:
        occupied = select(User.id).where(User.role == "business", User.is_active.is_(True),
                                         User.approval_status == "approved", User.business_id == business_id)
        if exclude_user:
            occupied = occupied.where(User.id != exclude_user)
        require(db.scalar(occupied.limit(1)) is None, 409, "BUSINESS_ALREADY_ASSIGNED",
                "El local ya tiene una cuenta operadora activa.")
    return business_id


@router.get("/institution", operation_id="getInstitution")
def institution(request: Request, actor: User = Depends(request_user)):
    settings = request.app.state.settings
    return {
        "university": {"id": settings.institution_id, "name": settings.institution_name},
        "cafeteria": {"id": settings.cafeteria_id, "name": settings.cafeteria_name},
        "adminEmailDomains": _domains(settings),
    }


@router.get("/admin/users", operation_id="listUsers")
def list_users(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200), q: str = "",
               actor: User = Depends(require_master), db: Session = Depends(get_db, scope="function")):
    stmt = select(User)
    if q.strip():
        search = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        stmt = stmt.where(or_(User.display_name.ilike(f"%{search}%", escape="\\"),
                              User.email.ilike(f"%{search}%", escape="\\")))
    return page_result(db, stmt.order_by(User.created_at.desc(), User.id), serialize_user, page, limit)


@router.post("/admin/users", status_code=201, operation_id="createUser")
def create_user(request: Request, data: dict = Body(...), actor: User = Depends(require_master),
                db: Session = Depends(get_db, scope="function")):
    validate_body("createUser", data)
    _lock_admins(db)
    ensure_account(actor, db)
    email = normalize_email(data["email"])
    require(db.scalar(select(User.id).where(User.email == email)) is None, 409,
            "EMAIL_EXISTS", "Ya existe una cuenta con ese correo.")
    business_id = _assignment(db, request.app.state.settings, role=data["role"], email=email,
                              business_id=data["businessId"], active=data["isActive"])
    now = utcnow()
    user = User(id=new_id(), display_name=_nonblank(data["displayName"], "El nombre"), email=email,
                role=data["role"], business_id=business_id, is_active=data["isActive"],
                is_master=False, approval_status="approved", email_verified=False,
                password_hash=hash_password(data["password"]), version=1, auth_version=1,
                created_at=now, updated_at=now)
    db.add(user)
    db.flush()
    queue_verification(db, user, request.app.state.settings, mailer=getattr(request.app.state, "mailer", None))
    return serialize_user(user)


@router.patch("/admin/users/{id}", operation_id="updateUser")
def update_user(id: str, request: Request, data: dict = Body(...), actor: User = Depends(require_master),
                db: Session = Depends(get_db, scope="function")):
    validate_body("updateUser", data)
    admins = _lock_admins(db)
    ensure_account(actor, db)
    user = db.scalar(select(User).where(User.id == id).with_for_update())
    require(user is not None, 404, "USER_NOT_FOUND", "La cuenta no existe.")
    version_check(user, data["expectedVersion"])
    require(user.approval_status == "approved", 409, "APPROVAL_REQUIRED",
            "Utiliza el flujo de solicitudes para autorizar esta cuenta.")
    role, active = data["role"], data["isActive"]
    if user.is_master:
        require(role == "admin" and active, 403, "MASTER_PROTECTED", "La cuenta maestra debe permanecer activa.")
    if user.id == actor.id:
        require(role == actor.role and active, 403, "SELF_ACCESS_CHANGE", "No puedes retirar tu propio acceso.")
    if user.role == "admin" and (role != "admin" or not active):
        require(any(x.id != user.id for x in admins), 409, "LAST_ADMIN", "Debe conservarse un administrador activo.")
    email = normalize_email(data["email"])
    require(db.scalar(select(User.id).where(User.email == email, User.id != id)) is None,
            409, "EMAIL_EXISTS", "Ya existe una cuenta con ese correo.")
    business_id = _assignment(db, request.app.state.settings, role=role, email=email,
                              business_id=data["businessId"], active=active, exclude_user=user.id)
    changed_email = user.email != email
    user.display_name = _nonblank(data["displayName"], "El nombre")
    user.email, user.role, user.business_id, user.is_active = email, role, business_id, active
    if changed_email:
        user.email_verified = False
    user.version += 1
    user.updated_at = utcnow()
    revoke_user_sessions(db, user)
    db.flush()
    if changed_email:
        queue_verification(db, user, request.app.state.settings, mailer=getattr(request.app.state, "mailer", None))
    return serialize_user(user)


@router.get("/admin/access-requests", operation_id="listAccessRequests")
def list_access_requests(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                         actor: User = Depends(require_master), db: Session = Depends(get_db, scope="function")):
    return page_result(db, select(AccessRequest).where(AccessRequest.approval_status == "pending")
                       .order_by(AccessRequest.created_at, AccessRequest.id), serialize_access_request, page, limit)


@router.post("/admin/access-requests/{id}/decision", operation_id="decideAccessRequest")
def decide_access(id: str, request: Request, data: dict = Body(...), actor: User = Depends(require_master),
                  db: Session = Depends(get_db, scope="function")):
    validate_body("decideAccessRequest", data)
    _lock_admins(db)
    ensure_account(actor, db)
    # Read only the target ID first. Verification also locks User before its
    # AccessRequest; reversing those locks can deadlock approval against email
    # confirmation. Re-read the request after obtaining the account lock.
    target_id = db.scalar(select(AccessRequest.user_id).where(AccessRequest.id == id))
    require(target_id is not None, 404, "REQUEST_NOT_FOUND", "La solicitud no existe.")
    user = db.scalar(select(User).where(User.id == target_id).with_for_update()
                     .execution_options(populate_existing=True))
    access = db.scalar(select(AccessRequest).where(AccessRequest.id == id).with_for_update()
                       .execution_options(populate_existing=True))
    require(access is not None, 404, "REQUEST_NOT_FOUND", "La solicitud no existe.")
    require(access.approval_status == "pending", 409, "REQUEST_ALREADY_REVIEWED", "La solicitud ya fue revisada.")
    version_check(access, data["expectedVersion"])
    require(user is not None and user.approval_status == "pending", 409,
            "REQUEST_ALREADY_REVIEWED", "La solicitud ya fue revisada.")
    now = utcnow()
    if data["decision"] == "approve":
        require(data["identityConfirmed"], 422, "IDENTITY_CONFIRMATION_REQUIRED", "Confirma la identidad de la persona.")
        require(access.email_verified and user.email_verified, 422, "EMAIL_NOT_VERIFIED", "La persona debe verificar su correo.")
        business_id = _assignment(db, request.app.state.settings, role=data["role"], email=user.email,
                                  business_id=data["businessId"], active=True, exclude_user=user.id)
        user.role, user.business_id, user.is_active = data["role"], business_id, True
        user.approval_status = "approved"
    else:
        user.role, user.business_id, user.is_active, user.approval_status = "pending", None, False, "rejected"
    user.is_master = False
    user.version += 1
    user.updated_at = now
    revoke_user_sessions(db, user)
    access.approval_status = user.approval_status
    access.version += 1
    access.reviewed_by, access.note, access.decided_at = actor.id, data["note"], now
    db.add(AccessDecision(request_id=access.id, user_id=user.id, actor_id=actor.id, decision=data["decision"],
                          role=user.role, business_id=user.business_id, note=data["note"], created_at=now))
    db.flush()
    return serialize_user(user)


@router.get("/admin/academic-catalog", operation_id="listAcademicCatalog")
def academic_catalog(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                     actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    # Include retired catalog references: old reviews retain their original IDs.
    entries = union_all(
        select(Career.id.label("id"), literal("career").label("kind"), Career.name.label("name"), literal(None).label("career_id")),
        select(AcademicGroup.id, literal("group"), AcademicGroup.name, AcademicGroup.career_id),
    ).subquery()
    total = db.scalar(select(func.count()).select_from(entries)) or 0
    rows = db.execute(select(entries).order_by(entries.c.kind, entries.c.name, entries.c.id)
                      .offset((page - 1) * limit).limit(limit)).mappings()
    data = [{"id": x["id"], "kind": x["kind"], "name": x["name"],
             **({"careerId": x["career_id"]} if x["kind"] == "group" else {})} for x in rows]
    return {"data": data, "pagination": {"page": page, "limit": limit, "total": total, "totalPages": math.ceil(total / limit)}}


@router.get("/admin/businesses", operation_id="listAdminBusinesses")
def list_businesses(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200), q: str = "",
                    actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    stmt = select(Business)
    if q.strip():
        search = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        stmt = stmt.where(Business.name.ilike(f"%{search}%", escape="\\"))
    return page_result(db, stmt.order_by(Business.name, Business.id), business_dict, page, limit)


@router.post("/admin/businesses", status_code=201, operation_id="createBusiness")
def create_business(request: Request, data: dict = Body(...), actor: User = Depends(require_admin),
                    db: Session = Depends(get_db, scope="function")):
    validate_body("createBusiness", data)
    settings = request.app.state.settings
    require(data["cafeteriaId"] == settings.cafeteria_id, 422, "INVALID_INPUT", "La cafetería no existe.")
    now = utcnow()
    business = Business(id=new_id(), name=_nonblank(data["name"], "El nombre"), category=data["category"].strip(),
                        description=data["description"].strip(), timezone=data["timezone"],
                        cafeteria_id=settings.cafeteria_id, cafeteria_name=settings.cafeteria_name,
                        is_active=data["isActive"], is_open=False, version=1,
                        next_order_number=1, created_at=now, updated_at=now)
    db.add(business)
    db.flush()
    return business_dict(business)


@router.patch("/admin/businesses/{id}", operation_id="updateAdminBusiness")
def update_business(id: str, request: Request, data: dict = Body(...), actor: User = Depends(require_admin),
                    db: Session = Depends(get_db, scope="function")):
    validate_body("updateAdminBusiness", data)
    business = db.scalar(select(Business).where(Business.id == id).with_for_update())
    require(business is not None, 404, "BUSINESS_NOT_FOUND", "El local no existe.")
    version_check(business, data["expectedVersion"])
    require(data.get("cafeteriaId", business.cafeteria_id) == business.cafeteria_id, 422,
            "INVALID_INPUT", "No se puede trasladar el local a otra cafetería.")
    if not data["isActive"]:
        active = db.scalar(select(Order.id).where(Order.business_id == id,
                         Order.status.in_(("pending", "accepted", "preparing", "ready"))).limit(1))
        require(active is None, 409, "BUSINESS_HAS_ACTIVE_ORDERS", "Resuelve los pedidos activos antes de deshabilitar el local.")
        business.is_open = False
    business.name = _nonblank(data["name"], "El nombre")
    business.category, business.description = data["category"].strip(), data["description"].strip()
    business.is_active = data["isActive"]
    business.version += 1
    business.updated_at = utcnow()
    db.flush()
    emit_event(db, f"business:{business.id}", "business.updated", {"businessId": business.id, "version": business.version})
    return business_dict(business)


@router.get("/admin/reviews", operation_id="listReviews")
def list_reviews(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                 actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    return page_result(db, select(Review).order_by(Review.created_at.desc(), Review.id), review_dict, page, limit)


@router.get("/admin/followups", operation_id="listFollowups")
def list_followups(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                   actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    return page_result(db, select(Followup).order_by(Followup.updated_at.desc(), Followup.review_id), followup_dict, page, limit)


def _get_review(db: Session, id: str, *, lock: bool = False) -> Review:
    stmt = select(Review).where(Review.id == id)
    row = db.scalar(stmt.with_for_update() if lock else stmt)
    require(row is not None, 404, "REVIEW_NOT_FOUND", "La opinión no existe.")
    return row


@router.get("/admin/reviews/{id}/followup", operation_id="getFollowup")
def get_followup(id: str, actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    _get_review(db, id)
    row = db.get(Followup, id)
    require(row is not None, 404, "FOLLOWUP_NOT_FOUND", "La opinión aún no tiene seguimiento.")
    return followup_dict(row)


@router.put("/admin/reviews/{id}/followup", operation_id="saveFollowup")
def save_followup(id: str, data: dict = Body(...), actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    validate_body("saveFollowup", data)
    review = _get_review(db, id, lock=True)
    row = db.scalar(select(Followup).where(Followup.review_id == id).with_for_update())
    expected = data["expectedVersion"]
    if row is None:
        require(expected == 0, 409, "VERSION_CONFLICT", "El seguimiento cambió; vuelve a consultarlo.")
        row = Followup(review_id=id, business_id=review.business_id, version=1)
        db.add(row)
    else:
        version_check(row, expected)
        row.version += 1
    row.status = data["status"]
    row.assignee = _nonblank(data["assignee"], "El responsable")
    row.note = _nonblank(data["note"], "La nota")
    row.updated_at = utcnow()
    db.flush()
    db.add(FollowupEvent(review_id=id, business_id=review.business_id, actor_id=actor.id,
                         status=row.status, assignee=row.assignee, note=row.note,
                         version=row.version, updated_at=row.updated_at))
    db.flush()
    return followup_dict(row)


@router.get("/admin/reviews/{id}/followup/history", operation_id="getFollowupHistory")
def followup_history(id: str, page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                      actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    _get_review(db, id)
    return page_result(db, select(FollowupEvent).where(FollowupEvent.review_id == id)
                       .order_by(FollowupEvent.version.desc(), FollowupEvent.id), followup_dict, page, limit)


@router.post("/student/orders/{id}/review", status_code=201, operation_id="createStudentReview")
def create_student_review(id: str, data: dict = Body(...), actor: User = Depends(require_student),
                           db: Session = Depends(get_db, scope="function")):
    return create_review_record(id, data, actor, db)


def create_review_record(id, data, actor, db, *, minimum=1):
    require(set(data) <= {"rating", "foodRating", "serviceRating", "comment"}, 422,
            "INVALID_INPUT", "La carrera y el grupo se obtienen del padrón institucional.")
    require(type(data.get("rating")) is int and minimum <= data["rating"] <= 5,
            422, "INVALID_INPUT", "La calificación debe ser un entero del 1 al 5.")
    for field in ("foodRating", "serviceRating"):
        value = data.get(field)
        require(value is None or (type(value) is int and minimum <= value <= 5), 422,
                "INVALID_INPUT", "Las calificaciones deben ser enteros del 1 al 5 o null.")
    comment = data.get("comment", "")
    require(isinstance(comment, str) and len(comment) <= 2000, 422, "INVALID_INPUT", "El comentario admite hasta 2000 caracteres.")
    order = db.scalar(select(Order).where(Order.id == id, Order.student_id == actor.id).with_for_update())
    require(order is not None, 404, "ORDER_NOT_FOUND", "El pedido no existe.")
    require(order.status == "completed", 409, "ORDER_NOT_COMPLETED", "Solo puedes evaluar pedidos entregados.")
    require(db.scalar(select(Review.id).where(Review.order_id == id)) is None, 409,
            "REVIEW_EXISTS", "Este pedido ya tiene una opinión.")
    academic = db.scalar(select(AcademicRecord).where(AcademicRecord.email == actor.email,
                         AcademicRecord.kind == "student", AcademicRecord.is_active.is_(True)))
    require(academic is not None, 403, "INSTITUTIONAL_RECORD_REQUIRED", "Se requiere un registro académico vigente.")
    career = db.get(Career, academic.career_id) if academic.career_id else None
    group = db.get(AcademicGroup, academic.group_id) if academic.group_id else None
    require(group is None or (career is not None and group.career_id == career.id), 409,
            "ACADEMIC_DATA_CONFLICT", "La referencia de carrera y grupo no es consistente.")
    review = Review(id=new_id(), order_id=id, user_id=actor.id, business_id=order.business_id,
                    rating=data["rating"], food_rating=data.get("foodRating"), service_rating=data.get("serviceRating"),
                    career_id=career.id if career else None, group_id=group.id if group else None,
                    career_name=career.name if career else "", group_name=group.name if group else "",
                    comment=comment.strip(), created_at=utcnow())
    db.add(review)
    db.flush()
    return review_dict(review)
