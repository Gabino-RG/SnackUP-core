"""Ephemeral chat. Durable notifications contain IDs only, never message text."""
from datetime import datetime, timedelta
import hashlib
import hmac

from fastapi import APIRouter, Body, Request, Response
from pydantic import Field
from sqlalchemy import delete, func, select

from .auth import as_utc, current_user
from .common import iso, require
from .db import emit_event, utcnow
from .identity_models import User
from .operation_models import Business, Order
from .v3_operations import (Authenticated, DB, Limit, Operator, Page, PaginationResponse,
                            ResponseModel, StrictInput, Student, _page_rows)
from .v32_models import Chat, ChatClosure, ChatMessage

router = APIRouter(tags=['Chat efímero V3.2'])
TTL = timedelta(hours=24)


class OpenChatInput(StrictInput):
    orderId: str | None = Field(default=None, min_length=1, max_length=1500)


class MessageInput(StrictInput):
    text: str = Field(min_length=1, max_length=1000)


class ChatResponse(ResponseModel):
    id: str
    businessId: str
    orderId: str | None
    createdAt: datetime
    lastActivityAt: datetime


class MessageResponse(ResponseModel):
    id: str
    chatId: str
    senderRole: str
    text: str
    createdAt: datetime


class ChatPage(ResponseModel):
    data: list[ChatResponse]
    pagination: PaginationResponse


class MessagePage(ResponseModel):
    data: list[MessageResponse]
    pagination: PaginationResponse


def chat_dto(chat):
    return {'id': chat.id, 'businessId': chat.business_id, 'orderId': chat.order_id,
            'createdAt': iso(chat.created_at), 'lastActivityAt': iso(chat.last_activity_at)}


def message_dto(message):
    return {'id': message.id, 'chatId': message.chat_id, 'senderRole': message.sender_role,
            'text': message.text, 'createdAt': iso(message.created_at)}


def participant(actor, chat):
    return (actor.role == 'user' and actor.id == chat.student_id or
            actor.role == 'business' and actor.business_id == chat.business_id)


def closure_proof(settings, chat_id, role, identity):
    payload = '\0'.join((chat_id, role, identity)).encode()
    return hmac.new(settings.secret_key.encode(), b'chat-closure\0' + payload, hashlib.sha256).hexdigest()


def close_chat(db, chat, settings, now=None):
    now = now or utcnow()
    # Only keyed proofs survive. They authorize repeated DELETE without keeping
    # the conversation, participants, order ID or any text as an audit history.
    db.add(ChatClosure(id=chat.id, student_proof=closure_proof(settings, chat.id, 'user', chat.student_id),
                       business_proof=closure_proof(settings, chat.id, 'business', chat.business_id), closed_at=now))
    for topic in (f'user:{chat.student_id}:chats', f'business:{chat.business_id}:chats'):
        emit_event(db, topic, 'chat.closed', {'chatId': chat.id})
    db.execute(delete(ChatMessage).where(ChatMessage.chat_id == chat.id))
    db.delete(chat)
    db.flush()


def _actor_lock(db, request, actor):
    db.scalar(select(User).where(User.id == actor.id).with_for_update(key_share=True).execution_options(populate_existing=True))
    actor = current_user(request, db)
    require(actor.role in ('user', 'business'), 403, 'FORBIDDEN')
    return actor


def _chat(db, actor, id, *, lock=False, allow_expired=False):
    statement = select(Chat).where(Chat.id == id)
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    chat = db.scalar(statement)
    require(chat is not None and participant(actor, chat), 404, 'CHAT_NOT_FOUND')
    require(allow_expired or as_utc(chat.last_activity_at) > utcnow() - TTL, 404, 'CHAT_NOT_FOUND')
    return chat


@router.post('/businesses/{id}/chats', response_model=ChatResponse, operation_id='v32OpenChat')
def open_chat(id: str, request: Request, db: DB, actor: Authenticated,
              body: OpenChatInput = Body(default_factory=OpenChatInput)):
    actor = _actor_lock(db, request, actor)
    request.app.state.limiter.check('chat-open', actor.id, 20, 60)
    require(actor.role != 'business' or actor.business_id == id, 403, 'FORBIDDEN')
    business = db.scalar(select(Business).where(Business.id == id).with_for_update()
                         .execution_options(populate_existing=True))
    current_user(request, db)
    require(business is not None and business.is_active, 404, 'BUSINESS_NOT_FOUND')
    require(actor.role != 'business' or body.orderId is not None, 422, 'ORDER_REQUIRED')
    student_id = actor.id
    if body.orderId:
        order = db.get(Order, body.orderId)
        require(order is not None and order.business_id == id and
                (actor.role == 'business' or order.student_id == actor.id), 404, 'ORDER_NOT_FOUND')
        student_id = order.student_id
    chat = db.scalar(select(Chat).where(Chat.student_id == student_id, Chat.business_id == id)
                     .with_for_update().execution_options(populate_existing=True))
    if chat and as_utc(chat.last_activity_at) <= utcnow() - TTL:
        close_chat(db, chat, request.app.state.settings)
        chat = None
    if chat is None:
        chat = Chat(student_id=student_id, business_id=id, order_id=body.orderId)
        db.add(chat)
        db.flush()
        for topic in (f'user:{student_id}:chats', f'business:{id}:chats'):
            emit_event(db, topic, 'chat.opened', {'chatId': chat.id})
    return chat_dto(chat)


@router.get('/users/me/chats', response_model=ChatPage, operation_id='v32MyChats')
def my_chats(db: DB, actor: Student, page: Page = 1, limit: Limit = 20):
    return _chat_page(db, select(Chat).where(Chat.student_id == actor.id), page, limit)


@router.get('/businesses/{id}/chats', response_model=ChatPage, operation_id='v32BusinessChats')
def business_chats(id: str, db: DB, actor: Operator, page: Page = 1, limit: Limit = 20):
    require(actor.business_id == id, 403, 'FORBIDDEN')
    return _chat_page(db, select(Chat).where(Chat.business_id == id), page, limit)


def _chat_page(db, statement, page, limit):
    rows, pagination = _page_rows(db, statement.where(Chat.last_activity_at > utcnow() - TTL)
                                  .order_by(Chat.last_activity_at.desc(), Chat.id), page, limit)
    return {'data': [chat_dto(row) for row in rows], 'pagination': pagination}


@router.get('/chats/{id}/messages', response_model=MessagePage, operation_id='v32ChatMessages')
def list_messages(id: str, db: DB, actor: Authenticated, page: Page = 1, limit: Limit = 50):
    _chat(db, actor, id)
    rows, pagination = _page_rows(db, select(ChatMessage).where(ChatMessage.chat_id == id)
                                  .order_by(ChatMessage.created_at, ChatMessage.id), page, limit)
    return {'data': [message_dto(row) for row in rows], 'pagination': pagination}


@router.post('/chats/{id}/messages', status_code=201, response_model=MessageResponse, operation_id='v32SendChatMessage')
def send_message(id: str, body: MessageInput, request: Request, db: DB, actor: Authenticated):
    actor = _actor_lock(db, request, actor)
    request.app.state.limiter.check('chat-message', actor.id, 1, 1)
    chat = _chat(db, actor, id, lock=True)
    current_user(request, db)
    require(bool(body.text.strip()), 422, 'EMPTY_MESSAGE')
    require(db.scalar(select(func.count()).select_from(ChatMessage).where(ChatMessage.chat_id == id)) < 1000,
            422, 'CHAT_MESSAGE_LIMIT', 'Finaliza esta conversación antes de abrir otra.')
    message = ChatMessage(chat_id=id, sender_id=actor.id, sender_role='ALUMNO' if actor.role == 'user' else 'COCINA',
                          text=body.text.strip())
    db.add(message)
    chat.last_activity_at = utcnow()
    db.flush()
    for topic in (f'user:{chat.student_id}:chats', f'business:{chat.business_id}:chats'):
        emit_event(db, topic, 'chat.message', {'chatId': id, 'messageId': message.id})
    return message_dto(message)


@router.delete('/chats/{id}', status_code=204, operation_id='v32CloseChat')
def finish_chat(id: str, request: Request, db: DB, actor: Authenticated):
    actor = _actor_lock(db, request, actor)
    chat = db.scalar(select(Chat).where(Chat.id == id).with_for_update().execution_options(populate_existing=True))
    current_user(request, db)
    if chat:
        require(participant(actor, chat), 404, 'CHAT_NOT_FOUND')
        close_chat(db, chat, request.app.state.settings)
    else:
        receipt = db.get(ChatClosure, id)
        expected = closure_proof(request.app.state.settings, id, actor.role,
                                 actor.id if actor.role == 'user' else actor.business_id or '')
        proof = receipt.student_proof if receipt and actor.role == 'user' else receipt.business_proof if receipt else ''
        require(hmac.compare_digest(proof, expected), 404, 'CHAT_NOT_FOUND')
    return Response(status_code=204)


def realtime_message(db, identity, event):
    """Materialize transient text at delivery, only while the chat still exists."""
    data = event['data']
    message = db.get(ChatMessage, data.get('messageId'))
    chat = db.get(Chat, data.get('chatId'))
    if (message is None or chat is None or message.chat_id != chat.id
            or as_utc(chat.last_activity_at) <= utcnow() - TTL):
        return None
    allowed = (identity.role == 'user' and identity.user_id == chat.student_id or
               identity.role == 'business' and identity.business_id == chat.business_id)
    return {**event, 'data': message_dto(message)} if allowed else None
