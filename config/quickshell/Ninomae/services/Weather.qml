pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning
import qs.modules.common
/**
 * Current weather and the next hours from Open-Meteo (no API key; wttr.in kept timing out).
 * Location is the configured city (looked up once with Open-Meteo's geocoder) or GPS.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options.bar.weather.enable
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    property bool gpsActive: Config.options.bar.weather.enableGPS

    // Where to fetch for. Plain properties (not one object mutated in place) so bindings notice changes
    property real lat: 0
    property real lon: 0
    property bool locationValid: false
    property string resolvedCity: ""
    property string _geocodedCity: "" // The city `lat`/`lon` were looked up for

    // `real`, not `int`: Date.now() doesn't fit in 32 bits, which made the cache never hit
    property real _lastFetchTime: 0
    property string _lastKey: ""

    property var data: ({
        uv: 0,
        humidity: "",
        windDir: "N",
        icon: "cloud",
        condition: "",
        city: "",
        wind: "",
        temp: "",
        tempFeelsLike: "",
        isDay: true,
        high: "",
        low: "",
        hourly: [],    // [{ time: Date, icon, temp, pop }] for the next 12 hours from the fetch
        sunEvents: []  // [{ sunrise: bool, time: Date }] today and tomorrow, in order
    })

    onUseUSCSChanged: getData(true)
    onCityChanged: {
        if (root.gpsActive) return;
        root.locationValid = false;
        getData(true);
    }
    onEnabledChanged: if (enabled) getData()

    function getData(force = false) {
        if (!root.enabled) return;
        if (!root.gpsActive) {
            if (!root.city || root.city.trim().length === 0) {
                console.warn("[WeatherService] No GPS location and no city configured, skipping fetch");
                return;
            }
            if (!root.locationValid || root._geocodedCity !== root.city) {
                geocode();
                return; // fetch() runs once the coordinates are known
            }
        } else if (!root.locationValid) {
            return; // Waiting for the first GPS fix
        }
        const key = `${root.lat},${root.lon},${root.useUSCS}`;
        if (!force && key === root._lastKey && Date.now() - root._lastFetchTime < root.fetchInterval) return;
        fetch(key);
    }

    function geocode() {
        if (geoProc.running) return;
        geoProc.lookingUp = root.city;
        geoProc.command = ["curl", "-sf", "--max-time", "15",
            `https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(root.city.trim())}`];
        geoProc.running = true;
    }
    Process {
        id: geoProc
        property string lookingUp
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) { // Offline (usually the network isn't up yet at login)
                    retryTimer.restart();
                    return;
                }
                try {
                    const place = JSON.parse(text).results?.[0];
                    if (!place) {
                        console.warn(`[WeatherService] City not found: ${geoProc.lookingUp}`);
                        return;
                    }
                    root.lat = place.latitude;
                    root.lon = place.longitude;
                    root.resolvedCity = place.name;
                    root._geocodedCity = geoProc.lookingUp;
                    root.locationValid = true;
                    root.getData(true);
                } catch (e) {
                    console.warn(`[WeatherService] Geocoding failed: ${e.message}`);
                    retryTimer.restart();
                }
            }
        }
    }

    function fetch(key) {
        if (weatherProc.running) return;
        const units = root.useUSCS ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "";
        weatherProc.key = key;
        weatherProc.command = ["curl", "-sf", "--max-time", "20", "https://api.open-meteo.com/v1/forecast"
            + `?latitude=${root.lat}&longitude=${root.lon}&timezone=auto&forecast_days=2&forecast_hours=12${units}`
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,"
            + "wind_direction_10m,uv_index"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day"
            + "&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min"];
        weatherProc.running = true;
    }
    Process {
        id: weatherProc
        property string key
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    console.warn("[WeatherService] No response from Open-Meteo");
                    retryTimer.restart();
                    return;
                }
                try {
                    root.refineData(JSON.parse(text));
                    root._lastKey = weatherProc.key;
                    root._lastFetchTime = Date.now();
                } catch (e) {
                    console.error(`[WeatherService] JSON parse error: ${e.message}`);
                }
            }
        }
    }

    // WMO weather code → Material Symbol and description (https://open-meteo.com/en/docs)
    function wmoInfo(code, isDay) {
        if (code === 0) return [isDay ? "clear_day" : "clear_night", Translation.tr("Clear")];
        if (code === 1) return [isDay ? "clear_day" : "clear_night", Translation.tr("Mainly clear")];
        if (code === 2) return [isDay ? "partly_cloudy_day" : "partly_cloudy_night", Translation.tr("Partly cloudy")];
        if (code === 3) return ["cloud", Translation.tr("Overcast")];
        if (code === 45 || code === 48) return ["foggy", Translation.tr("Fog")];
        if (code >= 51 && code <= 55) return ["rainy", Translation.tr("Drizzle")];
        if (code === 56 || code === 57) return ["weather_hail", Translation.tr("Freezing drizzle")];
        if (code === 61) return ["rainy", Translation.tr("Light rain")];
        if (code === 63) return ["rainy", Translation.tr("Rain")];
        if (code === 65) return ["rainy", Translation.tr("Heavy rain")];
        if (code === 66 || code === 67) return ["weather_hail", Translation.tr("Freezing rain")];
        if (code === 71) return ["cloudy_snowing", Translation.tr("Light snow")];
        if (code === 73) return ["snowing", Translation.tr("Snow")];
        if (code === 75) return ["snowing_heavy", Translation.tr("Heavy snow")];
        if (code === 77) return ["snowing", Translation.tr("Snow grains")];
        if (code >= 80 && code <= 82) return ["rainy", Translation.tr("Rain showers")];
        if (code === 85 || code === 86) return ["cloudy_snowing", Translation.tr("Snow showers")];
        if (code === 95) return ["thunderstorm", Translation.tr("Thunderstorm")];
        if (code === 96 || code === 99) return ["thunderstorm", Translation.tr("Thunderstorm with hail")];
        return ["cloud", Translation.tr("Unknown")];
    }
    function compassPoint(degrees) {
        const points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        return points[Math.round(((degrees ?? 0) % 360) / 22.5) % 16];
    }

    function refineData(json) {
        const c = json.current ?? {};
        const u = json.current_units ?? {};
        const [icon, condition] = wmoInfo(c.weather_code, c.is_day !== 0);
        const round = v => Math.round(v ?? 0);
        const h = json.hourly ?? {};
        const d = json.daily ?? {};
        const hourly = (h.time ?? []).map((t, i) => ({
            time: new Date(t), // Local wall time (timezone=auto)
            icon: wmoInfo(h.weather_code?.[i], h.is_day?.[i] !== 0)[0],
            temp: `${round(h.temperature_2m?.[i])}°`,
            pop: h.precipitation_probability?.[i] ?? 0
        }));
        const sunEvents = []; // No flatMap in QML's JS engine
        (d.sunrise ?? []).forEach((rise, i) => {
            sunEvents.push({ sunrise: true, time: new Date(rise) });
            if (d.sunset?.[i]) sunEvents.push({ sunrise: false, time: new Date(d.sunset[i]) });
        });
        root.data = {
            uv: Math.round((c.uv_index ?? 0) * 10) / 10,
            humidity: `${round(c.relative_humidity_2m)}%`,
            windDir: compassPoint(c.wind_direction_10m),
            icon: icon,
            condition: condition,
            city: root.resolvedCity || root.city || Translation.tr("City"),
            wind: `${round(c.wind_speed_10m)} ${u.wind_speed_10m ?? "km/h"}`,
            temp: `${round(c.temperature_2m)}${u.temperature_2m ?? "°C"}`,
            tempFeelsLike: `${round(c.apparent_temperature)}${u.apparent_temperature ?? "°C"}`,
            isDay: c.is_day !== 0,
            high: d.temperature_2m_max ? `${round(d.temperature_2m_max[0])}°` : "",
            low: d.temperature_2m_min ? `${round(d.temperature_2m_min[0])}°` : "",
            hourly: hourly,
            sunEvents: sunEvents
        };
    }

    // GPS: coordinates from the position service, the place name from OpenStreetMap
    Process {
        id: reverseGeoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const addr = JSON.parse(text).address || {};
                    const name = addr.city || addr.town || addr.village || addr.municipality || addr.locality || addr.state || "";
                    if (name.length > 0) root.resolvedCity = name;
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: {
        if (!root.gpsActive || !root.enabled) return;
        console.info("[WeatherService] Starting the GPS service.");
        positionSource.start();
    }
    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                root.lat = position.coordinate.latitude;
                root.lon = position.coordinate.longitude;
                root.locationValid = true;
                reverseGeoProc.command = ["curl", "-sf", "--max-time", "15", "-A", "Ninomae-Shell/1.0",
                    `https://nominatim.openstreetmap.org/reverse?lat=${root.lat}&lon=${root.lon}&format=json`];
                reverseGeoProc.running = true;
                root.getData();
            } else {
                // Keep using the last valid location; give up on GPS if there never was one
                root.gpsActive = root.locationValid;
                console.error("[WeatherService] Failed to get the GPS location.");
            }
        }
        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop();
                root.locationValid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", "-a", "Weather", Translation.tr("Weather Service"), Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not aquire a valid backend plugin.");
            }
        }
    }
    Timer {
        // A failed lookup tries again soon instead of waiting a whole fetchInterval
        id: retryTimer
        interval: 30000
        onTriggered: root.getData(true)
    }
    Timer {
        // GPS mode refreshes from position updates; the city mode polls. Nothing runs while disabled
        running: root.enabled && !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: true
        onTriggered: root.getData()
    }
}
