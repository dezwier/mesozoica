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
from app.models.formation_map_session import FormationMapSession
from app.models.orbit_survey_session import OrbitSurveySession
from app.models.terrain_echo_session import TerrainEchoSession
from app.models.guidance_session import GuidanceSession
from app.models.site import Site
from app.models.site_type import SiteType
from app.models.tool import Tool
from app.models.tool_mission import ToolMission
from app.models.tool_mission_event import ToolMissionEvent
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

__all__ = [
    "Dinosaur",
    "DinosaurType",
    "DinosaurTypeRevision",
    "FieldEnsureJob",
    "FieldSurveyJob",
    "Fossil",
    "FormationMapSession",
    "OrbitSurveySession",
    "TerrainEchoSession",
    "GuidanceSession",
    "Site",
    "SiteType",
    "Tool",
    "ToolMission",
    "ToolMissionEvent",
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
]
