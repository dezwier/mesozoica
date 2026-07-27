"""Auth and user API schemas."""

from __future__ import annotations

from datetime import date

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class LoginRequest(BaseModel):
    username: str = Field(..., description="Username or email")
    password: str = Field(..., min_length=1)


class RegisterRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr
    password: str = Field(..., min_length=6)
    full_name: str | None = Field(None, max_length=200)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    email: str
    created_at: str
    full_name: str | None = None
    image_url: str | None = None
    display_name: str = "Paleontologist"
    specialization: str = "Paleontologist"
    years_of_experience: int = 0
    notable_discovery: str = ""
    favorite_era: str = ""
    xp: int = 0
    level: int = 1
    achievements: list[str] = Field(default_factory=list)
    bio: str = ""
    current_location: str = ""
    is_subscriber: bool = False
    is_admin: bool = False
    total_distance_m: float = 0.0
    weekly_distance_m: float = 0.0
    active_distance_m: float = 0.0
    active_weekly_distance_m: float = 0.0
    distance_week_start: date | None = None
    distance_synced_at: str | None = None

    exploration_xp: int = 0
    excavation_xp: int = 0
    research_xp: int = 0
    exploration_level: int = 1
    excavation_level: int = 1
    research_level: int = 1
    career_title: str = "Trail Dust Note"
    exploration_progress: float = 0.0
    excavation_progress: float = 0.0
    research_progress: float = 0.0
    career_progress: float = 0.0
    xp_from_sites: int = 0
    xp_from_fossils: int = 0
    xp_from_active_distance: int = 0
    xp_from_passive_distance: int = 0


class UserProfileResponse(UserResponse):
    actual_dinosaurs_count: int = 0
    actual_fossils_count: int = 0
    actual_sites_count: int = 0


class UpdateDistanceRequest(BaseModel):
    total_distance_m: float = Field(..., ge=0)
    weekly_distance_m: float = Field(..., ge=0)
    active_distance_m: float = Field(0, ge=0)
    active_weekly_distance_m: float = Field(0, ge=0)
    week_start: date = Field(..., description="Local Monday (ISO date) for the weekly window")


class UserListEntry(BaseModel):
    id: int
    username: str
    display_name: str
    full_name: str | None = None
    image_url: str | None = None
    level: int = 1
    actual_dinosaurs_count: int = 0
    actual_fossils_count: int = 0
    actual_sites_count: int = 0


class UserListResponse(BaseModel):
    items: list[UserListEntry]
    total: int
    limit: int
    offset: int
    has_next: bool


class UpdateProfileRequest(BaseModel):
    username: str | None = Field(None, min_length=3, max_length=50)
    email: EmailStr | None = None
    current_password: str | None = None
    password: str | None = Field(None, min_length=6)
    full_name: str | None = Field(None, max_length=200)


class FirebaseLoginRequest(BaseModel):
    id_token: str = Field(..., description="Firebase ID token from the client")


class LinkGoogleRequest(BaseModel):
    id_token: str | None = None
    firebase_id_token: str | None = None


class LinkAppleRequest(BaseModel):
    id_token: str | None = None
    firebase_id_token: str | None = None
    email: str | None = None
    full_name: str | None = None


class AuthResponse(BaseModel):
    user: UserResponse
    access_token: str
    token_type: str = "bearer"
    message: str


class AvailabilityResponse(BaseModel):
    available: bool


class LinkedAccountsResponse(BaseModel):
    providers: list[str]


class LinkedAccountsMessageResponse(BaseModel):
    message: str
    providers: list[str]


class RegisterDeviceTokenRequest(BaseModel):
    """Register FCM (or other) device token for push."""

    token: str = Field(..., min_length=1, description="FCM device token")
    platform: str = Field(
        default="android",
        description="android | ios | web",
    )


class DeleteUserDataRequest(BaseModel):
    """Selective wipe of the authenticated user's progress tables."""

    sites: bool = False
    fossils: bool = False
    dinosaurs: bool = False


class DeleteUserDataResponse(BaseModel):
    deleted_sites: int = 0
    deleted_fossils: int = 0
    deleted_dinosaurs: int = 0
    user: UserProfileResponse
    message: str
