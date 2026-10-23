"""Owned media with decoded-image validation and transaction-aware file cleanup."""
import io
from pathlib import Path
from typing import Annotated, Literal
import warnings

from fastapi import APIRouter, Depends, File, Form, Request, Response, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from .auth import current_user, ensure_account
from .common import require
from .db import get_db, new_id, utcnow
from .identity_models import User
from .operation_models import Business, MediaFile, Product

router = APIRouter(tags=['Medios V3'])
DB = Annotated[Session, Depends(get_db, scope='function')]
Authenticated = Annotated[User, Depends(current_user)]
Purpose = Literal['product', 'business', 'avatar', 'review']
MAX_BYTES = 5 * 1024 * 1024
FORMATS = {'JPEG': 'image/jpeg', 'PNG': 'image/png', 'WEBP': 'image/webp'}


class MediaResponse(BaseModel):
    id: str
    url: str
    width: int
    height: int


def owned_media(db, user, url, settings, *, purpose, business_id=None):
    """Validate an attachment by database ownership, never by URL shape alone."""
    if url is None:
        return None
    prefix = settings.public_origin + '/media/'
    filename = url[len(prefix):] if isinstance(url, str) and url.startswith(prefix) else ''
    media = db.scalar(select(MediaFile).where(MediaFile.filename == filename,
                                              MediaFile.deleted_at.is_(None), MediaFile.purpose == purpose)
                      .with_for_update().execution_options(populate_existing=True))
    require(media is not None, 422, 'INVALID_IMAGE', 'Sube primero una imagen autorizada para este recurso.')
    if purpose in {'product', 'business'}:
        require(business_id is not None and media.business_id == business_id, 422, 'INVALID_IMAGE')
    else:
        require(media.owner_id == user.id, 422, 'INVALID_IMAGE')
    return media


def _business_scope(db, user, purpose, business_id):
    if purpose in {'avatar', 'review'}:
        require(business_id is None, 422, 'INVALID_INPUT')
        require(purpose != 'review' or user.role == 'user', 403, 'FORBIDDEN')
        return None
    require(user.role in {'business', 'admin'}, 403, 'FORBIDDEN')
    if user.role == 'business':
        require(business_id in {None, user.business_id}, 403, 'FORBIDDEN')
        business_id = user.business_id
    else:
        require(purpose == 'business', 403, 'FORBIDDEN', 'Administración gestiona imágenes de negocio.')
        require(bool(business_id), 422, 'BUSINESS_REQUIRED')
    business = db.get(Business, business_id)
    require(business is not None, 404, 'BUSINESS_NOT_FOUND')
    return business_id


def _writer(request, db, user):
    user = db.scalar(select(User).where(User.id == user.id).with_for_update()
                     .execution_options(populate_existing=True))
    # A logout/replay that won the User lock must also win over queued writes.
    return current_user(request, db)


@router.post('/media', status_code=201, response_model=MediaResponse, operation_id='v3UploadMedia')
def upload_media(request: Request, db: DB, user: Authenticated,
                 file: Annotated[UploadFile, File()], purpose: Annotated[Purpose, Form()],
                 businessId: Annotated[str | None, Form(min_length=1, max_length=1500)] = None):
    user = _writer(request, db, user)
    request.app.state.limiter.check('media-upload', user.id, 20, 60)
    business_id = _business_scope(db, user, purpose, businessId)
    data = file.file.read(MAX_BYTES + 1)
    require(0 < len(data) <= MAX_BYTES, 413, 'PAYLOAD_TOO_LARGE', 'La imagen admite hasta 5 MB.')
    require(file.content_type in FORMATS.values(), 422, 'INVALID_IMAGE', 'Usa JPEG, PNG o WebP.')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as source:
                require(source.format in FORMATS and FORMATS[source.format] == file.content_type,
                        422, 'INVALID_IMAGE', 'El contenido no coincide con el tipo declarado.')
                require(source.width * source.height <= 20_000_000, 422, 'INVALID_IMAGE', 'La imagen es demasiado grande.')
                source.load()
                processed = ImageOps.exif_transpose(source).convert('RGBA' if 'A' in source.getbands() else 'RGB')
                processed.thumbnail((1600, 1600))
                output = io.BytesIO()
                processed.save(output, 'WEBP', quality=85, method=4)
                width, height = processed.size
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        from .errors import ApiError
        raise ApiError(422, 'INVALID_IMAGE', 'No se pudo validar la imagen.') from None
    identity = new_id()
    filename = identity + '.webp'
    settings = request.app.state.settings
    path = settings.media_dir / filename
    # Add cleanup before writing so partial writes cannot leave a broken image.
    db.info.setdefault('created_media_files', []).append(path)
    path.write_bytes(output.getvalue())
    row = MediaFile(id=identity, business_id=business_id, owner_id=user.id, purpose=purpose,
                    filename=filename, mime_type='image/webp', size=len(output.getvalue()), width=width, height=height)
    db.add(row)
    db.flush()
    return {'id': row.id, 'url': settings.public_origin + '/media/' + filename, 'width': width, 'height': height}


@router.delete('/media/{id}', status_code=204, operation_id='v3DeleteMedia')
def delete_media(id: str, request: Request, db: DB, user: Authenticated):
    user = _writer(request, db, user)
    row = db.scalar(select(MediaFile).where(MediaFile.id == id).with_for_update())
    current_user(request, db)
    require(row is not None, 404, 'MEDIA_NOT_FOUND')
    owned = row.owner_id == user.id
    business_managed = row.purpose in {'product', 'business'} and row.business_id is not None and (
        (user.role == 'business' and user.business_id == row.business_id)
        or (user.role == 'admin' and row.purpose == 'business'))
    require(owned or business_managed, 403, 'FORBIDDEN')
    if row.deleted_at is not None:
        return Response(status_code=204)
    url = request.app.state.settings.public_origin + '/media/' + row.filename
    used = (db.scalar(select(Product.id).where(Product.image_url == url, Product.is_deleted.is_(False)).limit(1))
            or db.scalar(select(Business.id).where(Business.image_url == url).limit(1))
            or db.scalar(select(User.id).where(User.avatar_url == url).limit(1)))
    require(used is None, 409, 'MEDIA_IN_USE', 'Desvincula la imagen del recurso antes de eliminarla.')
    row.deleted_at = utcnow()
    db.info.setdefault('deleted_media_files', []).append(request.app.state.settings.media_dir / row.filename)
    return Response(status_code=204)
