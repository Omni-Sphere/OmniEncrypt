#include "Base64.hpp"
#include "html_content.h"
#include "webview/webview.h"
#include <algorithm>
#include <boost/json.hpp>
#include <string>

// Helpers

std::string extract_input(const std::string &raw_req) {
  try {
    auto value = boost::json::parse(raw_req);
    if (value.is_array() && !value.as_array().empty()) {
      auto first = value.as_array()[0];
      if (first.is_string())
        return std::string(first.as_string());
    } else if (value.is_string())
      return std::string(value.as_string());
  } catch (...) {
  }
  if (raw_req.size() >= 2 && raw_req.front() == '"' && raw_req.back() == '"')
    return raw_req.substr(1, raw_req.size() - 2);
  return raw_req;
}

std::string to_json_result(const std::string &s) {
  return boost::json::serialize(boost::json::string(s));
}

int main() {
  omnisphere::utils::Base64::SetSecret(".:d0mn15ph3r3b:.");
  webview::webview w(false, nullptr);
  w.set_title("OmniEncrypt");

  w.set_size(900, 530, WEBVIEW_HINT_FIXED);

  w.bind("omni_encrypt", [&](const std::string &req) -> std::string {
    try {
      std::string res = omnisphere::utils::Base64::Encode(extract_input(req));
      return to_json_result(res);
    } catch (const std::exception &e) {
      return to_json_result("Error: " + std::string(e.what()));
    }
  });

  w.bind("omni_decrypt", [&](const std::string &req) -> std::string {
    try {
      std::string res = omnisphere::utils::Base64::Decode(extract_input(req));
      return to_json_result(res);
    } catch (const std::exception &e) {
      return to_json_result("Error: " + std::string(e.what()));
    }
  });

  w.bind("omni_quit", [&](const std::string &) -> std::string {
    w.terminate();
    return "";
  });

  w.set_html(reinterpret_cast<const char *>(HTML_CONTENT));

  w.run();
  return 0;
}
