# Weather Assets

Pixel-art weather artwork with transparent backgrounds. Static and animated files share matching names.

- `Static/`: 10 PNG icons, each 1254 × 1254 pixels, RGBA transparency.
- `Animated/`: 10 GIF icons, each 256 × 256 pixels, 3 frames, transparent background, infinite loop.

| Filename stem | Weather | Animation | Loop duration |
| --- | --- | --- | --- |
| 01-rain | Rain | Falling rain | 0.54 s |
| 02-thunderstorm | Thunderstorm | Lightning flash | 0.85 s |
| 03-sun | Sunny | Pulsing sun rays | 0.84 s |
| 04-partly-cloudy | Partly cloudy | Small cloud and ray changes | 1.20 s |
| 05-wind | Windy | Flowing wind streaks | 0.60 s |
| 06-cloud | Cloudy | Drifting cloud | 1.35 s |
| 07-moon | Clear night | Twinkling stars | 1.50 s |
| 08-showers | Showers | Falling diagonal rain | 0.54 s |
| 09-rainbow | Rainbow | Subtle brightness pulse | 1.35 s |
| 10-snowflake | Snow | Gently swaying snowflake | 1.05 s |

Created from the user-provided weather reference using built-in imagegen. Background cleanup and GIF assembly used ImageMagick. PNG alpha, GIF frame count, dimensions, distinct frames, and infinite-loop metadata were checked before import.

These are standalone assets; application code is not changed by this import.
