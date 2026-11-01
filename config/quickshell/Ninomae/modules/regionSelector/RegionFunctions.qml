pragma Singleton
import Quickshell
Singleton {
    id: root
    function intersectionOverUnion(regionA, regionB) {
        // region: { at: [x, y], size: [w, h] }
        const ax1 = regionA.at[0], ay1 = regionA.at[1];
        const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
        const bx1 = regionB.at[0], by1 = regionB.at[1];
        const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];
        const interX1 = Math.max(ax1, bx1);
        const interY1 = Math.max(ay1, by1);
        const interX2 = Math.min(ax2, bx2);
        const interY2 = Math.min(ay2, by2);
        const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
        const areaA = (ax2 - ax1) * (ay2 - ay1);
        const areaB = (bx2 - bx1) * (by2 - by1);
        const unionArea = areaA + areaB - interArea;
        return unionArea > 0 ? interArea / unionArea : 0;
    }
    // Of pictures that overlap, only the smallest stays (the most specific one to click)
    function filterOverlappingImageRegions(regions) {
        const area = r => r.size[0] * r.size[1];
        const removed = new Set();
        for (let i = 0; i < regions.length; ++i) {
            for (let j = i + 1; j < regions.length && !removed.has(i); ++j) {
                if (removed.has(j) || intersectionOverUnion(regions[i], regions[j]) <= 0) continue;
                removed.add(area(regions[i]) <= area(regions[j]) ? j : i);
            }
        }
        return regions.filter((_, i) => !removed.has(i));
    }
    // Windows under a popup or the sidebar aren't offered: the popup is what shows there
    function filterWindowRegionsByLayers(windowRegions, layerRegions) {
        return windowRegions.filter(w => !layerRegions.some(l => intersectionOverUnion(w, l) > 0));
    }
    function contains(region, x, y) {
        return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
    }
    // Pictures found in the frame worth a click: inside a window or popup (on the bare wallpaper it finds
    // shapes in the art), and not just the window itself again
    function filterImageRegions(regions, windowRegions, layerRegions = [], threshold = 0.1) {
        const surfaces = windowRegions.concat(layerRegions);
        const filtered = regions.filter(region => {
            const cx = region.at[0] + region.size[0] / 2, cy = region.at[1] + region.size[1] / 2;
            if (!surfaces.some(s => contains(s, cx, cy))) return false;
            return !windowRegions.some(w => intersectionOverUnion(region, w) > threshold);
        });
        return filterOverlappingImageRegions(filtered);
    }
}
