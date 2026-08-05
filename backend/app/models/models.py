"""
Barrel re-export for SQLModel tables.

Alembic imports this module to detect schema changes.
"""

from app.models.dinosaur import Dinosaur
from app.models.dinosaur_type import DinosaurType
from app.models.dinosaur_type_revision import DinosaurTypeRevision
from app.models.field_ensure_job import FieldEnsureJob
from app.models.field_survey_job import FieldSurveyJob
from app.models.fossil import Fossil
from app.models.game_config_release import GameConfigRelease
from app.models.game_config_revision import GameConfigRevision
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_session import ToolSession
from app.models.tool_session_event import ToolSessionEvent
from app.models.tool_type import ToolType
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.models.user_device_token import UserDeviceToken
from app.models.user_dinosaur import UserDinosaur
from app.models.user_fossil import UserFossil
from app.models.user_notification import UserNotification
from app.models.user_site import UserSite
from app.models.user_tool import UserTool
from app.models.user_user import UserUser
from app.models.weather import Weather

__all__ = [
    "Dinosaur",
    "DinosaurType",
    "DinosaurTypeRevision",
    "FieldEnsureJob",
    "FieldSurveyJob",
    "Fossil",
    "GameConfigRelease",
    "GameConfigRevision",
    "Site",
    "SiteType",
    "Tool",
    "ToolSession",
    "ToolSessionEvent",
    "ToolType",
    "User",
    "UserAuthIdentity",
    "UserDeviceToken",
    "UserDinosaur",
    "UserFossil",
    "UserNotification",
    "UserSite",
    "UserTool",
    "UserUser",
    "Weather",
]
