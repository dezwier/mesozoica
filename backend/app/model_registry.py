"""Single persistence-model registration point for SQLModel and Alembic."""

# Alembic imports this registry, never feature internals or compatibility
# modules. Importing each feature-owned model here registers the unchanged
# tables on SQLModel.metadata.
from app.features.accounts.models.user import User
from app.features.accounts.models.user_auth_identity import UserAuthIdentity
from app.features.accounts.models.user_device_token import UserDeviceToken
from app.features.accounts.models.user_notification import UserNotification
from app.features.accounts.models.user_user import UserUser
from app.features.field.models.field_ensure_job import FieldEnsureJob
from app.features.field.models.field_survey_job import FieldSurveyJob
from app.features.game_config.models_release import GameConfigRelease
from app.features.game_config.models_revision import GameConfigRevision
from app.features.sites.models.site import Site
from app.features.sites.models.site_type import SiteType
from app.features.sites.models.user_site import UserSite
from app.features.specimens.models.dinosaur import Dinosaur
from app.features.specimens.models.dinosaur_type import DinosaurType
from app.features.specimens.models.dinosaur_type_revision import DinosaurTypeRevision
from app.features.specimens.models.fossil import Fossil
from app.features.specimens.models.user_dinosaur import UserDinosaur
from app.features.specimens.models.user_fossil import UserFossil
from app.features.tools.models.tool import Tool
from app.features.tools.models.tool_session import ToolSession
from app.features.tools.models.tool_session_event import ToolSessionEvent
from app.features.tools.models.tool_type import ToolType
from app.features.tools.models.user_tool import UserTool
from app.features.weather.models import Weather

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
