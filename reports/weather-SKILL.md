---
name: weather
description: Current weather, hourly and daily forecasts, rain totals and air quality for any place, from free services with no API key (Open-Meteo first, wttr.in for a quick check, 3BMeteo for Italian places). Use for any question about weather, temperature, rain, wind, snow, sunrise/sunset or air quality, today or in the coming days.
---

# Weather

Fetch these URLs with `web_fetch` (all plain GET, JSON back). **Open-Meteo is
the source of truth**: structured, hourly, several models. wttr.in is a
one-line sanity check, never a source for rain totals.

## 1. Find the place

Never use coordinates from memory. Look the name up first:

`https://geocoding-api.open-meteo.com/v1/search?name=<place>&count=1&format=json`

Use `results[0]`: `latitude`, `longitude`, `timezone`, `country`, `admin1`.
No `results` means no match: try the local spelling, then the nearest larger
town. Add `&language=it` to get Italian names back.

## 2. The forecast

`https://api.open-meteo.com/v1/forecast?latitude=<lat>&longitude=<lon>&timezone=<tz>&forecast_days=3&current=temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m&hourly=temperature_2m,apparent_temperature,precipitation,precipitation_probability,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset`

- **Always pass `timezone`** (the one from step 1, or `auto`). Without it every
  time is UTC, the most common mistake.
- `forecast_days` 1 to 16 (default 7). `past_days=1` adds yesterday, to compare
  what fell with what was forecast.
- Ask only for what the question needs: "will it rain tonight" needs
  `hourly=precipitation,precipitation_probability,weather_code`, not
  everything.

## 3. Rain or a close call: compare models

One model can be off by a factor of two on daily rain. For any question about
rain, snow or a borderline temperature, ask three models at once:

`https://api.open-meteo.com/v1/forecast?latitude=<lat>&longitude=<lon>&timezone=<tz>&forecast_days=3&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&models=icon_seamless,ecmwf_ifs025,arpege_europe`

Keys gain the model as a suffix (`precipitation_sum_ecmwf_ifs025`). Report the
**range** ("16–22 mm"), not one figure. If the models differ by more than about
half on rain or 3 °C on the high, say they disagree.

**Horizons:** ARPEGE stops after about 4 days (its values come back `null`),
ICON-EU after about 5 (the seamless one switches to the global model). Beyond
day 4, compare `icon_seamless` and `ecmwf_ifs025` only, and say the spread is
thinner.

## 4. Weather codes

Open-Meteo returns numbers. Translate them:

| Code | Meaning | Code | Meaning |
|---|---|---|---|
| 0 | Clear | 61 / 63 / 65 | Rain: light / moderate / heavy |
| 1 / 2 / 3 | Mainly clear / partly cloudy / overcast | 66 / 67 | Freezing rain |
| 45 / 48 | Fog / rime fog | 71 / 73 / 75 | Snow: light / moderate / heavy |
| 51 / 53 / 55 | Drizzle: light / moderate / dense | 77 | Snow grains |
| 56 / 57 | Freezing drizzle | 80 / 81 / 82 | Showers: light / moderate / violent |
| 85 / 86 | Snow showers | 95 / 96 / 99 | Thunderstorm (96, 99 with hail) |

## 5. Quick check: wttr.in

`https://wttr.in/<place>?format=%l:+%c+%t+%h+%w&m` gives one line for "what is
it like now" (`%c` condition, `%t` temperature, `%h` humidity, `%w` wind; `&m`
metric). Spaces as `+`; airport codes work. Its rain amounts undercount on wet
days: never quote a rain total from it.

## 6. Italian places: 3BMeteo

`https://www.3bmeteo.com/meteo/<city>` (lowercase, `+` for spaces: `reggio+emilia`) is an
HTML page with observations, snow line and alerts: good corroboration, read as
text. Use it to cross-check, not as the main numbers. (MeteoAM's city pages
need JavaScript and come back empty: don't fetch them.)

## 7. Air quality

`https://air-quality-api.open-meteo.com/v1/air-quality?latitude=<lat>&longitude=<lon>&timezone=<tz>&hourly=pm10,pm2_5,european_aqi`
when the question is about air, smog or exercising outside.

## How to answer

- Local clock times ("14:00"), and the timezone said once.
- Hour by hour as a **table**, never prose per hour. Cover the hours the
  question is about; for "how is today", the rest of the day in 2–3 hour steps.
- Give the day's min and max, and rain as the range across models.
- Mention sunrise and sunset when the answer is about being outside.
- When sources disagree, show it; don't average it away.
- If a later source contradicts a figure you gave earlier, correct it plainly.
