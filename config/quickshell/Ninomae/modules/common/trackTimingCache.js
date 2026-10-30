.pragma library

// One shared memory for every TrackTiming (the bar's, and the media drawer's, which is rebuilt each time
// it opens): track key → { length, anchorPos (s), anchorTime (ms), playing }
var tracks = {};
