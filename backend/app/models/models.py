"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.models.user_device_token import UserDeviceToken
from app.models.user_dinosaur import UserDinosaur
from app.models.user_fossil import UserFossil
from app.models.user_notification import UserNotification
from app.models.user_site import UserSite
from app.models.user_tool import UserTool
from app.models.user_user import UserUser

__all__ = [
    "Dinosaur",
    "FieldEnsureJob",
    "FieldSurveyJob",
    "Fossil",
    "Site",
    "SiteType",
    "Tool",
    "User",
    "UserAuthIdentity",
    "UserDeviceToken",
    "UserDinosaur",
    "UserFossil",
    "UserNotification",
    "UserSite",
    "UserTool",
    "UserUser",
]
