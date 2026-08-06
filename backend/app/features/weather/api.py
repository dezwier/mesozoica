"""HTTP adapter owned by the weather feature."""

from app.features.weather.api_weather import router

routers = (router,)

__all__ = ["routers"]
