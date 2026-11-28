pragma Singleton
import Quickshell
/**
 * The shell's UI text goes through tr(), the one place a translation would plug in. The UI is English only,
 * so it returns the text as it is (the old lookup read an en_US.json that mapped every string to itself).
 */
Singleton {
    function tr(text) {
        return text ? text.toString() : "";
    }
}
