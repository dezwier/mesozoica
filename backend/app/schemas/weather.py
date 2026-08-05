"""Weather status response models."""

from datetime import datetime

from pydantic import BaseModel, Field


class WeatherCellInfo(BaseModel):
    i: int
    j: int
    center_lat: float
    center_lon: float


class WeatherStatusResponse(BaseModel):
    weather_type: str
    temperature_c: float
    weather_time: str
    observed_at: datetime
    cell: WeatherCellInfo
    wmo_code: int = Field(description="Upstream Open-Meteo WMO weather code")


class WeatherHourPoint(BaseModel):
    valid_at: datetime
    weather_type: str
    temperature_c: float
    wmo_code: int
    is_forecast: bool
    fetched_at: datetime


class WeatherForecastResponse(BaseModel):
    cell: WeatherCellInfo
    hours: list[WeatherHourPoint]
