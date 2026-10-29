#ifndef RUNNER_JSON_WRITER_H_
#define RUNNER_JSON_WRITER_H_

#include <flutter/encodable_value.h>

#include <string>

namespace nova {

// Serializes a Flutter message value (the player's creation params and
// commands) as JSON for the WebView2 player page. Strings are UTF-8; the
// output is safe inside a script (no raw '<', U+2028 or U+2029).
std::string ToJson(const flutter::EncodableValue& value);

// UTF-8 <-> UTF-16 for WebView2's wide-string APIs.
std::wstring Utf8ToWide(const std::string& utf8);
std::string WideToUtf8(const std::wstring& wide);

}  // namespace nova

#endif  // RUNNER_JSON_WRITER_H_
