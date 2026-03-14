module modules.json5;

import std.json;

/++
 + Parses a JSON5 string into a JSONValue.
 +/
JSONValue parseJSON5(string content) {
    // TODO: Implement actual JSON5 parsing logic.
    // Falls back to std.json.parseJSON for now.
    return parseJSON(content);
}

/++
 + Serializes a JSONValue into a JSON5 string.
 +/
string toJSON5(JSONValue value, bool pretty = true) {
    return value.toJSON(pretty);
}
