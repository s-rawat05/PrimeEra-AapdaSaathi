from __future__ import annotations

from fastapi import Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import AppContext
from app.notifications.dispatcher import flush_outbox
from app.services.realtime import commit


async def finalize(session: AsyncSession, ctx: AppContext) -> None:
    """Commit, publish realtime events, then send any queued notifications (outside the transaction)."""
    await commit(session, ctx.bus)
    await flush_outbox(ctx)


class PageParams:
    def __init__(self, limit: int = Query(50, ge=1, le=500), offset: int = Query(0, ge=0)) -> None:
        self.limit = limit
        self.offset = offset


async def paged(session: AsyncSession, query, page: PageParams):
    total = await session.scalar(select(func.count()).select_from(query.order_by(None).subquery()))
    rows = (await session.execute(query.limit(page.limit).offset(page.offset))).scalars().all()
    return rows, total or 0
