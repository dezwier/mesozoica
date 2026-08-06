"""HTTP adapters owned by the accounts feature."""

from app.features.accounts.api_auth_linking import router as auth_linking_router
from app.features.accounts.api_auth_login import router as auth_login_router
from app.features.accounts.api_auth_profile import router as auth_profile_router
from app.features.accounts.api_notifications import router as notifications_router
from app.features.accounts.api_user_relationships import router as relationships_router
from app.features.accounts.api_users import router as users_router

routers = (
    auth_login_router,
    auth_profile_router,
    auth_linking_router,
    users_router,
    relationships_router,
    notifications_router,
)

__all__ = ["routers"]
