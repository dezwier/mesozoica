"""Auth, profile, and friends API tests."""

from __future__ import annotations

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.core.security import create_access_token
from app.models.user import User


def _auth_headers(user_id: int) -> dict[str, str]:
    token = create_access_token({"sub": str(user_id)})
    return {"Authorization": f"Bearer {token}"}


def _register_user(client: TestClient, username: str, email: str) -> dict:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "username": username,
            "email": email,
            "password": "secret123",
            "full_name": "Dr. Rex",
        },
    )
    assert response.status_code == 201
    return response.json()


def test_register_and_login(client: TestClient):
    registered = _register_user(client, "rex", "rex@example.com")
    assert registered["access_token"]
    assert registered["user"]["username"] == "rex"
    assert registered["user"]["display_name"] == "Dr. Rex"

    login = client.post(
        "/api/v1/auth/login",
        json={"username": "rex", "password": "secret123"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["email"] == "rex@example.com"


def test_get_my_profile(client: TestClient):
    registered = _register_user(client, "profile_user", "profile@example.com")
    token = registered["access_token"]
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["username"] == "profile_user"
    assert body["actual_dinosaurs_count"] == 0
    assert body["actual_fossils_count"] == 0
    assert body["actual_sites_count"] == 0


def test_profile_collection_counts_from_link_tables(
    client: TestClient, session: Session
):
    from decimal import Decimal

    from app.models.dinosaur import Dinosaur
    from app.models.dinosaur_type import DinosaurType
    from app.models.fossil import Fossil
    from app.models.site import Site
    from app.models.site_type import SiteType
    from app.models.user_dinosaur import (
        USER_DINOSAUR_ROLE_MODELLED,
        UserDinosaur,
    )
    from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
    from app.models.user_site import (
        USER_SITE_ROLE_DISCOVERER,
        USER_SITE_ROLE_DOCUMENTER,
        UserSite,
    )

    registered = _register_user(client, "collector", "collector@example.com")
    user_id = registered["user"]["id"]
    token = registered["access_token"]

    site_type = SiteType(period="cretaceous", rock_type="sandstone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)

    session.add(
        Site(
            site_id=91001,
            latitude=Decimal("45.0"),
            longitude=Decimal("-110.0"),
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
        )
    )
    session.add(
        Site(
            site_id=91002,
            latitude=Decimal("46.0"),
            longitude=Decimal("-111.0"),
            rock_type="sandstone",
            period="cretaceous",
            site_type_id=site_type.id,
        )
    )
    dino_type_a = DinosaurType(
        name="Tyrannosaurus",
        wikipedia_page_id=91001,
        wikipedia_title="Tyrannosaurus",
    )
    dino_type_b = DinosaurType(
        name="Triceratops",
        wikipedia_page_id=91002,
        wikipedia_title="Triceratops",
    )
    session.add(dino_type_a)
    session.add(dino_type_b)
    session.commit()
    session.refresh(dino_type_a)
    session.refresh(dino_type_b)

    occurrence_a = Dinosaur(dinosaur_type_id=dino_type_a.id)
    session.add(occurrence_a)
    session.commit()
    session.refresh(occurrence_a)

    fossil_a = Fossil(
        id=91001, dinosaur_id=dino_type_a.id, identified_name="T. rex tooth"
    )
    fossil_b = Fossil(
        id=91002, dinosaur_id=dino_type_b.id, identified_name="Triceratops horn"
    )
    session.add(fossil_a)
    session.add(fossil_b)
    session.commit()

    # Two roles on the same site → still one unique site.
    session.add(
        UserSite(
            user_id=user_id,
            site_id=91001,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.add(
        UserSite(
            user_id=user_id,
            site_id=91001,
            role=USER_SITE_ROLE_DOCUMENTER,
        )
    )
    session.add(
        UserSite(
            user_id=user_id,
            site_id=91002,
            role=USER_SITE_ROLE_DISCOVERER,
        )
    )
    session.add(
        UserFossil(
            user_id=user_id,
            fossil_id=91001,
            role=USER_FOSSIL_ROLE_IN_SITU,
        )
    )
    session.add(
        UserFossil(
            user_id=user_id,
            fossil_id=91002,
            role=USER_FOSSIL_ROLE_IN_SITU,
        )
    )
    session.add(
        UserDinosaur(
            user_id=user_id,
            dinosaur_id=occurrence_a.id,
            role=USER_DINOSAUR_ROLE_MODELLED,
        )
    )
    session.commit()

    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["actual_sites_count"] == 2
    assert body["actual_fossils_count"] == 2
    assert body["actual_dinosaurs_count"] == 1

    other = _register_user(client, "other_collector", "other@example.com")
    other_me = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert other_me.status_code == 200
    other_body = other_me.json()
    assert other_body["actual_sites_count"] == 0
    assert other_body["actual_fossils_count"] == 0
    assert other_body["actual_dinosaurs_count"] == 0

    user_a = _register_user(client, "alice", "alice@example.com")
    user_b = _register_user(client, "bob", "bob@example.com")

    list_response = client.get(
        "/api/v1/users/list",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert list_response.status_code == 200
    assert list_response.json()["total"] >= 2

    bob_id = user_b["user"]["id"]
    request_response = client.post(
        "/api/v1/user-relationships/friend-request",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
        json={"target_user_id": bob_id},
    )
    assert request_response.status_code == 200
    assert request_response.json()["relationship_type"] == "friend_pending"

    rel = client.get(
        f"/api/v1/user-relationships/{bob_id}",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert rel.status_code == 200
    assert rel.json()["relationship_type"] == "friend_pending"

    alice_id = user_a["user"]["id"]
    accept = client.post(
        f"/api/v1/user-relationships/friend-request/{alice_id}/accept",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert accept.status_code == 200
    assert accept.json()["relationship_type"] == "friend"

    friends = client.get(
        "/api/v1/user-relationships/friends/me/list",
        headers={"Authorization": f"Bearer {user_a['access_token']}"},
    )
    assert friends.status_code == 200
    assert friends.json()["total"] == 1


def test_get_self_relationship(client: TestClient):
    registered = _register_user(client, "self_user", "self@example.com")
    user_id = registered["user"]["id"]
    response = client.get(
        f"/api/v1/user-relationships/{user_id}",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["relationship_type"] == "self"


def test_public_profile(client: TestClient):
    registered = _register_user(client, "public_user", "public@example.com")
    user_id = registered["user"]["id"]
    other = _register_user(client, "viewer", "viewer@example.com")
    response = client.get(
        f"/api/v1/users/{user_id}/profile",
        headers={"Authorization": f"Bearer {other['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["username"] == "public_user"


def test_update_profile_username(client: TestClient):
    registered = _register_user(client, "oldname", "old@example.com")
    token = registered["access_token"]
    response = client.patch(
        "/api/v1/auth/update-profile",
        headers={"Authorization": f"Bearer {token}"},
        json={"full_name": "Old Name Updated"},
    )
    assert response.status_code == 200
    assert response.json()["user"]["full_name"] == "Old Name Updated"


def test_delete_data_requires_auth(client: TestClient):
    response = client.post(
        "/api/v1/auth/delete-data",
        json={"sites": True, "fossils": True, "dinosaurs": True},
    )
    assert response.status_code == 401


def test_delete_data_requires_selection(client: TestClient):
    registered = _register_user(client, "wipe_empty", "wipe_empty@example.com")
    response = client.post(
        "/api/v1/auth/delete-data",
        headers={"Authorization": f"Bearer {registered['access_token']}"},
        json={"sites": False, "fossils": False, "dinosaurs": False, "xp": False},
    )
    assert response.status_code == 400
    assert "at least one" in response.json()["detail"].lower()


def test_delete_data_selective_and_scoped(client: TestClient, session: Session):
    from decimal import Decimal

    from app.models.dinosaur import Dinosaur
    from app.models.dinosaur_type import DinosaurType
    from app.models.fossil import Fossil
    from app.models.site import Site
    from app.models.site_type import SiteType
    from app.models.user_dinosaur import (
        USER_DINOSAUR_ROLE_MODELLED,
        UserDinosaur,
    )
    from app.models.user_fossil import USER_FOSSIL_ROLE_IN_SITU, UserFossil
    from app.models.user_site import USER_SITE_ROLE_DISCOVERER, UserSite
    from sqlmodel import col, select

    user_a = _register_user(client, "wipe_a", "wipe_a@example.com")
    user_b = _register_user(client, "wipe_b", "wipe_b@example.com")
    a_id = user_a["user"]["id"]
    b_id = user_b["user"]["id"]
    a_token = user_a["access_token"]

    site_type = SiteType(period="jurassic", rock_type="limestone")
    session.add(site_type)
    session.commit()
    session.refresh(site_type)

    session.add(
        Site(
            site_id=92001,
            latitude=Decimal("40.0"),
            longitude=Decimal("-105.0"),
            rock_type="limestone",
            period="jurassic",
            site_type_id=site_type.id,
        )
    )
    session.add(
        Site(
            site_id=92002,
            latitude=Decimal("41.0"),
            longitude=Decimal("-106.0"),
            rock_type="limestone",
            period="jurassic",
            site_type_id=site_type.id,
        )
    )
    dino_type = DinosaurType(
        name="Stegosaurus",
        wikipedia_page_id=92001,
        wikipedia_title="Stegosaurus",
    )
    session.add(dino_type)
    session.commit()
    session.refresh(dino_type)

    occurrence = Dinosaur(dinosaur_type_id=dino_type.id)
    session.add(occurrence)
    session.commit()
    session.refresh(occurrence)

    fossil = Fossil(
        id=92001, dinosaur_id=dino_type.id, identified_name="Stegosaurus plate"
    )
    session.add(fossil)
    session.commit()

    for uid in (a_id, b_id):
        session.add(
            UserSite(
                user_id=uid,
                site_id=92001,
                role=USER_SITE_ROLE_DISCOVERER,
            )
        )
        session.add(
            UserSite(
                user_id=uid,
                site_id=92002,
                role=USER_SITE_ROLE_DISCOVERER,
            )
        )
        session.add(
            UserFossil(
                user_id=uid,
                fossil_id=92001,
                role=USER_FOSSIL_ROLE_IN_SITU,
            )
        )
        session.add(
            UserDinosaur(
                user_id=uid,
                dinosaur_id=occurrence.id,
                role=USER_DINOSAUR_ROLE_MODELLED,
            )
        )
    session.commit()

    # Wipe only sites for A; fossils + dinos remain for A; B untouched.
    wipe_sites = client.post(
        "/api/v1/auth/delete-data",
        headers={"Authorization": f"Bearer {a_token}"},
        json={"sites": True, "fossils": False, "dinosaurs": False},
    )
    assert wipe_sites.status_code == 200
    sites_body = wipe_sites.json()
    assert sites_body["deleted_sites"] == 2
    assert sites_body["deleted_fossils"] == 0
    assert sites_body["deleted_dinosaurs"] == 0
    assert sites_body["user"]["actual_sites_count"] == 0
    assert sites_body["user"]["actual_fossils_count"] == 1
    assert sites_body["user"]["actual_dinosaurs_count"] == 1

    # Wipe fossils + dinos for A.
    wipe_rest = client.post(
        "/api/v1/auth/delete-data",
        headers={"Authorization": f"Bearer {a_token}"},
        json={"sites": False, "fossils": True, "dinosaurs": True},
    )
    assert wipe_rest.status_code == 200
    rest_body = wipe_rest.json()
    assert rest_body["deleted_fossils"] == 1
    assert rest_body["deleted_dinosaurs"] == 1
    assert rest_body["user"]["actual_sites_count"] == 0
    assert rest_body["user"]["actual_fossils_count"] == 0
    assert rest_body["user"]["actual_dinosaurs_count"] == 0

    me = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {a_token}"},
    )
    assert me.status_code == 200
    assert me.json()["actual_sites_count"] == 0
    assert me.json()["actual_fossils_count"] == 0
    assert me.json()["actual_dinosaurs_count"] == 0

    # User B's progress intact.
    assert (
        len(session.exec(select(UserSite).where(col(UserSite.user_id) == b_id)).all())
        == 2
    )
    assert (
        len(
            session.exec(
                select(UserFossil).where(col(UserFossil.user_id) == b_id)
            ).all()
        )
        == 1
    )
    assert (
        len(
            session.exec(
                select(UserDinosaur).where(col(UserDinosaur.user_id) == b_id)
            ).all()
        )
        == 1
    )

    other_me = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {user_b['access_token']}"},
    )
    assert other_me.status_code == 200
    assert other_me.json()["actual_sites_count"] == 2
    assert other_me.json()["actual_fossils_count"] == 1
    assert other_me.json()["actual_dinosaurs_count"] == 1

    # Idempotent: wiping again succeeds with zero deletes.
    again = client.post(
        "/api/v1/auth/delete-data",
        headers={"Authorization": f"Bearer {a_token}"},
        json={"sites": True, "fossils": True, "dinosaurs": True},
    )
    assert again.status_code == 200
    assert again.json()["deleted_sites"] == 0
    assert again.json()["deleted_fossils"] == 0
    assert again.json()["deleted_dinosaurs"] == 0


def test_delete_data_clears_skill_xp(client: TestClient, session: Session):
    from app.services.level_service import set_skill_xp, sync_career_from_skills
    from app.services.level_service.skills import get_skill_xp, total_skill_xp

    registered = _register_user(client, "wipe_xp", "wipe_xp@example.com")
    user_id = registered["user"]["id"]
    token = registered["access_token"]

    user = session.get(User, user_id)
    assert user is not None
    set_skill_xp(user, "site_discovery", 120)
    set_skill_xp(user, "site_stewardship", 80)
    sync_career_from_skills(user)
    session.add(user)
    session.commit()
    session.refresh(user)
    before = total_skill_xp(user)
    assert before == 200
    assert user.level > 1

    wipe = client.post(
        "/api/v1/auth/delete-data",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "sites": False,
            "fossils": False,
            "dinosaurs": False,
            "xp": True,
        },
    )
    assert wipe.status_code == 200
    body = wipe.json()
    assert body["cleared_xp"] == 200
    assert body["deleted_sites"] == 0
    assert body["user"]["xp"] == 0
    assert body["user"]["level"] == 1
    for skill in body["user"]["skills"]:
        assert skill["xp"] == 0
        assert skill["level"] == 1

    session.refresh(user)
    assert total_skill_xp(user) == 0
    assert get_skill_xp(user, "site_discovery") == 0
    assert get_skill_xp(user, "site_stewardship") == 0
    assert user.skill_breakdown == {}
    assert user.xp == 0
    assert user.level == 1
