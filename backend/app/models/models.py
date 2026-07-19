"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur
from app.models.field_ensure_job import FieldEnsureJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_status import SiteStatus
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.models.user_notification import UserNotification
from app.models.user_user import UserUser

__all__ = [
    "Dinosaur",
    "FieldEnsureJob",
    "Fossil",
    "Site",
    "SiteStatus",
    "SiteType",
    "Tool",
    "User",
    "UserAuthIdentity",
    "UserNotification",
    "UserUser",
]
