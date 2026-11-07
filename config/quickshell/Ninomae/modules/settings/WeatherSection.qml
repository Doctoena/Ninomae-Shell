import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The weather options (Settings → Bar & dock, the welcome window): on or off, your location or a city, units and
 * how often it updates.
 */
ContentSection {
    title: Translation.tr("Weather")
    spacing: 10
    ConfigSwitch {
        text: Translation.tr("Weather in the clock drawer")
        description: Translation.tr("Today's forecast when you open the clock")
        option: "bar.weather.enable"
    }
    ConfigSwitch {
        text: Translation.tr("Use my location")
        description: Translation.tr("Find where you are instead of using a city name")
        visible: Config.options.bar.weather.enable
        option: "bar.weather.enableGPS"
    }
    SettingRow { // Where to get the weather for, without location
        visible: Config.options.bar.weather.enable && !Config.options.bar.weather.enableGPS
        text: Translation.tr("City")
        description: Translation.tr("Where the forecast is for")
        StyledTextArea {
            Layout.preferredWidth: 260 // The row says what it is: no floating label
            text: WeatherLocation.city
            onTextChanged: if (text !== WeatherLocation.city) WeatherLocation.setCity(text)
        }
    }
    ConfigSwitch {
        text: Translation.tr("Fahrenheit")
        description: Translation.tr("°F and miles per hour instead of °C and km/h")
        visible: Config.options.bar.weather.enable
        option: "bar.weather.useUSCS"
    }
    ConfigSpinBox {
        text: Translation.tr("Update every")
        description: Translation.tr("How often the forecast refreshes")
        visible: Config.options.bar.weather.enable
        option: "bar.weather.fetchInterval"
        suffix: Translation.tr("minutes")
        from: 5
        to: 60
        stepSize: 5
    }
}
