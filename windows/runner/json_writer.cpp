#include "json_writer.h"

#include <windows.h>

#include <cmath>
#include <cstdio>

namespace nova {

namespace {

void AppendString(std::string& out, const std::string& value) {
  out.push_back('"');
  for (size_t i = 0; i < value.size(); ++i) {
    const unsigned char c = static_cast<unsigned char>(value[i]);
    if (c == '"') {
      out += "\\\"";
    } else if (c == '\\') {
      out += "\\\\";
    } else if (c == '\n') {
      out += "\\n";
    } else if (c == '\r') {
      out += "\\r";
    } else if (c == '\t') {
      out += "\\t";
    } else if (c == '<') {
      out += "\\u003c";
    } else if (c < 0x20) {
      char buffer[8];
      std::snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<unsigned int>(c));
      out += buffer;
    } else if (c == 0xE2 && i + 2 < value.size() &&
               static_cast<unsigned char>(value[i + 1]) == 0x80 &&
               (static_cast<unsigned char>(value[i + 2]) == 0xA8 ||
                static_cast<unsigned char>(value[i + 2]) == 0xA9)) {
      // U+2028 / U+2029 end a line in JavaScript source.
      out += static_cast<unsigned char>(value[i + 2]) == 0xA8 ? "\\u2028"
                                                              : "\\u2029";
      i += 2;
    } else {
      out.push_back(static_cast<char>(c));
    }
  }
  out.push_back('"');
}

void AppendDouble(std::string& out, double value) {
  if (!std::isfinite(value)) {
    out += "null";
    return;
  }
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%.17g", value);
  out += buffer;
}

void Append(std::string& out, const flutter::EncodableValue& value) {
  if (const auto* flag = std::get_if<bool>(&value)) {
    out += *flag ? "true" : "false";
  } else if (const auto* int32_value = std::get_if<int32_t>(&value)) {
    out += std::to_string(*int32_value);
  } else if (const auto* large = std::get_if<int64_t>(&value)) {
    out += std::to_string(*large);
  } else if (const auto* number = std::get_if<double>(&value)) {
    AppendDouble(out, *number);
  } else if (const auto* text = std::get_if<std::string>(&value)) {
    AppendString(out, *text);
  } else if (const auto* list = std::get_if<flutter::EncodableList>(&value)) {
    out.push_back('[');
    bool first = true;
    for (const flutter::EncodableValue& item : *list) {
      if (!first) {
        out.push_back(',');
      }
      first = false;
      Append(out, item);
    }
    out.push_back(']');
  } else if (const auto* map = std::get_if<flutter::EncodableMap>(&value)) {
    out.push_back('{');
    bool first = true;
    for (const auto& entry : *map) {
      const auto* name = std::get_if<std::string>(&entry.first);
      if (name == nullptr) {
        continue;
      }
      if (!first) {
        out.push_back(',');
      }
      first = false;
      AppendString(out, *name);
      out.push_back(':');
      Append(out, entry.second);
    }
    out.push_back('}');
  } else {
    // null and the typed lists the player never receives.
    out += "null";
  }
}

}  // namespace

std::string ToJson(const flutter::EncodableValue& value) {
  std::string out;
  Append(out, value);
  return out;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                           static_cast<int>(utf8.size()),
                                           nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), length);
  return wide;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int length = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                           static_cast<int>(wide.size()),
                                           nullptr, 0, nullptr, nullptr);
  if (length <= 0) {
    return std::string();
  }
  std::string utf8(static_cast<size_t>(length), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        utf8.data(), length, nullptr, nullptr);
  return utf8;
}

}  // namespace nova
