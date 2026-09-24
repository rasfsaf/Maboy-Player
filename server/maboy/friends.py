"""Заявки в друзья и передача трека между аккаунтами.

Байты файла не копируются: получатель получает запись с тем же provider/source_id
и обычную операцию track.upsert в своей синхронизации.
"""

from fastapi import HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .models import FriendRequest, Track, TrackShare, User
import uuid


class NicknameIn(BaseModel):
    nickname: str = Field(min_length=3, max_length=24, pattern=r"^[a-z0-9_]+$")


class ShareIn(BaseModel):
    track_id: str


def snapshot(db: Session, user: User) -> dict:
    accepted = db.scalars(
        select(FriendRequest).where(
            FriendRequest.status == "accepted",
            (FriendRequest.from_user_id == user.id) | (FriendRequest.to_user_id == user.id),
        )
    ).all()
    people = []
    for row in accepted:
        other_id = row.to_user_id if row.from_user_id == user.id else row.from_user_id
        other = db.get(User, other_id)
        if other and other.nickname:
            people.append({"id": other.id, "nickname": other.nickname})
    incoming = db.scalars(
        select(FriendRequest).where(FriendRequest.to_user_id == user.id, FriendRequest.status == "pending")
    ).all()
    outgoing = db.scalars(
        select(FriendRequest).where(FriendRequest.from_user_id == user.id, FriendRequest.status == "pending")
    ).all()
    shares = db.scalars(
        select(TrackShare).where(TrackShare.to_user_id == user.id, TrackShare.status == "pending")
    ).all()
    return {
        "nickname": user.nickname,
        "friends": people,
        "incoming": [_request_view(db, row) for row in incoming],
        "outgoing": [
            {"id": row.id, "nickname": (db.get(User, row.to_user_id).nickname or "")}
            for row in outgoing
        ],
        "shares": [_share_view(db, row) for row in shares],
    }


def _request_view(db: Session, row: FriendRequest) -> dict:
    sender = db.get(User, row.from_user_id)
    return {"id": row.id, "nickname": sender.nickname if sender else ""}


def _share_view(db: Session, row: TrackShare) -> dict:
    sender = db.get(User, row.from_user_id)
    return {
        "id": row.id,
        "nickname": sender.nickname if sender else "",
        "track_id": row.source_track_id,
        "title": row.title,
        "artist": row.artist or "",
        "provider": row.provider,
        "source_id": row.source_id,
    }


def set_nickname(db: Session, user: User, nickname: str) -> dict:
    taken = db.scalar(select(User).where(User.nickname == nickname, User.id != user.id))
    if taken:
        raise HTTPException(409, "nickname_taken")
    user.nickname = nickname
    db.commit()
    return {"nickname": nickname}


def request_friend(db: Session, user: User, nickname: str) -> dict:
    if not user.nickname:
        raise HTTPException(409, "nickname_required")
    if nickname == user.nickname:
        raise HTTPException(422, "self_request")
    target = db.scalar(select(User).where(User.nickname == nickname))
    if target is None:
        raise HTTPException(404, "user_not_found")
    existing = db.scalar(
        select(FriendRequest).where(
            FriendRequest.from_user_id.in_([user.id, target.id]),
            FriendRequest.to_user_id.in_([user.id, target.id]),
        )
    )
    if existing and existing.status == "accepted":
        return {"status": "accepted"}
    if existing and existing.status == "pending" and existing.from_user_id == target.id:
        existing.status = "accepted"
        db.commit()
        return {"status": "accepted"}
    if existing and existing.status == "pending":
        return {"status": "pending"}
    db.add(FriendRequest(from_user_id=user.id, to_user_id=target.id))
    db.commit()
    return {"status": "pending"}


def accept_request(db: Session, user: User, request_id: str) -> dict:
    row = db.get(FriendRequest, request_id)
    if row is None or row.to_user_id != user.id or row.status != "pending":
        raise HTTPException(404, "request_not_found")
    row.status = "accepted"
    db.commit()
    return {"status": "accepted"}


def share_track(db: Session, user: User, nickname: str, track_id: str) -> dict:
    target = db.scalar(select(User).where(User.nickname == nickname))
    track = db.get(Track, track_id)
    if target is None or track is None or track.user_id != user.id:
        raise HTTPException(404, "not_found")
    friends = snapshot(db, user)["friends"]
    if not any(person["id"] == target.id for person in friends):
        raise HTTPException(403, "not_friends")
    db.add(TrackShare(
        from_user_id=user.id,
        to_user_id=target.id,
        source_track_id=track.id,
        title=track.title,
        artist=track.artist,
        provider=track.provider,
        source_id=track.source_id,
    ))
    db.commit()
    return {"status": "pending"}


def accept_share(db: Session, user: User, share_id: str) -> dict:
    from .app import Mutation, apply_mutation

    row = db.get(TrackShare, share_id)
    if row is None or row.to_user_id != user.id or row.status != "pending":
        raise HTTPException(404, "share_not_found")
    row.status = "accepted"
    track_id = str(uuid.uuid4())
    mutation = Mutation(operation_id=str(uuid.uuid4()), kind="track.upsert", payload={
        "id": track_id,
        "provider": row.provider,
        "source_id": row.source_id,
        "title": row.title,
        "artist": row.artist,
    })
    apply_mutation(db, user, mutation)
    user.version += 1
    from .models import Operation
    db.add(Operation(
        user_id=user.id, operation_id=str(mutation.operation_id),
        kind=mutation.kind, payload=mutation.payload, version=user.version,
    ))
    db.commit()
    return {"status": "accepted", "track_id": track_id, "source_track_id": row.source_track_id}


def shared_file(db: Session, user: User, share_id: str):
    row = db.get(TrackShare, share_id)
    if row is None or row.status != "accepted":
        raise HTTPException(404, "share_not_found")
    if user.id not in (row.from_user_id, row.to_user_id):
        raise HTTPException(404, "share_not_found")
    friends = snapshot(db, user)["friends"]
    other = row.to_user_id if row.from_user_id == user.id else row.from_user_id
    if not any(person["id"] == other for person in friends):
        raise HTTPException(403, "not_friends")
    return row.source_track_id

