pragma Singleton
// From https://github.com/caelestia-dots/shell (GPLv3)
import Quickshell
import QtQml

Singleton {
    id: root

    function getBluetoothDeviceMaterialSymbol(systemIconName: string): string {
        const iconName = (systemIconName || "").toLowerCase();

        if (iconName.includes("earbud") || iconName.includes("earphone") || iconName.includes("in-ear"))
            return "earbuds";
        if (iconName.includes("headset") || iconName.includes("headphones"))
            return "headphones";
        if (iconName.includes("speaker") || iconName.includes("audio"))
            return "speaker";
        if (iconName.includes("gamepad") || iconName.includes("gaming") || iconName.includes("joystick") || iconName.includes("controller"))
            return "gamepad";
        if (iconName.includes("phone"))
            return "phone";
        if (iconName.includes("tablet"))
            return "tablet";
        if (iconName.includes("computer") || iconName.includes("laptop"))
            return "computer";
        if (iconName.includes("printer"))
            return "print";
        if (iconName.includes("mouse"))
            return "mouse";
        if (iconName.includes("keyboard"))
            return "keyboard";
        return "bluetooth";
    }

    function isNight(): bool {
        const hour = new Date().getHours();
        return hour < 6 || hour >= 20;
    }

    // OpenWeatherMap condition ids, the provider Weather.qml queries.
    // Day/night variants only exist for clear and partly cloudy skies.
    // Every name below is a Material Symbols Rounded icon; an unknown id
    // falls back to the clear sky icon instead of rendering its name.
    function getWeatherIcon(code): string {
        const id = Number(code) || 0;
        const night = root.isNight();

        if (id >= 200 && id < 300) return "thunderstorm";
        if (id >= 300 && id < 400) return "rainy";
        if (id >= 500 && id < 600) {
            if (id === 511) return "weather_hail";            // freezing rain
            if (id >= 502 && id <= 504) return "weather_hail"; // heavy rain
            return "rainy";
        }
        if (id >= 600 && id < 700) {
            if (id >= 611 && id <= 616) return "weather_mix";  // sleet
            if (id === 602 || id === 622) return "snowing_heavy";
            if (id === 600 || id === 620) return "cloudy_snowing";
            return "snowing";
        }
        if (id >= 700 && id < 800) return "foggy";
        if (id === 800) return night ? "clear_night" : "clear_day";
        if (id === 801 || id === 802) return night ? "partly_cloudy_night" : "partly_cloudy_day";
        if (id >= 803 && id < 900) return "cloud";

        return night ? "clear_night" : "clear_day";
    }
}
